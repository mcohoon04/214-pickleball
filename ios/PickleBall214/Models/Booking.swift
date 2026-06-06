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
    let players: [BookingParticipant]
    var id: UUID { booking.id }
}

/// A participant in a booking — either a real user or a guest (no account).
struct BookingParticipant: Identifiable, Hashable {
    let rowId: UUID        // booking_players.id (used for removal)
    let userId: UUID?      // player_id — nil for guests
    let displayName: String
    let avatarUrl: String?
    let isGuest: Bool

    var id: UUID { rowId }
}

/// Raw booking_players row (decode only). `playerId` is nil for guest rows.
struct BookingPlayer: Codable {
    let id: UUID
    let bookingId: UUID
    let playerId: UUID?
    let guestName: String?
    let addedBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case bookingId = "booking_id"
        case playerId = "player_id"
        case guestName = "guest_name"
        case addedBy = "added_by"
    }
}

/// Insert payload for adding a real player to an existing booking.
struct BookingPlayerInsert: Encodable {
    let bookingId: UUID
    let playerId: UUID
    let addedBy: UUID

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case playerId = "player_id"
        case addedBy = "added_by"
    }
}

/// Insert payload for adding a guest to an existing booking.
struct GuestPlayerInsert: Encodable {
    let bookingId: UUID
    let guestName: String
    let addedBy: UUID

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case guestName = "guest_name"
        case addedBy = "added_by"
    }
}

/// One 30-minute slot on the day schedule, keyed on its exact start instant.
struct TimeSlot: Identifiable, Hashable {
    let date: Date          // exact slot start (Toronto wall-clock instant)
    var booking: BookingWithPlayers?
    var id: String { "\(date.timeIntervalSince1970)" }
    var isAvailable: Bool { booking == nil }
}
