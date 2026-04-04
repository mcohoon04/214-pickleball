import Foundation
import Supabase

@Observable
final class RealtimeService {
    private let supabase = SupabaseConfig.client
    private var channel: RealtimeChannelV2?

    func subscribeToBookingChanges(onChange: @escaping () -> Void) async {
        let channel = supabase.channel("booking-changes")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "bookings")
        await channel.subscribe()
        self.channel = channel

        Task {
            for await _ in changes {
                await MainActor.run { onChange() }
            }
        }
    }

    func unsubscribe() async {
        if let channel {
            await supabase.removeChannel(channel)
            self.channel = nil
        }
    }
}
