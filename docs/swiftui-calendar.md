# SwiftUI Month Calendar Research

## Scope
Research for implementing a **custom month-view calendar grid** in SwiftUI for iOS, with alternatives using `HorizonCalendar` and `FSCalendar`.

## Primary Sources
- Apple SwiftUI/API docs (reference pages):
  - https://developer.apple.com/documentation/swiftui/lazyvgrid
  - https://developer.apple.com/documentation/foundation/calendar
  - https://developer.apple.com/documentation/swiftui/datepicker
- HorizonCalendar README (Airbnb): https://github.com/airbnb/HorizonCalendar
- FSCalendar README: https://github.com/WenchaoD/FSCalendar

## Documentation Excerpts (Verified)

### HorizonCalendar (SwiftUI + UIKit)
From README:
- "`CalendarViewRepresentable` is the SwiftUI view type that represents the calendar."
- "At a minimum, you need to provide a `Calendar`, a visible date range, and a months layout (either vertical or horizontal)."
- "`CalendarView` is the `UIView` subclass that renders the calendar."

SwiftUI setup excerpt from README:
```swift
let calendar = Calendar.current

let startDate = calendar.date(from: DateComponents(year: 2020, month: 01, day: 01))!
let endDate = calendar.date(from: DateComponents(year: 2021, month: 12, day: 31))!

CalendarViewRepresentable(
  calendar: calendar,
  visibleDateRange: startDate...endDate,
  monthsLayout: .vertical(options: VerticalMonthsLayoutOptions()),
  dataDependency: nil)
```

Selection excerpt from README:
```swift
@State var selectedDate: Date?

CalendarViewRepresentable(...)
  .onDaySelection { day in
    selectedDate = calendar.date(from: day.components)
  }
```

### FSCalendar (UIKit-first)
From README:
- `FSCalendar` uses `FSCalendarDataSource` and `FSCalendarDelegate`.
- `FSCalendar` "doesn't update frame by itself" and recommends implementing `calendar(_:boundingRectWillChange:animated:)`.

Swift setup excerpt from README:
```swift
let calendar = FSCalendar(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
calendar.dataSource = self
calendar.delegate = self
view.addSubview(calendar)
self.calendar = calendar
```

## Native SwiftUI Pattern (No 3rd-Party)

### Month Grid Data Model Pattern
Use `Calendar` to compute:
- month start (`dateInterval(of: .month, for:)`)
- day count (`range(of: .day, in: .month, for:)`)
- first weekday offset (leading placeholders)

```swift
import SwiftUI

struct MonthDay: Identifiable {
  let id = UUID()
  let date: Date?
}

func monthGridDates(for month: Date, calendar: Calendar) -> [MonthDay] {
  guard
    let monthInterval = calendar.dateInterval(of: .month, for: month),
    let daysRange = calendar.range(of: .day, in: .month, for: month)
  else { return [] }

  let monthStart = monthInterval.start
  let firstWeekday = calendar.component(.weekday, from: monthStart)
  let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

  var cells: [MonthDay] = Array(repeating: MonthDay(date: nil), count: leading)

  for day in daysRange {
    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
      cells.append(MonthDay(date: date))
    }
  }

  while cells.count % 7 != 0 {
    cells.append(MonthDay(date: nil))
  }

  return cells
}
```

### Month Navigation Pattern
```swift
@State private var currentMonth = Date()
let calendar = Calendar.current

func nextMonth() {
  currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
}

func previousMonth() {
  currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
}
```

### Month Grid View Pattern (`LazyVGrid`)
```swift
let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

LazyVGrid(columns: columns, spacing: 8) {
  ForEach(monthGridDates(for: currentMonth, calendar: calendar)) { cell in
    if let date = cell.date {
      Button {
        // open day schedule
      } label: {
        Text("\(calendar.component(.day, from: date))")
          .frame(maxWidth: .infinity, minHeight: 36)
          .background(calendar.isDateInToday(date) ? Color.blue.opacity(0.15) : .clear)
          .cornerRadius(8)
      }
      .disabled(date < calendar.startOfDay(for: Date()))
    } else {
      Color.clear.frame(height: 36)
    }
  }
}
```

### Booking Indicator Pattern
Use a `Set<Date>` normalized to `startOfDay`:
```swift
let bookedDays: Set<Date> = ... // normalized in local calendar
let day = calendar.startOfDay(for: date)
let hasBooking = bookedDays.contains(day)
```

## Option Comparison

### Native SwiftUI (Recommended V1)
Pros:
- No UIKit bridge
- Small user base/simple requirements fit this
- Full control over disabled past-days + custom dots/labels

Cons:
- You own month math, accessibility polish, and edge cases

### HorizonCalendar
Pros:
- Strong SwiftUI support, fast at large date ranges
- Built-in advanced customization (`dayRanges`, selection handlers, month layouts)

Cons:
- Extra dependency and API learning curve

### FSCalendar
Pros:
- Mature/popular calendar component

Cons:
- UIKit-first; SwiftUI requires `UIViewRepresentable`
- More friction for pure SwiftUI architecture

## Practical Recommendation for This App
- Build V1 with **native SwiftUI grid** (`LazyVGrid` + `Calendar` APIs).
- If custom rendering/selection logic grows complex, migrate month screen to `HorizonCalendar` before considering `FSCalendar`.
