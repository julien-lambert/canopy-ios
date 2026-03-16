import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: CanopyAuthStore
    @EnvironmentObject private var workspaceStore: CanopyWorkspaceStore

    var body: some View {
        NavigationStack {
            CanopyScreen {
                CanopyCard(title: "Session", systemImage: "person.crop.circle") {
                    VStack(alignment: .leading, spacing: CanopySpacing.sm) {
                        CanopyInfoLine(label: "Email", value: authStore.currentUserEmail)
                        CanopyInfoLine(
                            label: "Statut",
                            value: authStore.isAuthenticated ? "Connecté" : "Déconnecté"
                        )
                    }
                }

                CanopyCard(title: "Site actif", systemImage: "leaf.circle") {
                    VStack(alignment: .leading, spacing: CanopySpacing.sm) {
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
                        .canopySecondaryActionStyle()
                        .disabled(workspaceStore.isLoading)
                    }
                }

                if !workspaceStore.modules.isEmpty {
                    CanopyCard(title: "Modules du site", systemImage: "square.grid.2x2") {
                        VStack(alignment: .leading, spacing: CanopySpacing.sm) {
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
                }

                CanopyCard(title: "Compte", systemImage: "rectangle.portrait.and.arrow.right") {
                    Button(role: .destructive) {
                        Task { await authStore.signOut() }
                    } label: {
                        Text("Se déconnecter")
                            .frame(maxWidth: .infinity)
                    }
                    .canopyPrimaryActionStyle()
                    .disabled(authStore.isLoading || !authStore.isAuthenticated)
                }

                if let error = authStore.errorMessage, !error.isEmpty {
                    CanopyCard(title: "État", systemImage: "exclamationmark.triangle") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let workspaceError = workspaceStore.errorMessage, !workspaceError.isEmpty {
                    CanopyCard(title: "Workspace", systemImage: "exclamationmark.triangle") {
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
