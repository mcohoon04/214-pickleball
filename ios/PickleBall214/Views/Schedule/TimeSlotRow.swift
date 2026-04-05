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
        let cal = Calendar.current
        return cal.component(.hour, from: bwp.booking.startsAt) == slot.hour
    }

    private var bookingDurationLabel: String? {
        guard isBookingStart, let bwp = slot.booking else { return nil }
        let hours = Calendar.current.dateComponents([.hour], from: bwp.booking.startsAt, to: bwp.booking.endsAt).hour ?? 1
        return hours > 1 ? "\(hours)hr" : nil
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
                                Text(bwp.players.map(\.displayName).joined(separator: ", "))
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
