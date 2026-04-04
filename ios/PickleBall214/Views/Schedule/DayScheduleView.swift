import SwiftUI

struct DayScheduleView: View {
    let date: Date
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(AuthService.self) var authService
    @Environment(RealtimeService.self) var realtimeService
    @State private var isLoading = true

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        f.timeZone = TimeZone(identifier: "America/Toronto")
        return f
    }()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(Theme.accent).padding(.top, 40)
                } else {
                    ForEach(bookingService.timeSlotsForDay(date: date)) { slot in
                        TimeSlotRow(
                            slot: slot,
                            currentUserId: authService.currentUser?.id,
                            onTapAvailable: {
                                path.append(slot)
                            },
                            onTapBooked: {
                                if let bwp = slot.booking {
                                    path.append(bwp)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.padding)
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Self.dateFormatter.string(from: date))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await bookingService.fetchAllPlayers()
            try? await bookingService.fetchBookingsForDay(date: date)
            isLoading = false
        }
        .task {
            await realtimeService.subscribeToBookingChanges {
                Task {
                    try? await bookingService.fetchBookingsForDay(date: date)
                }
            }
        }
    }
}
