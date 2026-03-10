import Foundation
import Supabase

enum CanopySupabaseClientProvider {
    static let shared: SupabaseClient? = {
        guard let url = CanopySupabaseConfig.url, let key = CanopySupabaseConfig.anonKey else {
            return nil
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}

enum CanopySupabaseAuthError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Session Supabase absente. Connecte-toi dans l'écran de connexion."
        }
    }
}

actor CanopySupabaseAuthBootstrap {
    static let shared = CanopySupabaseAuthBootstrap()

    func ensureAuthenticated(client: SupabaseClient) async throws {
        if client.auth.currentUser != nil {
            return
        }
        throw CanopySupabaseAuthError.notAuthenticated
    }
}
