import SwiftUI

enum CanopySpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

enum CanopyCornerRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}

enum CanopyIconSize {
    static let inline: CGFloat = 14
    static let card: CGFloat = 20
    static let hero: CGFloat = 28
}

struct CanopyScreen<Content: View>: View {
    private let spacing: CGFloat
    private let horizontalPadding: CGFloat
    private let content: Content

    init(
        spacing: CGFloat = CanopySpacing.lg,
        horizontalPadding: CGFloat = CanopySpacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, CanopySpacing.md)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

struct CanopySectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: CanopySpacing.xxs) {
            Text(title)
                .font(.headline)
                .foregroundColor(.textPrimary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

struct CanopyIconBadge: View {
    let systemImage: String
    var size: CGFloat = CanopyIconSize.card

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentPrimary.opacity(0.12))
                .frame(width: size * 2.2, height: size * 2.2)
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.accentPrimary)
        }
    }
}

struct CanopyCard<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var systemImage: String? = nil
    private let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CanopySpacing.sm) {
            if title != nil || subtitle != nil || systemImage != nil {
                HStack(alignment: .top, spacing: CanopySpacing.sm) {
                    if let systemImage {
                        CanopyIconBadge(systemImage: systemImage)
                    }

                    VStack(alignment: .leading, spacing: CanopySpacing.xxs) {
                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                        }

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            content
        }
        .padding(CanopySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: CanopyCornerRadius.md)
    }
}

struct CanopySelectableChip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CanopySpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentPrimary : Color.cardBackground)
            )
            .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
            .overlay(
                Capsule()
                    .stroke(
                        Color.accentPrimary.opacity(isSelected ? 0 : 0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CanopyEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: CanopySpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: CanopyIconSize.hero, weight: .medium))
                .foregroundColor(.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct CanopyInfoLine: View {
    let label: String
    let value: String

    var body: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: CanopySpacing.sm) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        #else
        HStack(alignment: .firstTextBaseline, spacing: CanopySpacing.sm) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        #endif
    }
}

struct CanopyToolbarIconButton: View {
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
        }
    }
}

private struct CanopyEditorToolbarModifier: ViewModifier {
    let saveTitle: String
    let isSaveDisabled: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveTitle, action: onSave)
                    .disabled(isSaveDisabled)
                    .fontWeight(.semibold)
            }
        }
    }
}

extension View {
    func canopyPrimaryActionStyle() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(.accentPrimary)
    }

    func canopySecondaryActionStyle() -> some View {
        self
            .buttonStyle(.bordered)
            .tint(.accentPrimary)
    }

    func canopyFloatingCapsule() -> some View {
        self
            .padding(6)
            .background(Color.cardBackground)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    func canopyFloatingCircle() -> some View {
        self
            .padding(6)
            .background(Color.cardBackground)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    func canopyEditorToolbar(
        saveTitle: String = "Enregistrer",
        isSaveDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        modifier(
            CanopyEditorToolbarModifier(
                saveTitle: saveTitle,
                isSaveDisabled: isSaveDisabled,
                onCancel: onCancel,
                onSave: onSave
            )
        )
    }
}
