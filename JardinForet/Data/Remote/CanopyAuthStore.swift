import Foundation
import Supabase

@MainActor
final class CanopyAuthStore: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient?
    private var authObservationTask: Task<Void, Never>?

    init(client: SupabaseClient? = CanopySupabaseClientProvider.shared) {
        self.client = client
        self.session = client?.auth.currentSession
        observeAuthStateChanges()
    }

    deinit {
        authObservationTask?.cancel()
    }

    var isAuthenticated: Bool {
        session != nil
    }

    var currentUserEmail: String {
        session?.user.email ?? "Inconnu"
    }

    var isConfigured: Bool {
        client != nil
    }

    func clearError() {
        errorMessage = nil
    }

    func signIn(email: String, password: String) async -> Bool {
        guard let client else {
            errorMessage = "Supabase non configuré. Vérifie SUPABASE_URL / SUPABASE_ANON_KEY."
            return false
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email et mot de passe requis."
            return false
        }

        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await client.auth.signIn(email: normalizedEmail, password: password)
            errorMessage = nil
            session = client.auth.currentSession
            return true
        } catch {
            errorMessage = "Connexion impossible: \(error.localizedDescription)"
            return false
        }
    }

    func signInWithGoogle() async -> Bool {
        guard let client else {
            errorMessage = "Supabase non configuré. Vérifie SUPABASE_URL / SUPABASE_ANON_KEY."
            return false
        }
        guard let redirectURL = CanopySupabaseConfig.redirectURL else {
            errorMessage = "SUPABASE_REDIRECT_URL manquant (ex: jardinforet://auth/callback)."
            return false
        }

        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: redirectURL
            )
            errorMessage = nil
            session = client.auth.currentSession
            return true
        } catch {
            errorMessage = "Connexion Google impossible: \(error.localizedDescription)"
            return false
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        guard let client else {
            errorMessage = "Supabase non configuré. Vérifie SUPABASE_URL / SUPABASE_ANON_KEY."
            return false
        }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else {
            errorMessage = "Email requis pour réinitialiser le mot de passe."
            return false
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.resetPasswordForEmail(
                normalizedEmail,
                redirectTo: CanopySupabaseConfig.redirectURL
            )
            errorMessage = "Email de réinitialisation envoyé."
            return true
        } catch {
            errorMessage = "Échec réinitialisation: \(error.localizedDescription)"
            return false
        }
    }

    func signOut() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.signOut()
            session = nil
            errorMessage = nil
        } catch {
            errorMessage = "Déconnexion impossible: \(error.localizedDescription)"
        }
    }

    private func observeAuthStateChanges() {
        guard let client else { return }
        authObservationTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                if [.initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated].contains(event) {
                    await MainActor.run {
                        self.session = session
                    }
                }
            }
        }
    }
}
