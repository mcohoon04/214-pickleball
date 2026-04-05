import Foundation
import Supabase

@Observable
final class BookingService {
    var bookingsForMonth: [Booking] = []
    var bookingsForDay: [BookingWithPlayers] = []
    var allPlayers: [PlayerInfo] = []

    private let supabase = SupabaseConfig.client
    private let torontoTZ = TimeZone(identifier: "America/Toronto")!

    func fetchBookingsForMonth(year: Int, month: Int) async throws {
        var cal = Calendar.current
        cal.timeZone = torontoTZ
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
        var cal = Calendar.current
        cal.timeZone = torontoTZ
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return }

        // Fetch bookings
        let bookings: [Booking] = try await supabase
            .from("bookings")
            .select()
            .eq("status", value: "active")
            .gte("starts_at", value: dayStart.ISO8601Format())
            .lt("starts_at", value: dayEnd.ISO8601Format())
            .order("starts_at")
            .execute()
            .value

        // Fetch players for each booking
        var result: [BookingWithPlayers] = []
        for booking in bookings {
            let bpRows: [BookingPlayer] = try await supabase
                .from("booking_players")
                .select()
                .eq("booking_id", value: booking.id)
                .execute()
                .value

            var players: [PlayerInfo] = []
            for bp in bpRows {
                if let player = allPlayers.first(where: { $0.id == bp.playerId }) {
                    players.append(player)
                }
            }
            result.append(BookingWithPlayers(booking: booking, players: players))
        }

        await MainActor.run { self.bookingsForDay = result }
    }

    func fetchAllPlayers() async throws {
        let players: [PlayerInfo] = try await supabase
            .rpc("list_players")
            .execute()
            .value
        await MainActor.run { self.allPlayers = players }
    }

    func createBooking(startsAt: Date, endsAt: Date, playerIds: [UUID]) async throws -> UUID {
        struct Params: Encodable {
            let p_starts_at: String
            let p_ends_at: String
            let p_player_ids: [UUID]
        }

        let result: UUID = try await supabase
            .rpc("create_booking", params: Params(
                p_starts_at: startsAt.ISO8601Format(),
                p_ends_at: endsAt.ISO8601Format(),
                p_player_ids: playerIds
            ))
            .execute()
            .value
        return result
    }

    /// Returns available end times for a booking starting at `startHour` on `date`.
    /// Ranges from startHour+1 up to the next existing booking or 9 PM (hour 21), max 4 hours.
    func availableEndTimes(date: Date, startHour: Int) -> [Date] {
        var cal = Calendar.current
        cal.timeZone = torontoTZ
        let dayStart = cal.startOfDay(for: date)

        // Find the next booking after startHour on this day
        let nextBookingHour = bookingsForDay
            .map { bwp -> Int in
                var c = Calendar.current
                c.timeZone = torontoTZ
                return c.component(.hour, from: bwp.booking.startsAt)
            }
            .filter { $0 > startHour }
            .sorted()
            .first ?? 21 // 9 PM end of court hours

        let maxEndHour = min(nextBookingHour, startHour + 4, 21) // cap at 4 hours and 9 PM

        return ((startHour + 1)...maxEndHour).compactMap { hour in
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart)
        }
    }

    func cancelBooking(id: UUID) async throws {
        try await supabase
            .from("bookings")
            .update(["status": "cancelled"])
            .eq("id", value: id)
            .execute()
    }

    func leaveBooking(bookingId: UUID, playerId: UUID) async throws {
        try await supabase
            .from("booking_players")
            .delete()
            .eq("booking_id", value: bookingId)
            .eq("player_id", value: playerId)
            .execute()
    }

    func addPlayerToBooking(bookingId: UUID, playerId: UUID, addedBy: UUID) async throws {
        try await supabase
            .from("booking_players")
            .insert(BookingPlayer(bookingId: bookingId, playerId: playerId, addedBy: addedBy))
            .execute()
    }

    func timeSlotsForDay(date: Date) -> [TimeSlot] {
        var cal = Calendar.current
        cal.timeZone = torontoTZ
        let dayStart = cal.startOfDay(for: date)

        return (5...20).map { hour in
            let slotDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart)!
            // Match any booking whose range covers this hour (start <= hour < end)
            let match = bookingsForDay.first { bwp in
                var c = Calendar.current
                c.timeZone = torontoTZ
                let startHour = c.component(.hour, from: bwp.booking.startsAt)
                let endHour = c.component(.hour, from: bwp.booking.endsAt)
                let sameDay = c.isDate(bwp.booking.startsAt, inSameDayAs: date)
                return sameDay && hour >= startHour && hour < endHour
            }
            return TimeSlot(hour: hour, date: slotDate, booking: match)
        }
    }
}
