import SwiftUI

struct BookingDetailView: View {
    let booking: BookingWithPlayers
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @State private var showCancelConfirm = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isCreator: Bool {
        booking.booking.createdBy == authService.currentUser?.id
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    var body: some View {
        VStack(spacing: 24) {
            // Date & Time card
            VStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: booking.booking.startsAt))
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)

                HStack {
                    Text(Self.timeFormatter.string(from: booking.booking.startsAt))
                    Text("–")
                    Text(Self.timeFormatter.string(from: booking.booking.endsAt))
                }
                .font(.title3)
                .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Theme.surface)
            .cornerRadius(Theme.cornerRadius)

            // Players
            VStack(alignment: .leading, spacing: 12) {
                Text("Players")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                ForEach(booking.players) { player in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.accent.opacity(0.2))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String(player.displayName.prefix(1)).uppercased())
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Theme.accent)
                            )

                        Text(player.displayName)
                            .foregroundStyle(Theme.textPrimary)

                        if player.id == booking.booking.createdBy {
                            Text("Organizer")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Theme.surfaceLight)
                                .cornerRadius(4)
                        }

                        Spacer()
                    }
                }
            }
            .padding(Theme.padding)
            .background(Theme.surface)
            .cornerRadius(Theme.cornerRadius)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
            }

            Spacer()

            // Cancel button (only for creator)
            if isCreator {
                Button {
                    showCancelConfirm = true
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Cancel Booking")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.destructive)
                    .foregroundStyle(.white)
                    .cornerRadius(Theme.cornerRadius)
                }
                .disabled(isLoading)
            }
        }
        .padding(Theme.padding)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Booking Details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Cancel this booking?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel Booking", role: .destructive) {
                cancelBooking()
            }
        } message: {
            Text("All players will be notified. This cannot be undone.")
        }
    }

    private func cancelBooking() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.cancelBooking(id: booking.booking.id)
                path.removeLast()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
