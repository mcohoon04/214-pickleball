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

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
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
                // Hour label
                Text(Self.hourFormatter.string(from: slot.date))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(isPast ? Theme.disabled : Theme.textSecondary)
                    .frame(width: 50, alignment: .trailing)

                if slot.isAvailable {
                    // Available slot
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
                } else if let bwp = slot.booking {
                    // Booked slot
                    HStack {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 4) {
                            if isMyBooking {
                                Text("Your Booking")
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(bwp.players.map(\.displayName).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.textSecondary)
                            .font(.caption)
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
