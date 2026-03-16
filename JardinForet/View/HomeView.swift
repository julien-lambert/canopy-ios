//
//  HomeView.swift
//  JardinForet
//
//  Created by Julien Lambert on 16/11/2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: CanopyStore
    @EnvironmentObject var workspaceStore: CanopyWorkspaceStore
    @State private var pendingPlantEditor: GardenPlant?
    @State private var homeBrief: HomeBriefBundle?
    @State private var isLoadingHomeBrief = false
    @State private var isAnalyzingHomeBrief = false
    @State private var homeBriefError: String?
    private let attentionAdvisor = HomeAttentionAdvisor()
    private let homeBriefService = HomeBriefingService.shared

    var body: some View {
        Group {
#if os(macOS)
            macOSBody
#else
            iOSBody
#endif
        }
        .task(id: workspaceStore.selectedSiteID) {
            await refreshHomeBrief()
        }
        .sheet(item: $pendingPlantEditor) { plant in
            IndividualSheet(mode: .edit(plantID: plant.id))
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var iOSBody: some View {
        let stats = store.fetchStats()
        let importantItems = displayedImportantPlantTasks

        CanopyScreen {
            VStack(alignment: .leading, spacing: CanopySpacing.lg) {
                HStack(alignment: .center, spacing: 12) {
                    CanopyIconBadge(systemImage: "leaf.fill", size: CanopyIconSize.card)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspaceStore.selectedSiteName)
                            .font(.title2).bold()
                        Text("Centre de contrôle du jardin vivant")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(.top, 8)

                syncPanel
                homeBriefSection

                if !importantItems.isEmpty {
                    importantActionsSection(items: importantItems, totalCount: importantPlantTasks.count)
                }

                CanopySectionHeader(title: "Actions rapides")

                LazyVGrid(columns: [GridItem(.flexible()),
                                    GridItem(.flexible())],
                          spacing: 12) {
                    if workspaceStore.isModuleEnabled("plants") {
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
                    }
                    if workspaceStore.isModuleEnabled("cartography_gis") {
                        NavigationLink(destination: GardenMapView()) {
                            ActionCard(
                                title: "Carte",
                                subtitle: "Vue géographique du site",
                                systemImage: "map"
                            )
                        }
                    }
                    if workspaceStore.isModuleEnabled("hives") {
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
                    if workspaceStore.isModuleEnabled("plantnet") {
                        NavigationLink(destination: PlantIdentifierView()) {
                            ActionCard(
                                title: "Identifier",
                                subtitle: "PlantNet / reconnaissance",
                                systemImage: "camera.viewfinder"
                            )
                        }
                    }
                }

                CanopySectionHeader(title: "Le jardin en un coup d’œil")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatChip(title: "Individus", value: "\(stats.plantCount)", systemImage: "number")
                        StatChip(title: "Espèces", value: "\(stats.speciesCount)", systemImage: "leaf")
                        StatChip(title: "Ruches", value: "\(stats.hiveCount)", systemImage: "shippingbox")
                        StatChip(title: "Colonies", value: "\(stats.colonyCount)", systemImage: "ant")
                    }
                    .padding(.vertical, 2)
                }

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
        }
    }

    @ViewBuilder
    private var macOSBody: some View {
        let stats = store.fetchStats()
        let importantItems = displayedImportantPlantTasks

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
                            Text(workspaceStore.selectedSiteName)
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
                    homeBriefSection

                    if !importantItems.isEmpty {
                        importantActionsSection(items: importantItems, totalCount: importantPlantTasks.count)
                    }

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

        return CanopyCard(title: "Synchronisation", subtitle: "Projection locale et Supabase", systemImage: "arrow.triangle.2.circlepath") {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    store.forceSyncNow()
                } label: {
                    Label(
                        store.isSyncing ? "Synchro..." : "Forcer la synchro",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .canopyPrimaryActionStyle()
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
    }

    @ViewBuilder
    private var homeBriefSection: some View {
        VStack(alignment: .leading, spacing: CanopySpacing.sm) {
            CanopySectionHeader(
                title: "Brief du jour",
                subtitle: "Meteo, gel et priorites de terrain"
            )

            if let homeBrief {
                HomeBriefCard(
                    bundle: homeBrief,
                    isRefreshing: isLoadingHomeBrief,
                    isAnalyzing: isAnalyzingHomeBrief,
                    onRefresh: {
                        Task { await refreshHomeBrief(force: true, withAI: false) }
                    },
                    onAnalyze: {
                        Task { await refreshHomeBrief(force: true, withAI: true) }
                    }
                )
            } else if isLoadingHomeBrief {
                CanopyCard(title: "Brief du jour", subtitle: "Chargement...", systemImage: "cloud.sun") {
                    ProgressView("Preparation du contexte meteo et terrain...")
                        .font(.subheadline)
                }
            } else if let homeBriefError {
                CanopyCard(title: "Brief du jour", subtitle: "Impossible de charger le brief", systemImage: "exclamationmark.triangle") {
                    VStack(alignment: .leading, spacing: CanopySpacing.sm) {
                        Text(homeBriefError)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Button("Reessayer") {
                            Task { await refreshHomeBrief(force: true, withAI: false) }
                        }
                        .canopySecondaryActionStyle()
                    }
                }
            }
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

    private var importantPlantTasks: [HomePlantAttentionItem] {
        attentionAdvisor.prioritize(
            plants: store.plants,
            isPlantsModuleEnabled: workspaceStore.isModuleEnabled("plants")
        )
    }

    private var displayedImportantPlantTasks: [HomePlantAttentionItem] {
        Array(importantPlantTasks.prefix(4))
    }

    @ViewBuilder
    private func importantActionsSection(items: [HomePlantAttentionItem], totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: CanopySpacing.sm) {
            CanopySectionHeader(
                title: "Actions importantes",
                subtitle: importantActionsSubtitle(totalCount: totalCount)
            )

            VStack(alignment: .leading, spacing: CanopySpacing.sm) {
                ForEach(items) { item in
                    PlantAttentionCard(item: item) {
                        pendingPlantEditor = item.plant
                    }
                }
            }

            let remainingCount = totalCount - items.count
            if remainingCount > 0 {
                NavigationLink(destination: PlantsListView()) {
                    Label(
                        "\(remainingCount) autre\(remainingCount > 1 ? "s" : "") individu\(remainingCount > 1 ? "s" : "") à compléter",
                        systemImage: "list.bullet"
                    )
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentPrimary)
            }
        }
    }

    private func importantActionsSubtitle(totalCount: Int) -> String {
        if totalCount == 1 {
            return "1 individu doit encore être qualifié ou positionné pour garder un suivi fiable."
        }

        return "\(totalCount) individus demandent encore une action de terrain prioritaire."
    }

    @MainActor
    private func refreshHomeBrief(force: Bool = false, withAI: Bool = false) async {
        guard let siteID = workspaceStore.selectedSiteID, !siteID.isEmpty else {
            homeBrief = nil
            homeBriefError = nil
            isLoadingHomeBrief = false
            return
        }

        if !force, homeBrief?.context.site.id == siteID {
            return
        }

        if withAI {
            isAnalyzingHomeBrief = true
        } else {
            isLoadingHomeBrief = true
        }
        defer {
            if withAI {
                isAnalyzingHomeBrief = false
            } else {
                isLoadingHomeBrief = false
            }
        }

        do {
            let loaded = try await homeBriefService.fetch(siteID: siteID, withAI: withAI)
            homeBrief = loaded
            homeBriefError = nil
        } catch {
            homeBriefError = error.localizedDescription
        }
    }
}

struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        CanopyCard(title: title, subtitle: subtitle, systemImage: systemImage) {
            EmptyView()
        }
    }
}

struct StatChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: CanopyIconSize.inline, weight: .medium))
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
        CanopyCard(title: title, systemImage: systemImage) {
            Text(text)
                .font(.footnote)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

private struct PlantAttentionCard: View {
    let item: HomePlantAttentionItem
    let onEdit: () -> Void

    var body: some View {
        CanopyCard(
            title: item.displayTitle,
            subtitle: item.subtitle,
            systemImage: "checklist"
        ) {
            VStack(alignment: .leading, spacing: CanopySpacing.sm) {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)

                HStack(spacing: CanopySpacing.xs) {
                    ForEach(item.missingLabels, id: \.self) { label in
                        Text(label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.accentPrimary.opacity(0.10))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.accentPrimary.opacity(0.25), lineWidth: 1)
                            )
                    }
                }

                if let suggestedSpread = item.suggestedSpread {
                    Text("Suggestion d’envergure de départ: \(metersLabel(suggestedSpread))")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                Button("Compléter la fiche", action: onEdit)
                    .canopyPrimaryActionStyle()
            }
        }
    }

    private func metersLabel(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return "\(rounded.formatted(.number.precision(.fractionLength(0 ... 1)))) m"
    }
}

