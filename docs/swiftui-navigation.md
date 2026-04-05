# SwiftUI Navigation & OAuth Deep Link Configuration

## Scope
NavigationStack patterns for the app's 4-view architecture, plus Xcode configuration for Google Sign-In and Supabase OAuth callback URLs.

## Primary Sources
- Apple SwiftUI NavigationStack:
  - https://developer.apple.com/documentation/swiftui/navigationstack
- Apple NavigationPath:
  - https://developer.apple.com/documentation/swiftui/navigationpath
- Apple navigationDestination modifier:
  - https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)
- Google Sign-In iOS start guide:
  - https://developers.google.com/identity/sign-in/ios/start-integrating
- Supabase Swift OAuth:
  - https://supabase.com/docs/reference/swift/auth-signinwithoauth

## 1) NavigationStack Basics (iOS 16+)

`NavigationStack` replaces the deprecated `NavigationView`. It manages a stack of views with push/pop semantics.

### Basic setup
```swift
NavigationStack {
    MonthCalendarView()
        .navigationTitle("214 Pickleball")
        .navigationDestination(for: Date.self) { date in
            DayScheduleView(date: date)
        }
        .navigationDestination(for: Booking.self) { booking in
            BookingDetailView(booking: booking)
        }
}
```

### Value-based NavigationLink (recommended)
```swift
// In MonthCalendarView
NavigationLink(value: selectedDate) {
    DayCell(date: selectedDate)
}
```

The `value` type must conform to `Hashable`. When tapped, SwiftUI finds the matching `navigationDestination(for:)` and pushes that view.

## 2) NavigationPath (Programmatic Navigation)

`NavigationPath` is a type-erased stack that enables programmatic push/pop.

```swift
@State private var path = NavigationPath()

NavigationStack(path: $path) {
    MonthCalendarView(path: $path)
        .navigationDestination(for: Date.self) { date in
            DayScheduleView(date: date, path: $path)
        }
        .navigationDestination(for: BookingSlot.self) { slot in
            BookingCreateView(slot: slot, path: $path)
        }
}
```

### Push a view
```swift
path.append(selectedDate)  // pushes DayScheduleView
```

### Pop one view
```swift
path.removeLast()
```

### Pop to root
```swift
path.removeLast(path.count)
```

## 3) App Navigation Architecture for This Project

### Approach: Auth guard at root, TabView for main content

```swift
@main
struct PickleballApp: App {
    @State private var isAuthenticated = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .onOpenURL { url in
                // Handle Google Sign-In and Supabase OAuth callbacks
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
```

### TabView with NavigationStack per tab (if using tabs)
```swift
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                MonthCalendarView()
                    .navigationDestination(for: Date.self) { date in
                        DayScheduleView(date: date)
                    }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person") }
        }
    }
}
```

### Simpler: Single NavigationStack (recommended for 4 views)
Given the app's linear flow (Calendar → Day → Booking → back), a single `NavigationStack` without tabs may be simpler. Profile/Settings can be a sheet or toolbar button.

```swift
struct MainView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            MonthCalendarView()
                .navigationDestination(for: Date.self) { date in
                    DayScheduleView(date: date)
                }
                .navigationDestination(for: BookingSlot.self) { slot in
                    BookingCreateView(slot: slot)
                }
                .navigationDestination(for: Booking.self) { booking in
                    BookingDetailView(booking: booking)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: ProfileDestination()) {
                            Image(systemName: "person.circle")
                        }
                    }
                }
        }
    }
}
```

## 4) Passing Data Between Views

### Via navigation values (primary pattern)
Define Hashable types for navigation:
```swift
struct BookingSlot: Hashable {
    let date: Date
    let hour: Int
}
```

Push with data:
```swift
NavigationLink(value: BookingSlot(date: date, hour: 10)) {
    Text("10:00 AM - Available")
}
```

### Via @Environment for shared state
```swift
@Observable
class AppState {
    var currentUser: Profile?
    var bookings: [Booking] = []
}

// In App:
ContentView()
    .environment(appState)

// In any child view:
@Environment(AppState.self) var appState
```

## 5) URL Scheme Configuration (Info.plist)

### Google Sign-In callback
Google Sign-In requires a URL scheme using the reversed iOS client ID:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

### Supabase OAuth callback (if using browser-based OAuth)
If using `signInWithOAuth` instead of native Google Sign-In:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.214-pickle</string>
    </array>
  </dict>
</array>
```

### Where to configure in Xcode
Target → Info → URL Types → Add (+):
- Identifier: (optional label)
- URL Schemes: reversed client ID or app scheme
- Role: Editor

## 6) Handling Incoming URLs in SwiftUI

```swift
@main
struct PickleballApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Google Sign-In handles its callback
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    // Handle Supabase OAuth callback (if using browser OAuth)
                    // supabase.auth.handle(url)
                }
        }
    }
}
```

## 7) Associated Domains (Not Required for V1)

Universal links / Associated Domains are only needed if:
- You want `https://` deep links (not custom scheme `com.app://`)
- You're using Sign in with Apple (separate from Google Sign-In)

For V1 with native Google Sign-In + custom URL scheme, Associated Domains configuration is **not required**.

## Recommendation for This App

1. Use single `NavigationStack` with `NavigationPath` (simpler than TabView for 4 views).
2. Profile/Settings accessible via toolbar button (sheet or pushed view).
3. Navigation flow: Month Calendar → Day Schedule → Booking Create/Detail.
4. Auth guard at app root (`if isAuthenticated` check).
5. URL schemes: Google reversed client ID in Info.plist.
6. `onOpenURL` at app root for Google Sign-In callback handling.
