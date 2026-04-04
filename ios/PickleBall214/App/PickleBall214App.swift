import SwiftUI
import GoogleSignIn

@main
struct PickleBall214App: App {
    @State private var authService = AuthService()
    @State private var bookingService = BookingService()
    @State private var realtimeService = RealtimeService()

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading {
                    ZStack {
                        Theme.background.ignoresSafeArea()
                        ProgressView()
                            .tint(Theme.accent)
                    }
                } else if authService.isAuthenticated {
                    MainView()
                        .environment(authService)
                        .environment(bookingService)
                        .environment(realtimeService)
                        .onAppear {
                            appDelegate.pushService.onTokenReceived = { token in
                                Task {
                                    try? await authService.updateDeviceToken(token)
                                }
                            }
                            appDelegate.pushService.requestPermission()
                        }
                } else {
                    LoginView()
                        .environment(authService)
                }
            }
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let pushService = PushNotificationService()

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushService.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Push registration failed: \(error)")
    }
}
