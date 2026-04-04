import SwiftUI

struct MainView: View {
    @State private var path = NavigationPath()
    @State private var showingProfile = false
    @Environment(AuthService.self) var authService
    @Environment(BookingService.self) var bookingService
    @Environment(RealtimeService.self) var realtimeService
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            MonthCalendarView(path: $path)
                .navigationDestination(for: Date.self) { date in
                    DayScheduleView(date: date, path: $path)
                }
                .navigationDestination(for: TimeSlot.self) { slot in
                    BookingCreateView(slot: slot, path: $path)
                }
                .navigationDestination(for: BookingWithPlayers.self) { bwp in
                    BookingDetailView(booking: bwp, path: $path)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingProfile = true } label: {
                            Image(systemName: "person.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .sheet(isPresented: $showingProfile) {
                    NavigationStack {
                        ProfileView()
                    }
                    .environment(authService)
                }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    let now = Date()
                    let cal = Calendar.current
                    try? await bookingService.fetchBookingsForMonth(
                        year: cal.component(.year, from: now),
                        month: cal.component(.month, from: now)
                    )
                }
            }
        }
    }
}
