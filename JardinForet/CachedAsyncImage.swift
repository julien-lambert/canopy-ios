//
//  CachedAsyncImage.swift
//  JardinForet
//
//  Created by Julien Lambert on 21/11/2025.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var platformImage: PlatformImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let platformImage {
                #if canImport(UIKit)
                content(Image(uiImage: platformImage).renderingMode(.original))
                #elseif canImport(AppKit)
                content(Image(nsImage: platformImage).renderingMode(.original))
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            if platformImage != nil {
                platformImage = nil
            }
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard let url = url else {
            trace("loadIfNeeded url=nil")
            return
        }
        if platformImage != nil { return }        // déjà chargé dans l’état local

        trace("loadIfNeeded url=\(url.absoluteString)")
        isLoading = true
        defer { isLoading = false }

        do {
            let image = try await PersistentImageCache.shared.loadImage(for: url)
            await MainActor.run {
                platformImage = image
            }
            trace("loadIfNeeded success url=\(url.absoluteString)")
        } catch {
            let nsError = error as NSError
            if nsError.isURLCancellation || error is CancellationError {
                AppLog.debug("Chargement image annule: \(url)", category: .network)
            } else if nsError.domain == "ImageCache", nsError.code == 404 || nsError.code == 410 {
                AppLog.debug("Image indisponible (404/410): \(url)", category: .network)
            } else if nsError.isTransientImageNetworkFailure {
                AppLog.debug("Image temporairement indisponible: \(url)", category: .network)
            } else {
                AppLog.warning("Erreur chargement image \(url): \(error)", category: .network)
            }
        }
    }

    private func trace(_ message: String) {
        guard AppLog.isVerboseEnabled else { return }
        let line = "[ImageTrace] \(message)"
        print(line)
        AppLog.info(line, category: .network)
    }
}

func resolvedImageURL(from rawValue: String?) -> URL? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if let direct = URL(string: value), isUsableURL(direct) {
        return direct
    }
    if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
       let url = URL(string: encoded),
       isUsableURL(url) {
        return url
    }

    if value.hasPrefix("/") || FileManager.default.fileExists(atPath: value) {
        let fileURL = URL(fileURLWithPath: value)
        return isUsableURL(fileURL) ? fileURL : nil
    }

    return nil
}

private func isUsableURL(_ url: URL) -> Bool {
    if url.isFileURL {
        return FileManager.default.fileExists(atPath: url.path)
    }
    guard let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
        return false
    }
    return url.host != nil
}

func resolvedPlantImageURL(local localValue: String?, remote remoteValue: String?) -> URL? {
    if let localURL = resolvedImageURL(from: localValue) {
        if AppLog.isVerboseEnabled {
            let line = "[ImageTrace] resolvedPlantImageURL picked local=\(localURL.absoluteString)"
            print(line)
            AppLog.info(line, category: .network)
        }
        return localURL
    }
    let remote = resolvedImageURL(from: remoteValue)
    if AppLog.isVerboseEnabled {
        let chosen = remote?.absoluteString ?? "nil"
        let line = "[ImageTrace] resolvedPlantImageURL picked remote=\(chosen)"
        print(line)
        AppLog.info(line, category: .network)
    }
    return remote
}

private extension NSError {
    var isURLCancellation: Bool {
        domain == NSURLErrorDomain && code == NSURLErrorCancelled
    }

    var isTransientImageNetworkFailure: Bool {
        guard domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
            NSURLErrorCannotLoadFromNetwork
        ].contains(code)
    }
}
