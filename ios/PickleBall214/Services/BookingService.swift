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

    func createBooking(startsAt: Date, playerIds: [UUID]) async throws -> UUID {
        struct Params: Encodable {
            let p_starts_at: String
            let p_player_ids: [UUID]
        }

        let result: UUID = try await supabase
            .rpc("create_booking", params: Params(
                p_starts_at: startsAt.ISO8601Format(),
                p_player_ids: playerIds
            ))
            .execute()
            .value
        return result
    }

    func cancelBooking(id: UUID) async throws {
        try await supabase
            .from("bookings")
            .update(["status": "cancelled"])
            .eq("id", value: id)
            .execute()
    }

    func timeSlotsForDay(date: Date) -> [TimeSlot] {
        var cal = Calendar.current
        cal.timeZone = torontoTZ
        let dayStart = cal.startOfDay(for: date)

        return (5...20).map { hour in
            let slotDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart)!
            let match = bookingsForDay.first { bwp in
                var c = Calendar.current
                c.timeZone = torontoTZ
                let bookingHour = c.component(.hour, from: bwp.booking.startsAt)
                return c.isDate(bwp.booking.startsAt, inSameDayAs: date) && bookingHour == hour
            }
            return TimeSlot(hour: hour, date: slotDate, booking: match)
        }
    }
}
