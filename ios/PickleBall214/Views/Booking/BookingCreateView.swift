import SwiftUI

private struct GuestEntry: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
}

struct BookingCreateView: View {
    let slot: TimeSlot
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @State private var selectedPlayerIds: Set<UUID> = []
    @State private var guests: [GuestEntry] = []
    @State private var selectedEndTime: Date?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    private var availableEndTimes: [Date] {
        bookingService.availableEndTimes(start: slot.date)
    }

    private var endTimeLabel: String {
        guard let end = selectedEndTime else { return "Select" }
        return Self.timeFormatter.string(from: end)
    }

    private var totalCount: Int {
        selectedPlayerIds.count + guests.count
    }

    private func durationLabel(to end: Date) -> String {
        let mins = max(0, Int(end.timeIntervalSince(slot.date) / 60))
        let h = mins / 60
        let m = mins % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) hr" }
        return "\(h) hr \(m) min"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — date, start time, end time picker
            VStack(spacing: 12) {
                Text(Self.dateFormatter.string(from: slot.date))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 8) {
                    Text(Self.timeFormatter.string(from: slot.date))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.accent)

                    Text("to")
                        .foregroundStyle(Theme.textSecondary)

                    Menu {
                        ForEach(availableEndTimes, id: \.self) { endTime in
                            Button {
                                selectedEndTime = endTime
                            } label: {
                                HStack {
                                    Text(Self.timeFormatter.string(from: endTime))
                                    Text("(\(durationLabel(to: endTime)))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(endTimeLabel)
                                .font(.title2.bold())
                                .foregroundStyle(Theme.accent)
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceLight)
                        .cornerRadius(8)
                    }
                }

                if let end = selectedEndTime {
                    Text(durationLabel(to: end))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Players")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(totalCount)/4")
                            .font(.subheadline)
                            .foregroundStyle(totalCount >= 2 ? Theme.accent : Theme.textSecondary)
                    }
                    .padding(.horizontal, Theme.padding)

                    // Registered players
                    ForEach(bookingService.allPlayers) { player in
                        let isCurrentUser = player.id == authService.currentUser?.id
                        let isSelected = selectedPlayerIds.contains(player.id)

                        Button {
                            if !isCurrentUser {
                                if isSelected {
                                    selectedPlayerIds.remove(player.id)
                                } else if totalCount < 4 {
                                    selectedPlayerIds.insert(player.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
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

                    // Guests
                    if !guests.isEmpty {
                        Text("Guests")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.padding)
                            .padding(.top, 4)
                    }

                    ForEach($guests) { $guest in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.surfaceLight)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                        .foregroundStyle(Theme.textSecondary)
                                )

                            TextField("Guest name (optional)", text: $guest.name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(Theme.textPrimary)

                            Button {
                                guests.removeAll { $0.id == guest.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Theme.destructive)
                                    .font(.title3)
                            }
                        }
                        .padding(.horizontal, Theme.padding)
                        .padding(.vertical, 8)
                    }

                    // Add guest
                    Button {
                        if totalCount < 4 {
                            guests.append(GuestEntry())
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(Theme.accent, lineWidth: 1.5)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "plus")
                                        .foregroundStyle(Theme.accent)
                                )
                            Text("Add Guest")
                                .foregroundStyle(Theme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.padding)
                        .padding(.vertical, 8)
                    }
                    .disabled(totalCount >= 4)
                    .opacity(totalCount >= 4 ? 0.4 : 1)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
                    .padding(.horizontal, Theme.padding)
            }

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
                .background(canBook ? Theme.accent : Theme.disabled)
                .foregroundStyle(Theme.textOnAccent)
                .cornerRadius(Theme.cornerRadius)
            }
            .disabled(!canBook || isLoading)
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
            if selectedEndTime == nil, let firstEnd = availableEndTimes.first {
                selectedEndTime = firstEnd
            }
        }
    }

    private var canBook: Bool {
        totalCount >= 2 && totalCount <= 4 && selectedEndTime != nil
    }

    private func createBooking() {
        guard let endTime = selectedEndTime else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                _ = try await bookingService.createBooking(
                    startsAt: slot.date,
                    endsAt: endTime,
                    playerIds: Array(selectedPlayerIds),
                    guestNames: guests.map(\.name)
                )
                path.removeLast(path.count)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
