import Foundation
import Supabase

enum SupabaseConfig {
    static let url = URL(string: "https://ttdeyiriqminwguozbal.supabase.co")!
    static let anonKey = "sb_publishable_f3Ll4CZYTHlxTcHJtmMduw_luSsdQs2"

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: anonKey,
        options: SupabaseClientOptions(
            db: .init(schema: "public"),
            auth: .init(flowType: .pkce)
        )
    )
}
