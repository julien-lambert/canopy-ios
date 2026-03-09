import SwiftUI

extension Color {

    // Fond général de l’app
    static var appBackground: Color {
        #if os(iOS)
        Color(UIColor.systemGroupedBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    // MARK: - Card Surface Tokens (source unique)

    // Base concrete card background (no alias to avoid recursion)
    private static var baseCardBackground: Color {
        #if os(iOS)
        Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return .secondarySystemBackground
            }
            // Plus clair que systemGroupedBackground pour retrouver le contraste des cartes
            return .systemBackground
        })
        #else
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var cardSurfaceBackground: Color { baseCardBackground }

    static var cardSurfaceStroke: Color { .clear }

    static var cardSurfaceShadow: Color { .black.opacity(0.05) }

    // Compat aliases
    static var cardBackground: Color { baseCardBackground }
    static var cardContrastBackground: Color { cardSurfaceBackground }
    static var cardContrastStroke: Color { cardSurfaceStroke }
    static var cardContrastShadow: Color { cardSurfaceShadow }

    // Fond des lignes de liste (blanc sur iOS clair, adapté au thème système)
    static var listRowBackground: Color {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.textBackgroundColor)
        #endif
    }

    // Couleur principale
    static var accentPrimary: Color {
        #if os(iOS)
        Color(UIColor.systemGreen)
        #else
        Color(NSColor.systemGreen)
        #endif
    }

    // Texte secondaire
    static var textSecondary: Color {
        #if os(iOS)
        Color(UIColor.secondaryLabel)
        #else
        Color(NSColor.secondaryLabelColor)
        #endif
    }

    // Texte principal
    static var textPrimary: Color {
        #if os(iOS)
        Color(UIColor.label)
        #else
        Color(NSColor.labelColor)
        #endif
    }
}
// MARK: - Liquid Glass Style

extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat = 16) -> some View {
        #if os(iOS)
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.12),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
        #else
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.cardSurfaceBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.cardSurfaceStroke, lineWidth: 1)
                    )
                    .shadow(color: Color.cardSurfaceShadow, radius: 6, x: 0, y: 3)
            )
        #endif
    }
}

