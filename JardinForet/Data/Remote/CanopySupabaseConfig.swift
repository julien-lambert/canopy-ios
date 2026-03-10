import Foundation

enum CanopySupabaseConfig {
    static func stringValue(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty, !env.hasPrefix("$(") {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String, !plist.isEmpty, !plist.hasPrefix("$(") {
            return plist
        }
        return nil
    }

    static var url: URL? {
        guard let rawURL = stringValue(for: "SUPABASE_URL") else { return nil }
        return URL(string: rawURL)
    }

    static var anonKey: String? {
        stringValue(for: "SUPABASE_ANON_KEY")
    }

    static var expectedProjectRef: String? {
        stringValue(for: "SUPABASE_PROJECT_REF")
    }

    static var redirectURL: URL? {
        guard let rawURL = stringValue(for: "SUPABASE_REDIRECT_URL") else { return nil }
        return URL(string: rawURL)
    }
}
