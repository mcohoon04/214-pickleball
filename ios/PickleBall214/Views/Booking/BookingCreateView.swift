import SwiftUI

struct BookingCreateView: View {
    let slot: TimeSlot
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @State private var selectedPlayerIds: Set<UUID> = []
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
        f.dateFormat = "h a"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    private var availableEndTimes: [Date] {
        bookingService.availableEndTimes(date: slot.date, startHour: slot.hour)
    }

    private var endTimeLabel: String {
        guard let end = selectedEndTime else { return "Select" }
        return Self.timeFormatter.string(from: end)
    }

    private var durationHours: Int {
        guard let end = selectedEndTime else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.hour], from: slot.date, to: end).hour ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — date, start time, end time picker
            VStack(spacing: 12) {
                Text(Self.dateFormatter.string(from: slot.date))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 8) {
                    // Start time (fixed)
                    Text(Self.timeFormatter.string(from: slot.date))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.accent)

                    Text("to")
                        .foregroundStyle(Theme.textSecondary)

                    // End time (dropdown)
                    Menu {
                        ForEach(availableEndTimes, id: \.self) { endTime in
                            Button {
                                selectedEndTime = endTime
                            } label: {
                                HStack {
                                    Text(Self.timeFormatter.string(from: endTime))
                                    let hours = Calendar.current.dateComponents([.hour], from: slot.date, to: endTime).hour ?? 0
                                    Text("(\(hours)hr)")
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

                if durationHours > 0 {
                    Text("\(durationHours) hour\(durationHours > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
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
            // Default to 1 hour
            if let firstEnd = availableEndTimes.first {
                selectedEndTime = firstEnd
            }
        }
    }

    private var canBook: Bool {
        selectedPlayerIds.count >= 2 && selectedEndTime != nil
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
