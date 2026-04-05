import SwiftUI

struct BookingDetailView: View {
    let booking: BookingWithPlayers
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @State private var showCancelConfirm = false
    @State private var showLeaveConfirm = false
    @State private var showAddPlayer = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentUserId: UUID? { authService.currentUser?.id }
    private var isCreator: Bool { booking.booking.createdBy == currentUserId }
    private var isPlayer: Bool { booking.players.contains { $0.id == currentUserId } }
    private var canAddPlayer: Bool { isPlayer && booking.players.count < 4 }

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
                HStack {
                    Text("Players")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    Text("\(booking.players.count)/4")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

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

                // Add player button
                if canAddPlayer {
                    Button { showAddPlayer = true } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(Theme.accent, lineWidth: 1.5)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "plus")
                                        .foregroundStyle(Theme.accent)
                                )

                            Text("Add Player")
                                .foregroundStyle(Theme.accent)
                        }
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

            // Action buttons
            VStack(spacing: 12) {
                // Leave booking (non-creator players only)
                if isPlayer && !isCreator {
                    Button {
                        showLeaveConfirm = true
                    } label: {
                        Text("Leave Booking")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.surface)
                            .foregroundStyle(Theme.destructive)
                            .cornerRadius(Theme.cornerRadius)
                    }
                    .disabled(isLoading)
                }

                // Cancel booking (creator only)
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
        }
        .padding(Theme.padding)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Booking Details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Cancel this booking?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel Booking", role: .destructive) { cancelBooking() }
        } message: {
            Text("All players will be notified. This cannot be undone.")
        }
        .confirmationDialog("Leave this booking?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave Booking", role: .destructive) { leaveBooking() }
        } message: {
            Text("You'll be removed from this game.")
        }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerSheet(booking: booking)
                .environment(bookingService)
                .environment(authService)
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

    private func leaveBooking() {
        guard let userId = currentUserId else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.leaveBooking(bookingId: booking.booking.id, playerId: userId)
                path.removeLast()
            } catch {
                if "\(error)".contains("between 2 and 4 players") {
                    errorMessage = "Can't leave — booking needs at least 2 players. Ask the organizer to cancel."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Add Player Sheet

struct AddPlayerSheet: View {
    let booking: BookingWithPlayers
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var availablePlayers: [PlayerInfo] {
        let existingIds = Set(booking.players.map(\.id))
        return bookingService.allPlayers.filter { !existingIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if availablePlayers.isEmpty {
                    Text("No available players to add")
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.surface)
                } else {
                    ForEach(availablePlayers) { player in
                        Button {
                            addPlayer(player.id)
                        } label: {
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

                                Spacer()

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.destructive)
                        .font(.caption)
                        .listRowBackground(Theme.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .task {
                try? await bookingService.fetchAllPlayers()
            }
        }
    }

    private func addPlayer(_ playerId: UUID) {
        guard let addedBy = authService.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.addPlayerToBooking(
                    bookingId: booking.booking.id,
                    playerId: playerId,
                    addedBy: addedBy
                )
                dismiss()
            } catch {
                if "\(error)".contains("between 2 and 4 players") {
                    errorMessage = "Booking is full (max 4 players)."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}
