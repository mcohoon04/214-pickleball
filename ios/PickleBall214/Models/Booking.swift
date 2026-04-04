import Foundation

struct Booking: Codable, Identifiable, Hashable {
    let id: UUID
    let createdBy: UUID
    let startsAt: Date
    let endsAt: Date
    let status: BookingStatus
    let cancelledAt: Date?
    let cancelledBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case createdBy = "created_by"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case cancelledAt = "cancelled_at"
        case cancelledBy = "cancelled_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum BookingStatus: String, Codable, Hashable {
    case active
    case cancelled
}

struct BookingWithPlayers: Identifiable, Hashable {
    let booking: Booking
    let players: [PlayerInfo]
    var id: UUID { booking.id }
}

struct BookingPlayer: Codable {
    let bookingId: UUID
    let playerId: UUID
    let addedBy: UUID

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case playerId = "player_id"
        case addedBy = "added_by"
    }
}

struct TimeSlot: Identifiable, Hashable {
    let hour: Int
    let date: Date
    var booking: BookingWithPlayers?
    var id: String { "\(date.timeIntervalSince1970)-\(hour)" }
    var isAvailable: Bool { booking == nil }
}
