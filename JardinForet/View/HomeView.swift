//
//  HomeView.swift
//  JardinForet
//
//  Created by Julien Lambert on 16/11/2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: GardenStore

    var body: some View {
#if os(macOS)
        macOSBody
#else
        iOSBody
#endif
    }

    @ViewBuilder
    private var iOSBody: some View {
        let stats = store.fetchStats()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // En-tête compact
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentPrimary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.accentPrimary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jardin-forêt de Devey")
                            .font(.title2).bold()
                        Text("Centre de contrôle du jardin vivant")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(.top, 8)

                syncPanel

                // Actions principales
                Text("Actions rapides")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()),
                                    GridItem(.flexible())],
                          spacing: 12) {
                    NavigationLink(destination: PlantsListView()) {
                        ActionCard(
                            title: "Individus",
                            subtitle: "Voir tous les plants",
                            systemImage: "tree"
                        )
                    }
                    NavigationLink(destination: SpeciesListView()) {
                        ActionCard(
                            title: "Espèces",
                            subtitle: "Taxonomie du jardin",
                            systemImage: "leaf.circle"
                        )
                    }
                    NavigationLink(destination: HivesListView()) {
                        ActionCard(
                            title: "Ruches",
                            subtitle: "Matériel & récoltes",
                            systemImage: "hexagon.fill"
                        )
                    }
                    NavigationLink(destination: ColoniesListView()) {
                        ActionCard(
                            title: "Colonies",
                            subtitle: "Santé des abeilles",
                            systemImage: "ant.fill"
                        )
                    }
                }

                // Statistiques synthétiques
                Text("Le jardin en un coup d’œil")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatChip(title: "Individus", value: "\(stats.plantCount)", systemImage: "number")
                        StatChip(title: "Espèces", value: "\(stats.speciesCount)", systemImage: "leaf")
                        StatChip(title: "Ruches", value: "\(stats.hiveCount)", systemImage: "shippingbox")
                        StatChip(title: "Colonies", value: "\(stats.colonyCount)", systemImage: "ant")
                    }
                    .padding(.vertical, 2)
                }

                // Cartes d’information
                VStack(alignment: .leading, spacing: 12) {
                    InfoCard(
                        title: "À propos du jardin",
                        systemImage: "globe.europe.africa",
                        text: "Le Jardin-forêt de Devey est un lieu expérimental et vivant : chaque arbre, chaque arbuste et chaque plante fait partie d’une histoire en cours d’écriture. Cette application t’aide à garder une mémoire de ce que tu plantes, de ce qui pousse bien et de ce qui disparaît."
                    )
                    InfoCard(
                        title: "Étiquettes NFC & QR",
                        systemImage: "dot.radiowaves.up.forward",
                        text: "Certains arbres et arbustes portent une étiquette interactive. En scannant un tag NFC ou un QR code, tu ouvres directement la fiche de l’individu : emplacement, variété, notes de culture, photos… idéal pour les balades sur place."
                    )
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private var macOSBody: some View {
        let stats = store.fetchStats()

        GeometryReader { proxy in
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    // Bandeau supérieur léger
                    HStack(alignment: .center, spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentPrimary.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.accentPrimary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Jardin-forêt de Devey")
                                .font(.largeTitle.bold())
                                .foregroundColor(.textPrimary)
                            Text("Tableau de bord général du jardin vivant")
                                .font(.headline)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()
                    }

                    Divider()
                        .padding(.top, 4)

                    syncPanel

                    // Corps en deux colonnes aérées
                    HStack(alignment: .top, spacing: 32) {
                        // Colonne gauche : navigation
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Navigation")
                                .font(.title3.bold())
                                .foregroundColor(.textPrimary)

                            VStack(alignment: .leading, spacing: 10) {
                                NavigationLink(destination: PlantsListView()) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: "tree")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.accentPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Individus")
                                                .font(.headline)
                                            Text("Liste, filtrage, fiches détaillées")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary.opacity(0.7))
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: SpeciesListView()) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: "leaf.circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.accentPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Espèces")
                                                .font(.headline)
                                            Text("Taxonomie, familles, strates")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary.opacity(0.7))
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: GardenMapView()) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: "map")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.accentPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Carte & parcelles")
                                                .font(.headline)
                                            Text("Localisation des individus")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary.opacity(0.7))
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: HivesListView()) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: "hexagon.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.accentPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Ruches")
                                                .font(.headline)
                                            Text("Matériel, récoltes, emplacement")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary.opacity(0.7))
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: ColoniesListView()) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: "ant.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.accentPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Colonies")
                                                .font(.headline)
                                            Text("Suivi sanitaire et dynamique")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary.opacity(0.7))
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: 340, alignment: .topLeading)

                        // Colonne droite : vue d’ensemble et infos
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Vue d’ensemble")
                                .font(.title3.bold())
                                .foregroundColor(.textPrimary)

                            // Stats en ligne, sans gros rectangles
                            HStack(spacing: 12) {
                                StatChip(title: "Individus", value: "\(stats.plantCount)", systemImage: "number")
                                StatChip(title: "Espèces", value: "\(stats.speciesCount)", systemImage: "leaf")
                                StatChip(title: "Ruches", value: "\(stats.hiveCount)", systemImage: "shippingbox")
                                StatChip(title: "Colonies", value: "\(stats.colonyCount)", systemImage: "ant")
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                InfoCard(
                                    title: "À propos du jardin",
                                    systemImage: "globe.europe.africa",
                                    text: "Le Jardin-forêt de Devey est un lieu expérimental et vivant : chaque arbre, chaque arbuste et chaque plante fait partie d’une histoire en cours d’écriture. Cette application t’aide à garder une mémoire de ce que tu plantes, de ce qui pousse bien et de ce qui disparaît."
                                )
                                .frame(maxWidth: .infinity,
                                       minHeight: 80,
                                       alignment: .leading)

                                InfoCard(
                                    title: "Étiquettes NFC & QR",
                                    systemImage: "dot.radiowaves.up.forward",
                                    text: "Certains arbres et arbustes portent une étiquette interactive. En scannant un tag NFC ou un QR code, tu ouvres directement la fiche de l’individu : emplacement, variété, notes de culture, photos… idéal pour les balades sur place."
                                )
                                .frame(maxWidth: .infinity,
                                       minHeight: 80,
                                       alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    // Vue du jardin sur toute la largeur, hauteur adaptative
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vue du jardin")
                            .font(.title3.bold())
                            .foregroundColor(.textPrimary)

                        let mapHeight = max(proxy.size.height * 0.45, CGFloat(260))

                        GardenMapView()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.cardBackground.opacity(0.6), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: mapHeight)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 1200, alignment: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
    }

    private var syncPanel: some View {
        let status = syncStatusPresentation(for: store.lastSyncMessage)

        return HStack(alignment: .center, spacing: 10) {
            Button {
                store.forceSyncNow()
            } label: {
                Label(
                    store.isSyncing ? "Synchro..." : "Forcer la synchro",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSyncing)

            VStack(alignment: .leading, spacing: 2) {
                if let status {
                    Text(status.text)
                        .font(.caption)
                        .foregroundColor(status.color)
                }
                if let lastSyncDate = store.lastSyncDate {
                    Text("Dernière synchro: \(syncDateFormatter.string(from: lastSyncDate))")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()
        }
    }

    private func syncStatusPresentation(for rawMessage: String?) -> (text: String, color: Color)? {
        guard let raw = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if raw.contains("UNIQUE constraint failed: cultivars.species_id, cultivars.name") {
            return (
                "Conflit de synchro: un cultivar a déjà ce nom pour la même espèce. Renomme le doublon puis relance la synchro.",
                .orange
            )
        }

        if raw.lowercased().contains("erreur") {
            let short = raw.split(separator: "\n").first.map(String.init) ?? raw
            return (short, .orange)
        }

        if raw.lowercased().contains("partielle") {
            return (raw, .orange)
        }

        if raw.lowercased().contains("termin") {
            return (raw, .green)
        }

        return (raw, .textSecondary)
    }

    private var syncDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentPrimary)

            Text(title)
                .font(.headline)
                .foregroundColor(.textPrimary)

            Text(subtitle)
                .font(.footnote)
                .foregroundColor(.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 16)
    }
}

struct StatChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.accentPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.subheadline).bold()
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
    }
}

struct InfoCard: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentPrimary.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline).bold()
                Text(text)
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String = "leaf"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundColor(.accentPrimary)

                Text(title)
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }

            Text(value)
                .font(.title2).bold()
                .foregroundColor(.textPrimary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 16)
    }
}
