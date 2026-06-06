import Foundation
import Supabase

@Observable
final class BookingService {
    var bookingsForMonth: [Booking] = []
    var bookingsForDay: [BookingWithPlayers] = []
    var allPlayers: [PlayerInfo] = []

    private let supabase = SupabaseConfig.client
    private let torontoTZ = TimeZone(identifier: "America/Toronto")!

    private var torontoCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = torontoTZ
        return cal
    }

    func fetchBookingsForMonth(year: Int, month: Int) async throws {
        let cal = torontoCalendar
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.timeZone = torontoTZ

        guard let monthStart = cal.date(from: components),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else { return }

        let bookings: [Booking] = try await supabase
            .from("bookings")
            .select()
            .eq("status", value: "active")
            .gte("starts_at", value: monthStart.ISO8601Format())
            .lt("starts_at", value: monthEnd.ISO8601Format())
            .execute()
            .value

        await MainActor.run { self.bookingsForMonth = bookings }
    }

    func fetchBookingsForDay(date: Date) async throws {
        let cal = torontoCalendar
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }

        let bookings: [Booking] = try await supabase
            .from("bookings")
            .select()
            .eq("status", value: "active")
            .gte("starts_at", value: dayStart.ISO8601Format())
            .lt("starts_at", value: dayEnd.ISO8601Format())
            .order("starts_at")
            .execute()
            .value

        var result: [BookingWithPlayers] = []
        for booking in bookings {
            let participants = try await fetchParticipants(bookingId: booking.id)
            result.append(BookingWithPlayers(booking: booking, players: participants))
        }

        await MainActor.run { self.bookingsForDay = result }
    }

    /// Loads the participants for one booking (real players + guests), ordered by add time.
    func fetchParticipants(bookingId: UUID) async throws -> [BookingParticipant] {
        let rows: [BookingPlayer] = try await supabase
            .from("booking_players")
            .select()
            .eq("booking_id", value: bookingId)
            .order("created_at")
            .execute()
            .value
        return rows.map { bp in
            if let pid = bp.playerId {
                let info = allPlayers.first(where: { $0.id == pid })
                return BookingParticipant(
                    rowId: bp.id,
                    userId: pid,
                    displayName: info?.displayName ?? "Player",
                    avatarUrl: info?.avatarUrl,
                    isGuest: false
                )
            } else {
                return BookingParticipant(
                    rowId: bp.id,
                    userId: nil,
                    displayName: bp.guestName ?? "Guest",
                    avatarUrl: nil,
                    isGuest: true
                )
            }
        }
    }

    func fetchAllPlayers() async throws {
        let players: [PlayerInfo] = try await supabase
            .rpc("list_players")
            .execute()
            .value
        await MainActor.run { self.allPlayers = players }
    }

    func createBooking(startsAt: Date, endsAt: Date, playerIds: [UUID], guestNames: [String]) async throws -> UUID {
        struct Params: Encodable {
            let p_starts_at: String
            let p_ends_at: String
            let p_player_ids: [UUID]
            let p_guest_names: [String]
        }

        let result: UUID = try await supabase
            .rpc("create_booking", params: Params(
                p_starts_at: startsAt.ISO8601Format(),
                p_ends_at: endsAt.ISO8601Format(),
                p_player_ids: playerIds,
                p_guest_names: guestNames
            ))
            .execute()
            .value
        return result
    }

    /// Available end times for a booking starting at `start`, in 30-minute steps.
    /// Capped by the next existing booking, 9 PM, and a 4-hour maximum.
    func availableEndTimes(start: Date) -> [Date] {
        let cal = torontoCalendar
        let dayStart = cal.startOfDay(for: start)
        guard let close = cal.date(bySettingHour: 21, minute: 0, second: 0, of: dayStart) else { return [] }

        let maxByDuration = start.addingTimeInterval(4 * 3600)
        let nextStart = bookingsForDay
            .map { $0.booking.startsAt }
            .filter { $0 > start }
            .min() ?? close

        let upper = min(close, maxByDuration, nextStart)

        var result: [Date] = []
        var t = start.addingTimeInterval(30 * 60)
        while t <= upper {
            result.append(t)
            t = t.addingTimeInterval(30 * 60)
        }
        return result
    }

    func cancelBooking(id: UUID) async throws {
        try await supabase
            .from("bookings")
            .update(["status": "cancelled"])
            .eq("id", value: id)
            .execute()
    }

    /// Removes a participant row (real player or guest) by its booking_players id.
    func removeParticipant(rowId: UUID) async throws {
        try await supabase
            .from("booking_players")
            .delete()
            .eq("id", value: rowId)
            .execute()
    }

    func addPlayerToBooking(bookingId: UUID, playerId: UUID, addedBy: UUID) async throws {
        try await supabase
            .from("booking_players")
            .insert(BookingPlayerInsert(bookingId: bookingId, playerId: playerId, addedBy: addedBy))
            .execute()
    }

    func addGuestToBooking(bookingId: UUID, guestName: String, addedBy: UUID) async throws {
        let trimmed = String(guestName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        let name = trimmed.isEmpty ? "Guest" : trimmed
        try await supabase
            .from("booking_players")
            .insert(GuestPlayerInsert(bookingId: bookingId, guestName: name, addedBy: addedBy))
            .execute()
    }

    /// 30-minute slots from 5:00 AM through 8:30 PM Toronto time (32 rows).
    func timeSlotsForDay(date: Date) -> [TimeSlot] {
        let cal = torontoCalendar
        let dayStart = cal.startOfDay(for: date)

        var slots: [TimeSlot] = []
        // 5:00 AM (open) up to 8:30 PM — 16 hours * 2 = 32 half-hour steps.
        for step in 0..<32 {
            let minutesFromOpen = step * 30
            let hour = 5 + minutesFromOpen / 60
            let minute = minutesFromOpen % 60
            guard let slotDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) else { continue }
            let match = bookingsForDay.first { bwp in
                slotDate >= bwp.booking.startsAt && slotDate < bwp.booking.endsAt
            }
            slots.append(TimeSlot(date: slotDate, booking: match))
        }
        return slots
    }
}
