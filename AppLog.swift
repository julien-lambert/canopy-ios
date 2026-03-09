import Foundation
import OSLog

enum AppLogCategory: String {
    case general
    case database
    case sync
    case map
    case ui
    case network
    case ar
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "JardinForet"

    static var isVerboseEnabled: Bool {
        if ProcessInfo.processInfo.environment["APP_VERBOSE_LOGS"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "verbose_logging")
    }

    private static func logger(for category: AppLogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func debug(_ message: String, category: AppLogCategory = .general) {
        guard isVerboseEnabled else { return }
        logger(for: category).debug("\(message, privacy: .public)")
    }

    static func info(_ message: String, category: AppLogCategory = .general) {
        guard isVerboseEnabled else { return }
        logger(for: category).info("\(message, privacy: .public)")
    }

    static func warning(_ message: String, category: AppLogCategory = .general) {
        logger(for: category).warning("\(message, privacy: .public)")
    }

    static func error(_ message: String, category: AppLogCategory = .general) {
        logger(for: category).error("\(message, privacy: .public)")
    }
}
