import Foundation
import Supabase

enum CanopySupabaseClientProvider {
    static let shared: SupabaseClient? = {
        guard let url = CanopySupabaseConfig.url, let key = CanopySupabaseConfig.anonKey else {
            return nil
        }
        let options = SupabaseClientOptions(
            auth: .init(
                redirectToURL: CanopySupabaseConfig.redirectURL,
                emitLocalSessionAsInitialSession: true
            )
        )
        return SupabaseClient(supabaseURL: url, supabaseKey: key, options: options)
    }()
}

enum CanopySupabaseAuthError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Session Supabase absente. Connecte-toi dans l'écran de connexion."
        }
    }
}

actor CanopySupabaseAuthBootstrap {
    static let shared = CanopySupabaseAuthBootstrap()

    func ensureAuthenticated(client: SupabaseClient) async throws -> Session {
        do {
            return try await client.auth.session
        } catch {
            throw CanopySupabaseAuthError.notAuthenticated
        }
    }
}

enum CanopyEdgeFunctionError: LocalizedError {
    case supabaseNotConfigured
    case notAuthenticated
    case noSelectedSite
    case invalidResponse(String)
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured:
            return "Supabase n'est pas configuré dans l'app."
        case .notAuthenticated:
            return "Session Supabase absente ou expirée. Reconnecte-toi avant d'utiliser l'IA."
        case .noSelectedSite:
            return "Aucun site courant sélectionné."
        case .invalidResponse(let functionName):
            return "Réponse invalide de la fonction \(functionName)."
        case .httpError(_, let message):
            return message
        }
    }
}

private struct CanopyEdgeErrorEnvelope: Decodable {
    let ok: Bool?
    let error: String?
    let detail: CanopyJSONValue?
    let allowed: Bool?
    let reason: String?
    let quotaRemaining: Int?
    let quotaTotal: Int?
    let moduleEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case error
        case detail
        case allowed
        case reason
        case quotaRemaining = "quota_remaining"
        case quotaTotal = "quota_total"
        case moduleEnabled = "module_enabled"
    }
}

enum CanopyEdgeFunctionsClient {
    static func currentSiteID() throws -> String {
        let localDB = try CanopyLocalDatabase()
        guard let siteID = try localDB.currentSiteID()?.trimmingCharacters(in: .whitespacesAndNewlines), !siteID.isEmpty else {
            throw CanopyEdgeFunctionError.noSelectedSite
        }
        return siteID
    }

    static func invoke<Response: Decodable>(
        _ functionName: String,
        body: [String: CanopyJSONValue],
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        guard let client = CanopySupabaseClientProvider.shared else {
            throw CanopyEdgeFunctionError.supabaseNotConfigured
        }

        let session = try await CanopySupabaseAuthBootstrap.shared.ensureAuthenticated(client: client)
        client.functions.setAuth(token: session.accessToken)
        do {
            return try await client.functions.invoke(
                functionName,
                options: .init(method: .post, body: body)
            )
        } catch let error as FunctionsError {
            switch error {
            case .httpError(let code, let data):
                throw CanopyEdgeFunctionError.httpError(
                    code,
                    localizedErrorMessage(statusCode: code, data: data, functionName: functionName)
                )
            case .relayError:
                throw CanopyEdgeFunctionError.invalidResponse(functionName)
            }
        } catch let error as CanopyEdgeFunctionError {
            throw error
        } catch {
            throw CanopyEdgeFunctionError.invalidResponse(functionName)
        }
    }

    private static func localizedErrorMessage(statusCode: Int, data: Data, functionName: String) -> String {
        if let envelope = try? JSONDecoder().decode(CanopyEdgeErrorEnvelope.self, from: data) {
            if envelope.allowed == false, let reason = envelope.reason {
                switch reason {
                case "module_disabled":
                    return "Le module requis n'est pas activé pour ce site."
                case "plan_required":
                    return "Le plan actuel n'autorise pas encore cette fonction IA."
                case "quota_exceeded":
                    return "Le quota mensuel de cette fonction IA est atteint."
                default:
                    break
                }
            }

            switch envelope.error {
            case "unauthorized":
                return "Session Supabase expirée. Reconnecte-toi avant d'utiliser l'IA."
            case "site_membership_required":
                return "Ton compte n'a pas accès au site courant."
            case "edge_ai_owner_only":
                return "Cette fonction IA est verrouillée pour l'instant: seul le compte autorisé peut l'utiliser."
            case "edge_ai_access_not_configured":
                return "L'accès IA n'est pas encore configuré côté serveur."
            case .some(let errorCode):
                if let detail = serialize(detail: envelope.detail), !detail.isEmpty {
                    return "Erreur \(functionName) (\(errorCode)): \(detail)"
                }
                return "Erreur \(functionName) (\(errorCode))."
            case .none:
                break
            }
        }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            return "Erreur \(functionName) HTTP \(statusCode): \(raw)"
        }
        return "Erreur \(functionName) HTTP \(statusCode)."
    }

    private static func serialize(detail: CanopyJSONValue?) -> String? {
        guard let detail else { return nil }
        switch detail {
        case .string(let value):
            return value
        default:
            guard let data = try? JSONEncoder().encode(detail) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
