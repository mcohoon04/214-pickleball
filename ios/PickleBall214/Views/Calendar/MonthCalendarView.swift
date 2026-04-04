import SwiftUI

struct MonthCalendarView: View {
    @Binding var path: NavigationPath
    @Environment(BookingService.self) var bookingService
    @Environment(RealtimeService.self) var realtimeService
    @State private var currentMonth = Date()
    @State private var isLoading = true

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "America/Toronto")!
        return cal
    }()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 0) {
            // Month header with navigation
            HStack {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Theme.accent)
                        .font(.title3)
                }

                Spacer()

                Text(monthYearString)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.accent)
                        .font(.title3)
                }
            }
            .padding(.horizontal, Theme.padding)
            .padding(.vertical, 12)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.padding)

            // Calendar grid
            if isLoading {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(monthDays(), id: \.id) { day in
                        if let date = day.date {
                            DayCellView(
                                date: date,
                                isToday: calendar.isDateInToday(date),
                                isPast: date < calendar.startOfDay(for: Date()),
                                hasBooking: hasBooking(on: date)
                            )
                            .onTapGesture {
                                if date >= calendar.startOfDay(for: Date()) {
                                    path.append(date)
                                }
                            }
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                .padding(.horizontal, Theme.padding)

                Spacer()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("214 Pickle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadMonth() }
        .task {
            await realtimeService.subscribeToBookingChanges {
                Task { await loadMonth() }
            }
        }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone(identifier: "America/Toronto")
        return formatter.string(from: currentMonth)
    }

    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
            Task { await loadMonth() }
        }
    }

    private func loadMonth() async {
        isLoading = true
        let year = calendar.component(.year, from: currentMonth)
        let month = calendar.component(.month, from: currentMonth)
        try? await bookingService.fetchBookingsForMonth(year: year, month: month)
        isLoading = false
    }

    private func hasBooking(on date: Date) -> Bool {
        bookingService.bookingsForMonth.contains { booking in
            calendar.isDate(booking.startsAt, inSameDayAs: date)
        }
    }

    private func monthDays() -> [MonthDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let daysRange = calendar.range(of: .day, in: .month, for: currentMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [MonthDay] = (0..<leading).map { MonthDay(id: "empty-\($0)", date: nil) }

        for day in daysRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                cells.append(MonthDay(id: "day-\(day)", date: date))
            }
        }

        while cells.count % 7 != 0 {
            cells.append(MonthDay(id: "trail-\(cells.count)", date: nil))
        }

        return cells
    }
}

private struct MonthDay: Identifiable {
    let id: String
    let date: Date?
}