private struct HomeBriefCard: View {
    let bundle: HomeBriefBundle
    let isRefreshing: Bool
    let isAnalyzing: Bool
    let onRefresh: () -> Void
    let onAnalyze: () -> Void

    var body: some View {
        let briefing = bundle.briefing
        let context = bundle.context

        CanopyCard(
            title: "Meteo et priorites",
            subtitle: homeBriefSubtitle,
            systemImage: "cloud.sun"
        ) {
            VStack(alignment: .leading, spacing: CanopySpacing.md) {
                HStack(alignment: .top, spacing: CanopySpacing.sm) {
                    weatherBlock(title: "Aujourd'hui", lines: [
                        briefing.weatherToday.label,
                        temperatureLine(min: briefing.weatherToday.tMinC, max: briefing.weatherToday.tMaxC),
                        compactMetric(label: "Pluie", value: briefing.weatherToday.precipMM, suffix: " mm"),
                        compactMetric(label: "Vent", value: briefing.weatherToday.windKMH, suffix: " km/h"),
                    ])

                    weatherBlock(title: "Gel", lines: [
                        briefing.frostRisk.label,
                        briefing.frostRisk.nextFrostAt.map { "Prochain gel estime: \(formatDateTime($0))" } ?? "Pas de gel prevu a court terme",
                        briefing.frostRisk.forecastMinC48H.map { "Min 48 h: \(metersOrTempLabel($0, suffix: " C"))" } ?? "Min 48 h: n/d",
                        "Sujets sensibles: \(context.frostRisk.sensitiveIndividualsCount)",
                    ])
                }

                if !briefing.alerts.isEmpty {
                    homeBriefSubsection(title: "Alertes") {
                        ForEach(briefing.alerts) { alert in
                            VStack(alignment: .leading, spacing: CanopySpacing.xxs) {
                                Text(alert.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(color(for: alert.severity))
                                Text(alert.reason)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                }

                if !briefing.tasks.isEmpty {
                    homeBriefSubsection(title: "Actions") {
                        ForEach(briefing.tasks) { task in
                            HStack(alignment: .top, spacing: CanopySpacing.sm) {
                                Text(task.priority.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(color(for: task.priority))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(color(for: task.priority).opacity(0.12)))
                                VStack(alignment: .leading, spacing: CanopySpacing.xxs) {
                                    Text(task.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.textPrimary)
                                    if let targetCount = task.targetCount {
                                        Text("\(targetCount) element\(targetCount > 1 ? "s" : "") concerne\(targetCount > 1 ? "s" : "")")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !briefing.fieldChecks.isEmpty {
                    homeBriefSubsection(title: "Verifications terrain") {
                        ForEach(briefing.fieldChecks, id: \.self) { check in
                            Label(check, systemImage: "scope")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: CanopySpacing.xs) {
                    Text("Synthese")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    Text(briefing.summary)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: CanopySpacing.sm) {
                        Text("Confiance: \(briefing.confidence.capitalized)")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        if let provider = bundle.llm.provider, !provider.isEmpty {
                            Text(bundle.llm.generated ? "Source: \(provider)" : "Fallback: \(provider)")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }

                HStack(spacing: CanopySpacing.sm) {
                    Button {
                        onRefresh()
                    } label: {
                        Label(isRefreshing ? "Actualisation..." : "Actualiser", systemImage: "arrow.clockwise")
                    }
                    .canopySecondaryActionStyle()
                    .disabled(isRefreshing || isAnalyzing)

                    Button {
                        onAnalyze()
                    } label: {
                        Label(isAnalyzing ? "Analyse..." : "Analyser avec l'IA", systemImage: "sparkles")
                    }
                    .canopyPrimaryActionStyle()
                    .disabled(isRefreshing || isAnalyzing)

                    Spacer()

                    Text("Genere le \(formatDateTime(context.generatedAt))")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }

                Text("L'analyse IA reste manuelle pour limiter les couts.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private var homeBriefSubtitle: String {
        if bundle.llm.generated {
            return "Synthese reformulee avec Gemini"
        }
        if let error = bundle.llm.error, !error.isEmpty {
            return "Brief deterministe (IA indisponible ou coupee)"
        }
        return "Contexte deterministe, analyse IA a la demande"
    }

    @ViewBuilder
    private func homeBriefSubsection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CanopySpacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
            VStack(alignment: .leading, spacing: CanopySpacing.sm) {
                content()
            }
        }
    }

    @ViewBuilder
    private func weatherBlock(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: CanopySpacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
            ForEach(lines.filter { !$0.isEmpty }, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(CanopySpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CanopyCornerRadius.sm, style: .continuous)
                .fill(Color.cardBackground.opacity(0.7))
        )
    }

    private func temperatureLine(min: Double?, max: Double?) -> String {
        "Min \(metersOrTempLabel(min, suffix: " C")) / Max \(metersOrTempLabel(max, suffix: " C"))"
    }

    private func compactMetric(label: String, value: Double?, suffix: String) -> String {
        "\(label): \(metersOrTempLabel(value, suffix: suffix))"
    }

    private func metersOrTempLabel(_ value: Double?, suffix: String) -> String {
        guard let value else { return "n/d" }
        return "\(formatNumber(value))\(suffix)"
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func formatDateTime(_ raw: String) -> String {
        let date = isoFormatter.date(from: raw) ?? fallbackISOFormatter.date(from: raw)
        guard let date else { return raw }
        return displayFormatter.string(from: date)
    }

    private func color(for severity: String) -> Color {
        switch severity.lowercased() {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .accentPrimary
        }
    }

    private var isoFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private var fallbackISOFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private var displayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}
