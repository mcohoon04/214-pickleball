import SwiftUI

struct BookingDetailView: View {
    let booking: BookingWithPlayers
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService

    @State private var players: [BookingParticipant] = []
    @State private var showCancelConfirm = false
    @State private var showLeaveConfirm = false
    @State private var showAddPlayer = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentUserId: UUID? { authService.currentUser?.id }
    private var isCreator: Bool { booking.booking.createdBy == currentUserId }
    private var isPlayer: Bool { players.contains { $0.userId == currentUserId } }
    private var isPast: Bool { booking.booking.startsAt < Date() }
    private var isFull: Bool { players.count >= 4 }
    private var canEdit: Bool { isPlayer && !isPast }

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
                    Text("\(players.count)/4")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(players) { participant in
                    participantRow(participant)
                }

                // Member: add another registered player or a guest.
                if canEdit && !isFull {
                    Button { showAddPlayer = true } label: {
                        addRow(icon: "plus", text: "Add Player or Guest")
                    }
                    .disabled(isLoading)
                }

                // Non-member: join this booking.
                if !isPlayer && !isPast && !isFull {
                    Button { join() } label: {
                        addRow(icon: "person.badge.plus", text: "Join this Booking")
                    }
                    .disabled(isLoading)
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
            Button("Leave Booking", role: .destructive) { leave() }
        } message: {
            Text("You'll be removed from this game.")
        }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerSheet(bookingId: booking.booking.id, currentPlayers: players)
                .environment(bookingService)
                .environment(authService)
        }
        .onChange(of: showAddPlayer) { _, shown in
            if !shown { Task { await refresh() } }
        }
        .task {
            players = booking.players
            await refresh()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func participantRow(_ participant: BookingParticipant) -> some View {
        let isOrganizer = participant.userId == booking.booking.createdBy
        let isSelf = participant.userId != nil && participant.userId == currentUserId
        HStack(spacing: 12) {
            Circle()
                .fill(participant.isGuest ? Theme.surfaceLight : Theme.accent.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Group {
                        if participant.isGuest {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Text(String(participant.displayName.prefix(1)).uppercased())
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                )

            Text(participant.displayName)
                .foregroundStyle(Theme.textPrimary)

            if isOrganizer {
                badge("Organizer")
            } else if participant.isGuest {
                badge("Guest")
            }

            Spacer()

            // Members can remove any non-organizer participant (other players & guests).
            // Your own row is removed via "Leave Booking" instead.
            if canEdit && !isOrganizer && !isSelf {
                Button { remove(participant) } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Theme.destructive)
                }
                .disabled(isLoading)
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.surfaceLight)
            .cornerRadius(4)
    }

    private func addRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 1.5)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: icon).foregroundStyle(Theme.accent))
            Text(text).foregroundStyle(Theme.accent)
            Spacer()
        }
    }

    // MARK: - Actions

    private func refresh() async {
        if bookingService.allPlayers.isEmpty {
            try? await bookingService.fetchAllPlayers()
        }
        if let updated = try? await bookingService.fetchParticipants(bookingId: booking.booking.id) {
            await MainActor.run { players = updated }
        }
    }

    private func friendly(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("between 2 and 4 players") {
            return "A booking needs at least 2 players."
        }
        if text.contains("creator must be included") {
            return "The organizer can't be removed."
        }
        return error.localizedDescription
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

    private func leave() {
        guard let userId = currentUserId,
              let row = players.first(where: { $0.userId == userId }) else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.removeParticipant(rowId: row.rowId)
                path.removeLast()
            } catch {
                errorMessage = friendly(error)
            }
            isLoading = false
        }
    }

    private func remove(_ participant: BookingParticipant) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.removeParticipant(rowId: participant.rowId)
                await refresh()
            } catch {
                errorMessage = friendly(error)
            }
            isLoading = false
        }
    }

    private func join() {
        guard let userId = currentUserId else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.addPlayerToBooking(
                    bookingId: booking.booking.id,
                    playerId: userId,
                    addedBy: userId
                )
                await refresh()
            } catch {
                errorMessage = friendly(error)
            }
            isLoading = false
        }
    }
}

// MARK: - Add Player Sheet

struct AddPlayerSheet: View {
    let bookingId: UUID
    let currentPlayers: [BookingParticipant]
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss
    @State private var guestName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var existingUserIds: Set<UUID> {
        Set(currentPlayers.compactMap(\.userId))
    }

    private var availablePlayers: [PlayerInfo] {
        bookingService.allPlayers.filter { !existingUserIds.contains($0.id) }
    }

    private var isFull: Bool { currentPlayers.count >= 4 }

    var body: some View {
        NavigationStack {
            List {
                Section("Add a guest") {
                    HStack {
                        TextField("Guest name (optional)", text: $guestName)
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(Theme.textPrimary)
                        Button("Add") { addGuest() }
                            .foregroundStyle(Theme.accent)
                            .disabled(isLoading || isFull)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section("Registered players") {
                    if availablePlayers.isEmpty {
                        Text("No other players to add")
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
                            .disabled(isLoading || isFull)
                            .listRowBackground(Theme.surface)
                        }
                    }
                }

                if isFull {
                    Text("Booking is full (max 4).")
                        .foregroundStyle(Theme.textSecondary)
                        .font(.caption)
                        .listRowBackground(Theme.background)
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

    private func friendly(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("between 2 and 4 players") {
            return "Booking is full (max 4 players)."
        }
        return error.localizedDescription
    }

    private func addPlayer(_ playerId: UUID) {
        guard let addedBy = authService.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.addPlayerToBooking(
                    bookingId: bookingId,
                    playerId: playerId,
                    addedBy: addedBy
                )
                dismiss()
            } catch {
                errorMessage = friendly(error)
            }
            isLoading = false
        }
    }

    private func addGuest() {
        guard let addedBy = authService.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await bookingService.addGuestToBooking(
                    bookingId: bookingId,
                    guestName: guestName,
                    addedBy: addedBy
                )
                dismiss()
            } catch {
                errorMessage = friendly(error)
            }
            isLoading = false
        }
    }
}
