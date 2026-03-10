import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: CanopyAuthStore
    @EnvironmentObject private var workspaceStore: CanopyWorkspaceStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    LabeledContent("Email", value: authStore.currentUserEmail)
                    LabeledContent("Statut", value: authStore.isAuthenticated ? "Connecté" : "Déconnecté")
                }

                Section("Site actif") {
                    if workspaceStore.sites.isEmpty {
                        Text("Aucun site membre disponible.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Site", selection: selectedSiteBinding) {
                            ForEach(workspaceStore.sites) { site in
                                Text("\(site.name) (\(site.role))")
                                    .tag(site.id)
                            }
                        }
                        .disabled(workspaceStore.isLoading)
                    }

                    Button("Rafraîchir le workspace") {
                        Task { await workspaceStore.refresh() }
                    }
                    .disabled(workspaceStore.isLoading)
                }

                if !workspaceStore.modules.isEmpty {
                    Section("Modules du site") {
                        ForEach(workspaceStore.modules) { module in
                            Toggle(isOn: moduleEnabledBinding(for: module.code)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(module.label)
                                    Text(module.code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!workspaceStore.canManageModules || workspaceStore.isLoading)
                        }

                        if !workspaceStore.canManageModules {
                            Text("Seuls owner/admin peuvent modifier les modules.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await authStore.signOut() }
                    } label: {
                        Text("Se déconnecter")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(authStore.isLoading || !authStore.isAuthenticated)
                }

                if let error = authStore.errorMessage, !error.isEmpty {
                    Section("État") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let workspaceError = workspaceStore.errorMessage, !workspaceError.isEmpty {
                    Section("Workspace") {
                        Text(workspaceError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Compte")
        }
    }

    private var selectedSiteBinding: Binding<String> {
        Binding(
            get: { workspaceStore.selectedSiteID ?? "" },
            set: { newValue in
                Task { await workspaceStore.selectSite(newValue) }
            }
        )
    }

    private func moduleEnabledBinding(for code: String) -> Binding<Bool> {
        Binding(
            get: { workspaceStore.isModuleEnabled(code) },
            set: { isEnabled in
                workspaceStore.setModuleEnabled(code: code, enabled: isEnabled)
            }
        )
    }
}
