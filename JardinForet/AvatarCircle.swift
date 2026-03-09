import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AvatarCircle: View {
    let title: String          // pour les initiales si pas d’image
    let imageURL: String?      // URL web optionnelle
    let localImageURL: String? // chemin local optionnel pour l’individu

    init(title: String, imageURL: String?, localImageURL: String? = nil) {
        self.title = title
        self.imageURL = imageURL
        self.localImageURL = localImageURL
    }

    private var initials: String {
        let comps = title.split(separator: " ")
        let letters = comps.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Group {
            if let url = resolvedPlantImageURL(local: localImageURL, remote: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(Color.cardBackground)
            .overlay(
                Text(initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentPrimary)
            )
    }
}
