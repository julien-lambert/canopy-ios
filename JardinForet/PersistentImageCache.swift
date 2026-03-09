//
//  Untitled.swift
//  JardinForet
//
//  Created by Julien Lambert on 21/11/2025.
//

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

actor PersistentImageCache {
    static let shared = PersistentImageCache()

    private let memoryCache = NSCache<NSURL, PlatformImage>()
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private var failedRemoteURLs: [String: Date] = [:]
    private let failedURLTTL: TimeInterval = 60 * 60 * 12 // 12h

    init() {
        // ~/Library/Caches/ImageCache
        let cachesDir = fileManager.urls(for: .cachesDirectory,
                                         in: .userDomainMask).first!
        let dir = cachesDir.appendingPathComponent("ImageCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir,
                                             withIntermediateDirectories: true)
        }
        self.directoryURL = dir
    }

    func loadImage(for url: URL) async throws -> PlatformImage {
        let nsURL = url as NSURL

        // 1) Mémoire
        if let cached = memoryCache.object(forKey: nsURL) {
            trace("memory hit url=\(url.absoluteString)")
            return cached
        }

        // 1bis) Fichier local direct (imageLocal)
        if url.isFileURL {
            let localPath = url.path
            guard fileManager.fileExists(atPath: localPath),
                  let data = try? Data(contentsOf: url),
                  let image = PlatformImage(data: data) else {
                trace("local file missing url=\(url.absoluteString)")
                throw NSError(
                    domain: "ImageCache",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Fichier image local introuvable ou invalide: \(localPath)"]
                )
            }
            memoryCache.setObject(image, forKey: nsURL)
            trace("local file loaded url=\(url.absoluteString)")
            return image
        }

        // 1ter) URL distante déjà connue invalide récemment (évite retries/bruit réseau)
        let key = url.absoluteString
        if let failedAt = failedRemoteURLs[key], Date().timeIntervalSince(failedAt) < failedURLTTL {
            trace("recently failed url=\(key)")
            throw NSError(
                domain: "ImageCache",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "URL image marquée invalide récemment: \(key)"]
            )
        }

        // 2) Disque
        let diskURL = fileURL(for: url)
        if fileManager.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL),
           let image = PlatformImage(data: data) {
            memoryCache.setObject(image, forKey: nsURL)
            trace("disk hit url=\(url.absoluteString) file=\(diskURL.path)")
            return image
        }

        // 3) Réseau
        trace("network fetch start url=\(url.absoluteString)")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let nsError = error as NSError
            print("[ImageTrace] network error url=\(url.absoluteString) error=\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)")
            trace("network fetch failed url=\(url.absoluteString)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            print("[ImageCache] Response invalid for \(url.absoluteString)")
            throw NSError(
                domain: "ImageCache",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Réponse réseau invalide"]
            )
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 404 || http.statusCode == 410 {
                failedRemoteURLs[key] = Date()
            }
            print("[ImageCache] HTTP \(http.statusCode) for \(url.absoluteString)")
            throw NSError(
                domain: "ImageCache",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) pour \(url.absoluteString)"]
            )
        }

        guard let image = PlatformImage(data: data) else {
            print("[ImageCache] Invalid image data for \(url.absoluteString) contentType=\(http.value(forHTTPHeaderField: "Content-Type") ?? "n/a")")
            throw NSError(domain: "ImageCache",
                          code: -1,
                          userInfo: [
                            NSLocalizedDescriptionKey: "Données image invalides",
                            "contentType": (http.value(forHTTPHeaderField: "Content-Type") ?? "n/a"),
                            "url": url.absoluteString
                          ])
        }

        memoryCache.setObject(image, forKey: nsURL)
        failedRemoteURLs.removeValue(forKey: key)
        try? data.write(to: diskURL, options: .atomic)
        trace("network fetch success url=\(url.absoluteString) file=\(diskURL.path)")

        return image
    }

    // Optionnel : pour purge ciblée
    func removeImage(for url: URL) {
        let nsURL = url as NSURL
        memoryCache.removeObject(forKey: nsURL)
        let diskURL = fileURL(for: url)
        try? fileManager.removeItem(at: diskURL)
    }

    func removeAll() {
        memoryCache.removeAllObjects()
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        if let files = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            for fileURL in files {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    func preloadImages(urls: [URL]) async -> (loaded: Int, failed: Int, notFound: Int) {
        var loaded = 0
        var failed = 0
        var notFound = 0
        for url in urls {
            do {
                _ = try await loadImage(for: url)
                loaded += 1
            } catch let error as NSError {
                failed += 1
                if error.domain == "ImageCache", error.code == 404 || error.code == 410 {
                    notFound += 1
                }
            } catch {
                failed += 1
            }
        }
        return (loaded, failed, notFound)
    }

    // MARK: - Helpers

    private func fileURL(for url: URL) -> URL {
        // Hash simple du absoluteString pour avoir un nom de fichier stable
        let filename = sha256(url.absoluteString) + ".img"
        return directoryURL.appendingPathComponent(filename)
    }

    private func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else {
            return UUID().uuidString
        }

        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback : pas cryptographiquement parfait, mais suffisant pour un nom de fichier
        return String(string.hashValue)
        #endif
    }

    private func trace(_ message: String) {
        guard AppLog.isVerboseEnabled else { return }
        let line = "[ImageTrace] \(message)"
        print(line)
        AppLog.info(line, category: .network)
    }
}
