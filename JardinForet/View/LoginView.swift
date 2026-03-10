import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authStore: CanopyAuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var rememberEmail = true

    @AppStorage("auth_last_email") private var storedEmail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Connexion") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)

                    SecureField("Mot de passe", text: $password)

                    Toggle("Mémoriser l'email", isOn: $rememberEmail)
                }

                Section {
                    Button {
                        Task { await signInWithPassword() }
                    } label: {
                        if authStore.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Se connecter")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(authStore.isLoading)

                    Button {
                        Task { _ = await authStore.signInWithGoogle() }
                    } label: {
                        Text("Continuer avec Google")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(authStore.isLoading)

                    Button("Mot de passe oublié ?") {
                        Task { _ = await authStore.sendPasswordReset(email: email) }
                    }
                    .disabled(authStore.isLoading)
                }

                if let error = authStore.errorMessage, !error.isEmpty {
                    Section("État") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(error.lowercased().contains("envoyé") ? .green : .red)
                    }
                }

                if !authStore.isConfigured {
                    Section("Configuration") {
                        Text("SUPABASE_URL / SUPABASE_ANON_KEY manquants dans les Build Settings.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Jardin Web - Connexion")
            .onAppear {
                if email.isEmpty {
                    email = storedEmail
                }
            }
        }
    }

    private func signInWithPassword() async {
        let success = await authStore.signIn(email: email, password: password)
        if success {
            if rememberEmail {
                storedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                storedEmail = ""
            }
            password = ""
        }
    }
}
