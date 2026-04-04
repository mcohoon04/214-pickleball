import SwiftUI

struct DayCellView: View {
    let date: Date
    let isToday: Bool
    let isPast: Bool
    let hasBooking: Bool

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "America/Toronto")!
        return cal
    }()

    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: isToday ? .bold : .regular))
                .foregroundStyle(isPast ? Theme.disabled : Theme.textPrimary)

            Circle()
                .fill(hasBooking ? Theme.accent : Color.clear)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Theme.accent : Color.clear, lineWidth: 2)
        )
        .opacity(isPast ? 0.5 : 1)
    }
}
