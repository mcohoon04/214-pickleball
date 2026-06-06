import SwiftUI

struct TimeSlotRow: View {
    let slot: TimeSlot
    let currentUserId: UUID?
    let onTapAvailable: () -> Void
    let onTapBooked: () -> Void

    private var isPast: Bool {
        slot.date < Date()
    }

    private var isMyBooking: Bool {
        slot.booking?.booking.createdBy == currentUserId
    }

    private var isBookingStart: Bool {
        guard let bwp = slot.booking else { return false }
        return abs(bwp.booking.startsAt.timeIntervalSince(slot.date)) < 1
    }

    private var bookingDurationLabel: String? {
        guard isBookingStart, let bwp = slot.booking else { return nil }
        let mins = Int(bwp.booking.endsAt.timeIntervalSince(bwp.booking.startsAt) / 60)
        guard mins > 30 else { return nil }
        let h = mins / 60
        let m = mins % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)hr" }
        return "\(h)hr \(m)m"
    }

    private var playersLabel: String {
        guard let bwp = slot.booking else { return "" }
        return bwp.players
            .map { $0.isGuest ? "\($0.displayName) (guest)" : $0.displayName }
            .joined(separator: ", ")
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    var body: some View {
        Button {
            if slot.isAvailable {
                onTapAvailable()
            } else {
                onTapBooked()
            }
        } label: {
            HStack(spacing: 12) {
                // Time label
                Text(Self.hourFormatter.string(from: slot.date))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(isPast ? Theme.disabled : Theme.textSecondary)
                    .frame(width: 64, alignment: .trailing)

                if slot.isAvailable {
                    HStack {
                        Text("Available")
                            .font(.subheadline)
                            .foregroundStyle(isPast ? Theme.disabled : Theme.accent)
                        Spacer()
                        if !isPast {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Theme.surface)
                    .cornerRadius(Theme.cornerRadius)
                } else if let _ = slot.booking {
                    HStack {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if isMyBooking && isBookingStart {
                                    Text("Your Booking")
                                        .font(.caption.bold())
                                        .foregroundStyle(Theme.accent)
                                }
                                if let dur = bookingDurationLabel {
                                    Text(dur)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Theme.surface)
                                        .cornerRadius(4)
                                }
                            }
                            if isBookingStart {
                                Text(playersLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                            } else {
                                Text("continued")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .italic()
                            }
                        }

                        Spacer()

                        if isBookingStart {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textSecondary)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Theme.surfaceLight)
                    .cornerRadius(Theme.cornerRadius)
                }
            }
        }
        .disabled(isPast)
        .opacity(isPast ? 0.5 : 1)
    }
}
