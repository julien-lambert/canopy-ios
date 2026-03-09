import SwiftUI

enum AppBadgeStyle {
    case subtle
    case accent
}

struct AppBadge: View {
    let text: String
    var style: AppBadgeStyle = .subtle

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: style == .accent ? .bold : .semibold))
            .foregroundColor(style == .accent ? .white : .textPrimary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(style == .accent ? Color.accentPrimary : Color.cardBackground)
            )
            .overlay(
                Capsule()
                    .stroke(
                        style == .accent ? Color.accentPrimary : Color.accentPrimary.opacity(0.5),
                        lineWidth: 0.5
                    )
            )
    }
}

