import SwiftUI

struct BookingCreateView: View {
    let slot: TimeSlot
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @State private var selectedPlayerIds: Set<UUID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d 'at' h a"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(Self.formatter.string(from: slot.date))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("1 hour session")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 20)

            // Player selection
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Select Players")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(selectedPlayerIds.count)/4")
                            .font(.subheadline)
                            .foregroundStyle(selectedPlayerIds.count >= 2 ? Theme.accent : Theme.textSecondary)
                    }
                    .padding(.horizontal, Theme.padding)

                    ForEach(bookingService.allPlayers) { player in
                        let isCurrentUser = player.id == authService.currentUser?.id
                        let isSelected = selectedPlayerIds.contains(player.id)

                        Button {
                            if !isCurrentUser {
                                if isSelected {
                                    selectedPlayerIds.remove(player.id)
                                } else if selectedPlayerIds.count < 4 {
                                    selectedPlayerIds.insert(player.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                // Avatar placeholder
                                Circle()
                                    .fill(Theme.accent.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String(player.displayName.prefix(1)).uppercased())
                                            .font(.headline)
                                            .foregroundStyle(Theme.accent)
                                    )

                                VStack(alignment: .leading) {
                                    Text(player.displayName)
                                        .foregroundStyle(Theme.textPrimary)
                                    if isCurrentUser {
                                        Text("You")
                                            .font(.caption)
                                            .foregroundStyle(Theme.accent)
                                    }
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Theme.accent : Theme.disabled)
                                    .font(.title3)
                            }
                            .padding(.horizontal, Theme.padding)
                            .padding(.vertical, 8)
                        }
                        .disabled(isCurrentUser)
                    }
                }
            }

            // Error
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .padding(.horizontal, Theme.padding)
            }

            // Book button
            Button {
                createBooking()
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(Theme.textOnAccent)
                    } else {
                        Text("Book Court")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedPlayerIds.count >= 2 ? Theme.accent : Theme.disabled)
                .foregroundStyle(Theme.textOnAccent)
                .cornerRadius(Theme.cornerRadius)
            }
            .disabled(selectedPlayerIds.count < 2 || isLoading)
            .padding(Theme.padding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Book Court")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await bookingService.fetchAllPlayers()
            if let userId = authService.currentUser?.id {
                selectedPlayerIds.insert(userId)
            }
        }
    }

    private func createBooking() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                _ = try await bookingService.createBooking(
                    startsAt: slot.date,
                    playerIds: Array(selectedPlayerIds)
                )
                path.removeLast(path.count)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
