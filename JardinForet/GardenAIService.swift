import Foundation
 
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct PlantNetService {
    private struct EdgeEnvelope: Decodable {
        let ok: Bool
        let data: IdentifyResponse?
    }

    enum PlantNetError: LocalizedError {
        case noImages
        case invalidImageFormat
        case invalidResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .noImages:
                return "Ajoute au moins une photo avant d’identifier."
            case .invalidImageFormat:
                return "Format image non supporté. Utilise une image lisible (JPEG/PNG/HEIC)."
            case .invalidResponse:
                return "Réponse PlantNet invalide."
            case .httpError(let code, let body):
                return "Erreur PlantNet HTTP \(code): \(body)"
            }
        }
    }

    enum Organ: String, CaseIterable, Identifiable, Codable {
        case auto
        case leaf
        case flower
        case fruit
        case bark
        case habit
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto: return "Auto"
            case .leaf: return "Feuille"
            case .flower: return "Fleur"
            case .fruit: return "Fruit"
            case .bark: return "Écorce"
            case .habit: return "Arbre entier"
            case .other: return "Autre"
            }
        }
    }

    struct Observation {
        let imageData: Data
        let organ: Organ
    }

    struct IdentifyResponse: Decodable {
        let bestMatch: String?
        let results: [ResultItem]

        enum CodingKeys: String, CodingKey {
            case bestMatch
            case results
        }
    }

    struct ResultItem: Decodable, Identifiable {
        let id = UUID()
        let score: Double
        let species: Species
        let images: [ResultImage]?

        enum CodingKeys: String, CodingKey {
            case score
            case species
            case images
        }

        var bestImageURL: String? {
            guard let images else { return nil }
            for image in images {
                if let value = normalizedURLString(image.url?.o) { return value }
                if let value = normalizedURLString(image.url?.m) { return value }
                if let value = normalizedURLString(image.url?.s) { return value }
            }
            return nil
        }

        private func normalizedURLString(_ value: String?) -> String? {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed
        }
    }

    struct ResultImage: Decodable {
        let organ: String?
        let url: ResultImageURL?
    }

    struct ResultImageURL: Decodable {
        let o: String?
        let m: String?
        let s: String?
    }

    struct Species: Decodable {
        let scientificNameWithoutAuthor: String?
        let scientificName: String?
        let commonNames: [String]?
        let family: Taxon?
        let genus: Taxon?
    }

    struct Taxon: Decodable {
        let scientificNameWithoutAuthor: String?
        let scientificName: String?
    }

    func identify(observations: [Observation], project: String = "all", lang: String = "fr", nbResults: Int = 5) async throws -> IdentifyResponse {
        guard !observations.isEmpty else {
            throw PlantNetError.noImages
        }

        let normalized: [Observation] = try observations.map { obs in
            guard let normalizedData = normalizeImageDataForPlantNet(obs.imageData) else {
                throw PlantNetError.invalidImageFormat
            }
            return Observation(imageData: normalizedData, organ: obs.organ)
        }

        let siteID = try CanopyEdgeFunctionsClient.currentSiteID()
        let observationsPayload: [CanopyJSONValue] = normalized.enumerated().map { index, observation in
            .object([
                "image_base64": .string(observation.imageData.base64EncodedString()),
                "organ": .string(observation.organ.rawValue),
                "filename": .string("plant_\(index).jpg"),
                "mime_type": .string("image/jpeg")
            ])
        }

        let envelope: EdgeEnvelope = try await CanopyEdgeFunctionsClient.invoke(
            "fn-plantnet-v2",
            body: [
                "site_id": .string(siteID),
                "project": .string(project),
                "lang": .string(lang),
                "nb_results": .int(nbResults),
                "observations": .array(observationsPayload)
            ],
            responseType: EdgeEnvelope.self
        )

        guard envelope.ok, let payload = envelope.data else {
            throw PlantNetError.invalidResponse
        }
        return payload
    }

    func identify(imageData: Data, organ: Organ = .auto, project: String = "all", lang: String = "fr", nbResults: Int = 5) async throws -> IdentifyResponse {
        try await identify(
            observations: [Observation(imageData: imageData, organ: organ)],
            project: project,
            lang: lang,
            nbResults: nbResults
        )
    }

    private func normalizeImageDataForPlantNet(_ data: Data) -> Data? {
        if isJPEG(data) {
            return data
        }

        #if os(iOS)
        if let image = UIImage(data: data) {
            return image.jpegData(compressionQuality: 0.9)
        }
        #elseif os(macOS)
        if let image = NSImage(data: data),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            return jpeg
        }
        #endif

        return nil
    }

    private func isJPEG(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF])
    }
}
struct PlantAIResponse: Codable {
    let nomLatin: String
    let famille: String
    let description: String
    let rusticite: String
    let besoinsEau: String
    let expositionSoleil: String
}

struct SpeciesAIResponse: Codable {
    let commonName: String?
    let nomLatin: String?
    let famille: String?
    let genre: String?
    let strate: String?
    let tags: String?
    let notes: String?
    let imageURL: String?
    let origine: String?
    let typePlante: String?
    let morphologie: String?
    let culture: String?
    let usages: String?
    let niveauMellifere: String?
    let interetOrnemental: String?
    let longeviteMin: String?
    let longeviteMax: String?
    let hauteurMin: String?
    let hauteurMax: String?
    let periodeFloraison: String?
    let periodeFructification: String?
}

struct SpeciesAIPayload: Codable {
    var commonName: String?
    var nomLatin: String?
    var famille: String?
    var genre: String?
    var strate: String?
    var tags: String?
    var notes: String?
    var imageURL: String?
    var origine: String?
    var typePlante: String?
    var morphologie: String?
    var culture: String?
    var usages: String?
    var niveauMellifere: String?
    var interetOrnemental: String?
    var longeviteMin: String?
    var longeviteMax: String?
    var hauteurMin: String?
    var hauteurMax: String?
    var periodeFloraison: String?
    var periodeFructification: String?
}

struct CultivarAIPayload: Codable {
    var species: SpeciesAIPayload
    var cultivar: CultivarFields

    struct CultivarFields: Codable {
        var nom: String?
        var notes: String?
        var tags: String?
        var origine: String?
        var typePlante: String?
        var morphologie: String?
        var culture: String?
        var usages: String?
        var niveauMellifere: String?
        var interetOrnemental: String?
        var longeviteMin: String?
        var longeviteMax: String?
        var hauteurMin: String?
        var hauteurMax: String?
        var periodeFloraison: String?
        var periodeFructification: String?
    }
}

enum GardenAIServiceError: LocalizedError {
    case emptyResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "La réponse Gemini est vide."
        case .invalidJSON:
            return "La réponse Gemini n'est pas un JSON valide."
        }
    }
}

final class GardenAIService {
    static let shared = GardenAIService()

    private struct GeminiEnvelope: Decodable {
        struct Payload: Decodable {
            let model: String?
            let text: String?
            let json: CanopyJSONValue?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case model
                case text
                case json
                case finishReason = "finish_reason"
            }
        }

        let ok: Bool
        let data: Payload?
    }

    private init() {}

    private static let allowedStrata: Set<String> = [
        "canopée", "arbuste", "sous-étage", "herbacée", "couvre-sol", "liane", "racine"
    ]

    private static let deveySystemInstruction = """
    Tu es un assistant botanique pour une application de terrain offline-first.

    CONTRAT DE SORTIE (obligatoire):
    - Réponds uniquement en JSON valide.
    - Aucun markdown, aucun backtick, aucun texte hors JSON.
    - Aucune clé supplémentaire.
    - Si incertain, laisse le champ null ou chaîne vide.
    - Ne modifie jamais un champ déjà rempli par l'utilisateur.

    CONTEXTE SITE (Devey):
    - altitude ~900 m
    - hiver froid avec gels fréquents
    - épisodes ventés
    - été potentiellement sec
    - sols acides (pH ~4.6–5.1)
    - substrat granitique / arène granitique
    - objectif: jardin-forêt résilient

    VOCABULAIRE CONTRÔLÉ:
    - strate ∈ {canopée, arbuste, sous-étage, herbacée, couvre-sol, liane, racine}
    - aucun synonyme pour strate
    - mapping: arbre -> canopée, grimpante -> liane

    NOTES:
    - Si notes est vide, produire 6 lignes max, exactement:
      Devey: ...
      Sol: ...
      Eau: ...
      Froid/Vent: ...
      Implantation: ...
      Risques: ...
    - Chaque ligne doit être actionnable.
    """

    func payloadDictionary<T: Encodable>(from payload: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw GardenAIServiceError.invalidJSON
        }
        return dict
    }

    func completePayload<T: Codable>(_ payload: T) async throws -> T {
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadJSON = String(data: payloadData, encoding: .utf8), !payloadJSON.isEmpty else {
            throw GardenAIServiceError.invalidJSON
        }

        let prompt = """
        Analyse l'objet JSON suivant et complète uniquement les champs vides ("" ou null).
        Garde exactement la même structure JSON.
        Objet:
        \(payloadJSON)
        """

        return try await generateAndDecode(
            prompt: prompt,
            responseSchema: schemaForPayload(payload),
            decode: T.self
        )
    }

    func completeSpeciesPayload(_ payload: SpeciesAIPayload) async throws -> SpeciesAIPayload {
        try await completePayload(payload)
    }

    func completeCultivarPayload(_ payload: CultivarAIPayload) async throws -> CultivarAIPayload {
        try await completePayload(payload)
    }

    func fetchPlantData(for plantName: String) async throws -> PlantAIResponse {
        let trimmedName = plantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw GardenAIServiceError.emptyResponse
        }

        let prompt = """
        Donne UNIQUEMENT un JSON avec les clés exactes:
        nomLatin, famille, description, rusticite, besoinsEau, expositionSoleil.
        Si incertain: chaîne vide.
        description <= 280 caractères.
        Plante: \(trimmedName)
        """

        return try await generateAndDecode(
            prompt: prompt,
            responseSchema: plantAIResponseSchema(),
            decode: PlantAIResponse.self
        )
    }

    func fetchSpeciesData(for plantName: String) async throws -> SpeciesAIResponse {
        let trimmedName = plantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw GardenAIServiceError.emptyResponse
        }

        let prompt = """
        Renvoie UNIQUEMENT un JSON avec exactement ces clés:
        commonName, nomLatin, famille, genre, strate, tags, notes, imageURL, origine, typePlante, morphologie, culture, usages, niveauMellifere, interetOrnemental, longeviteMin, longeviteMax, hauteurMin, hauteurMax, periodeFloraison, periodeFructification.
        Contraintes:
        - si incertain: chaîne vide
        - tags: CSV max 10
        - longeviteMin/longeviteMax: chaîne entière
        - hauteurMin/hauteurMax: chaîne décimale avec point
        Plante: \(trimmedName)
        """

        return try await generateAndDecode(
            prompt: prompt,
            responseSchema: speciesObjectSchema(),
            decode: SpeciesAIResponse.self
        )
    }

    private func generateAndDecode<T: Decodable>(
        prompt: String,
        responseSchema: [String: CanopyJSONValue]?,
        decode: T.Type
    ) async throws -> T {
        let siteID = try CanopyEdgeFunctionsClient.currentSiteID()
        var body: [String: CanopyJSONValue] = [
            "site_id": .string(siteID),
            "prompt": .string(prompt),
            "system_instruction": .string(Self.deveySystemInstruction),
            "response_mime_type": .string("application/json")
        ]
        if let responseSchema {
            body["response_schema"] = .object(responseSchema)
        }

        let envelope: GeminiEnvelope = try await CanopyEdgeFunctionsClient.invoke(
            "fn-gemini-v2",
            body: body,
            responseType: GeminiEnvelope.self
        )

        guard envelope.ok, let payload = envelope.data else {
            throw GardenAIServiceError.emptyResponse
        }

        let jsonData: Data?
        if let rawJSON = payload.json {
            jsonData = try? JSONEncoder().encode(rawJSON)
        } else if let text = normalizedString(payload.text) {
            jsonData = extractJSONObject(from: text)
        } else {
            jsonData = nil
        }

        guard let jsonData else {
            throw GardenAIServiceError.invalidJSON
        }

        let decoded = try JSONDecoder().decode(T.self, from: jsonData)
        let sanitized = await sanitizeDecodedAsync(decoded)
        return await MainActor.run { sanitized }
    }

    private func sanitizeDecodedAsync<T>(_ value: T) async -> T {
        if var species = value as? SpeciesAIPayload {
            species = sanitizeSpeciesPayload(species)
            species.imageURL = await ensureLiveImageURL(species.imageURL)
            if species.imageURL == nil {
                let query = species.nomLatin ?? species.commonName
                species.imageURL = await resolveLiveImageURL(for: query)
            }
            return species as! T
        }
        if var cultivar = value as? CultivarAIPayload {
            cultivar = sanitizeCultivarPayload(cultivar)
            cultivar.species.imageURL = await ensureLiveImageURL(cultivar.species.imageURL)
            if cultivar.species.imageURL == nil {
                let query = cultivar.species.nomLatin ?? cultivar.species.commonName ?? cultivar.cultivar.nom
                cultivar.species.imageURL = await resolveLiveImageURL(for: query)
            }
            return cultivar as! T
        }
        if let speciesResponse = value as? SpeciesAIResponse {
            var sanitized = sanitizeSpeciesResponse(speciesResponse)
            let imageURL = await ensureLiveImageURL(sanitized.imageURL)
            sanitized = SpeciesAIResponse(
                commonName: sanitized.commonName,
                nomLatin: sanitized.nomLatin,
                famille: sanitized.famille,
                genre: sanitized.genre,
                strate: sanitized.strate,
                tags: sanitized.tags,
                notes: sanitized.notes,
                imageURL: imageURL,
                origine: sanitized.origine,
                typePlante: sanitized.typePlante,
                morphologie: sanitized.morphologie,
                culture: sanitized.culture,
                usages: sanitized.usages,
                niveauMellifere: sanitized.niveauMellifere,
                interetOrnemental: sanitized.interetOrnemental,
                longeviteMin: sanitized.longeviteMin,
                longeviteMax: sanitized.longeviteMax,
                hauteurMin: sanitized.hauteurMin,
                hauteurMax: sanitized.hauteurMax,
                periodeFloraison: sanitized.periodeFloraison,
                periodeFructification: sanitized.periodeFructification
            )
            if sanitized.imageURL == nil {
                let query = sanitized.nomLatin ?? sanitized.commonName
                let fallback = await resolveLiveImageURL(for: query)
                sanitized = SpeciesAIResponse(
                    commonName: sanitized.commonName,
                    nomLatin: sanitized.nomLatin,
                    famille: sanitized.famille,
                    genre: sanitized.genre,
                    strate: sanitized.strate,
                    tags: sanitized.tags,
                    notes: sanitized.notes,
                    imageURL: fallback,
                    origine: sanitized.origine,
                    typePlante: sanitized.typePlante,
                    morphologie: sanitized.morphologie,
                    culture: sanitized.culture,
                    usages: sanitized.usages,
                    niveauMellifere: sanitized.niveauMellifere,
                    interetOrnemental: sanitized.interetOrnemental,
                    longeviteMin: sanitized.longeviteMin,
                    longeviteMax: sanitized.longeviteMax,
                    hauteurMin: sanitized.hauteurMin,
                    hauteurMax: sanitized.hauteurMax,
                    periodeFloraison: sanitized.periodeFloraison,
                    periodeFructification: sanitized.periodeFructification
                )
            }
            return sanitized as! T
        }
        return value
    }

    private func ensureLiveImageURL(_ value: String?) async -> String? {
        guard let raw = normalizedString(value), let url = URL(string: raw) else {
            return nil
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return await isReachableImageURL(url) ? raw : nil
    }

    private func isReachableImageURL(_ url: URL) async -> Bool {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 8
        head.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: head)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if mime.hasPrefix("image/") {
                    return true
                }
            }
        } catch {
            // On tente un fallback GET (certains serveurs refusent HEAD).
        }

        var get = URLRequest(url: url)
        get.httpMethod = "GET"
        get.timeoutInterval = 8
        get.cachePolicy = .reloadIgnoringLocalCacheData
        get.setValue("bytes=0-1024", forHTTPHeaderField: "Range")

        do {
            let (_, response) = try await URLSession.shared.data(for: get)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            guard (200...299).contains(http.statusCode) || http.statusCode == 206 else {
                return false
            }
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            return mime.hasPrefix("image/")
        } catch {
            return false
        }
    }

    private struct WikiSummaryResponse: Decodable {
        struct ImageRef: Decodable {
            let source: String?
        }

        let thumbnail: ImageRef?
        let originalimage: ImageRef?
    }

    private func resolveLiveImageURL(for query: String?) async -> String? {
        guard let name = normalizedString(query) else { return nil }

        let titles: [String] = [name, name.replacingOccurrences(of: " ", with: "_")]
        let hosts = ["fr.wikipedia.org", "en.wikipedia.org"]

        for host in hosts {
            for title in titles {
                guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    continue
                }
                guard let url = URL(string: "https://\(host)/api/rest_v1/page/summary/\(encoded)") else {
                    continue
                }

                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continue
                    }
                    let decoded = try JSONDecoder().decode(WikiSummaryResponse.self, from: data)
                    let candidates = [decoded.originalimage?.source, decoded.thumbnail?.source]
                    for candidate in candidates {
                        if let valid = await ensureLiveImageURL(candidate) {
                            return valid
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        return nil
    }

    private func sanitizeSpeciesPayload(_ payload: SpeciesAIPayload) -> SpeciesAIPayload {
        var clean = payload
        clean.commonName = normalizedString(clean.commonName)
        clean.nomLatin = normalizedString(clean.nomLatin)
        clean.famille = normalizedString(clean.famille)
        clean.genre = normalizedString(clean.genre)
        clean.strate = normalizedStrata(clean.strate)
        clean.tags = normalizedTags(clean.tags)
        clean.notes = normalizedNotes(clean.notes)
        clean.imageURL = normalizedString(clean.imageURL)
        clean.origine = normalizedString(clean.origine)
        clean.typePlante = normalizedString(clean.typePlante)
        clean.morphologie = normalizedString(clean.morphologie)
        clean.culture = normalizedString(clean.culture)
        clean.usages = normalizedString(clean.usages)
        clean.niveauMellifere = normalizedString(clean.niveauMellifere)
        clean.interetOrnemental = normalizedString(clean.interetOrnemental)
        clean.longeviteMin = normalizedIntegerString(clean.longeviteMin)
        clean.longeviteMax = normalizedIntegerString(clean.longeviteMax)
        clean.hauteurMin = normalizedDecimalString(clean.hauteurMin)
        clean.hauteurMax = normalizedDecimalString(clean.hauteurMax)
        clean.periodeFloraison = normalizedString(clean.periodeFloraison)
        clean.periodeFructification = normalizedString(clean.periodeFructification)
        return clean
    }

    private func sanitizeCultivarPayload(_ payload: CultivarAIPayload) -> CultivarAIPayload {
        var clean = payload
        clean.species = sanitizeSpeciesPayload(payload.species)

        var c = clean.cultivar
        c.nom = normalizedString(c.nom)
        c.notes = normalizedNotes(c.notes)
        c.tags = normalizedTags(c.tags)
        c.origine = normalizedString(c.origine)
        c.typePlante = normalizedString(c.typePlante)
        c.morphologie = normalizedString(c.morphologie)
        c.culture = normalizedString(c.culture)
        c.usages = normalizedString(c.usages)
        c.niveauMellifere = normalizedString(c.niveauMellifere)
        c.interetOrnemental = normalizedString(c.interetOrnemental)
        c.longeviteMin = normalizedIntegerString(c.longeviteMin)
        c.longeviteMax = normalizedIntegerString(c.longeviteMax)
        c.hauteurMin = normalizedDecimalString(c.hauteurMin)
        c.hauteurMax = normalizedDecimalString(c.hauteurMax)
        c.periodeFloraison = normalizedString(c.periodeFloraison)
        c.periodeFructification = normalizedString(c.periodeFructification)
        clean.cultivar = c

        return clean
    }

    private func sanitizeSpeciesResponse(_ response: SpeciesAIResponse) -> SpeciesAIResponse {
        SpeciesAIResponse(
            commonName: normalizedString(response.commonName),
            nomLatin: normalizedString(response.nomLatin),
            famille: normalizedString(response.famille),
            genre: normalizedString(response.genre),
            strate: normalizedStrata(response.strate),
            tags: normalizedTags(response.tags),
            notes: normalizedNotes(response.notes),
            imageURL: normalizedString(response.imageURL),
            origine: normalizedString(response.origine),
            typePlante: normalizedString(response.typePlante),
            morphologie: normalizedString(response.morphologie),
            culture: normalizedString(response.culture),
            usages: normalizedString(response.usages),
            niveauMellifere: normalizedString(response.niveauMellifere),
            interetOrnemental: normalizedString(response.interetOrnemental),
            longeviteMin: normalizedIntegerString(response.longeviteMin),
            longeviteMax: normalizedIntegerString(response.longeviteMax),
            hauteurMin: normalizedDecimalString(response.hauteurMin),
            hauteurMax: normalizedDecimalString(response.hauteurMax),
            periodeFloraison: normalizedString(response.periodeFloraison),
            periodeFructification: normalizedString(response.periodeFructification)
        )
    }

    private func normalizedString(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedTags(_ value: String?) -> String? {
        let raw = normalizedString(value) ?? ""
        guard !raw.isEmpty else { return nil }

        var seen = Set<String>()
        var ordered: [String] = []

        raw.split(whereSeparator: { ",;|\n".contains($0) }).forEach { token in
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(cleaned)
        }

        if ordered.isEmpty { return nil }
        return String(ordered.prefix(10).joined(separator: ", "))
    }

    private func normalizedNotes(_ value: String?) -> String? {
        let raw = normalizedString(value) ?? ""
        guard !raw.isEmpty else { return nil }

        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let limitedLines = Array(lines.prefix(6))
        let joined = limitedLines.joined(separator: "\n")
        if joined.count <= 600 {
            return joined
        }
        return String(joined.prefix(600))
    }

    private func normalizedIntegerString(_ value: String?) -> String? {
        let raw = normalizedString(value) ?? ""
        guard !raw.isEmpty else { return nil }

        let digits = raw.filter { $0.isNumber || $0 == "-" }
        guard let intValue = Int(digits) else {
            return nil
        }
        return String(intValue)
    }

    private func normalizedDecimalString(_ value: String?) -> String? {
        let raw = normalizedString(value) ?? ""
        guard !raw.isEmpty else { return nil }

        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized) else {
            return nil
        }
        return String(format: "%.2f", number)
    }

    private func normalizedStrata(_ value: String?) -> String? {
        let raw = normalizedString(value) ?? ""
        guard !raw.isEmpty else { return nil }

        let folded = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let mapped: String
        switch folded {
        case "canopee", "canopy", "arbre", "arbres":
            mapped = "canopée"
        case "arbuste", "arbustes":
            mapped = "arbuste"
        case "sous etage", "sous etages":
            mapped = "sous-étage"
        case "herbacee", "herbacees":
            mapped = "herbacée"
        case "couvre sol", "couvre sols":
            mapped = "couvre-sol"
        case "liane", "lianes", "grimpante", "grimpantes":
            mapped = "liane"
        case "racine", "racines", "racinaire":
            mapped = "racine"
        default:
            mapped = raw
        }

        return Self.allowedStrata.contains(mapped) ? mapped : nil
    }

    private func extractJSONObject(from text: String) -> Data? {
        if let directData = text.data(using: .utf8) {
            return directData
        }
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else {
            return nil
        }
        let payload = String(text[start...end])
        return payload.data(using: .utf8)
    }

    private func schemaForPayload(_ payload: Any) -> [String: CanopyJSONValue]? {
        if payload is SpeciesAIPayload {
            return speciesObjectSchema()
        }
        if payload is CultivarAIPayload {
            return cultivarPayloadSchema()
        }
        return nil
    }

    private func plantAIResponseSchema() -> [String: CanopyJSONValue] {
        let properties: [String: CanopyJSONValue] = [
            "nomLatin": stringSchema(nullable: false),
            "famille": stringSchema(nullable: false),
            "description": stringSchema(nullable: false),
            "rusticite": stringSchema(nullable: false),
            "besoinsEau": stringSchema(nullable: false),
            "expositionSoleil": stringSchema(nullable: false)
        ]
        return objectSchema(
            properties: properties,
            requiredProperties: Array(properties.keys)
        )
    }

    private func speciesObjectSchema() -> [String: CanopyJSONValue] {
        let properties: [String: CanopyJSONValue] = [
            "commonName": stringSchema(nullable: true),
            "nomLatin": stringSchema(nullable: true),
            "famille": stringSchema(nullable: true),
            "genre": stringSchema(nullable: true),
            "strate": stringSchema(nullable: true),
            "tags": stringSchema(nullable: true),
            "notes": stringSchema(nullable: true),
            "imageURL": stringSchema(nullable: true),
            "origine": stringSchema(nullable: true),
            "typePlante": stringSchema(nullable: true),
            "morphologie": stringSchema(nullable: true),
            "culture": stringSchema(nullable: true),
            "usages": stringSchema(nullable: true),
            "niveauMellifere": stringSchema(nullable: true),
            "interetOrnemental": stringSchema(nullable: true),
            "longeviteMin": stringSchema(nullable: true),
            "longeviteMax": stringSchema(nullable: true),
            "hauteurMin": stringSchema(nullable: true),
            "hauteurMax": stringSchema(nullable: true),
            "periodeFloraison": stringSchema(nullable: true),
            "periodeFructification": stringSchema(nullable: true)
        ]
        return objectSchema(
            properties: properties,
            requiredProperties: Array(properties.keys)
        )
    }

    private func cultivarPayloadSchema() -> [String: CanopyJSONValue] {
        let cultivarProperties: [String: CanopyJSONValue] = [
            "nom": stringSchema(nullable: true),
            "notes": stringSchema(nullable: true),
            "tags": stringSchema(nullable: true),
            "origine": stringSchema(nullable: true),
            "typePlante": stringSchema(nullable: true),
            "morphologie": stringSchema(nullable: true),
            "culture": stringSchema(nullable: true),
            "usages": stringSchema(nullable: true),
            "niveauMellifere": stringSchema(nullable: true),
            "interetOrnemental": stringSchema(nullable: true),
            "longeviteMin": stringSchema(nullable: true),
            "longeviteMax": stringSchema(nullable: true),
            "hauteurMin": stringSchema(nullable: true),
            "hauteurMax": stringSchema(nullable: true),
            "periodeFloraison": stringSchema(nullable: true),
            "periodeFructification": stringSchema(nullable: true)
        ]

        let cultivarSchema = objectSchema(
            properties: cultivarProperties,
            requiredProperties: Array(cultivarProperties.keys)
        )

        return objectSchema(
            properties: [
                "species": .object(speciesObjectSchema()),
                "cultivar": .object(cultivarSchema)
            ],
            requiredProperties: ["species", "cultivar"]
        )
    }

    private func objectSchema(
        properties: [String: CanopyJSONValue],
        requiredProperties: [String]
    ) -> [String: CanopyJSONValue] {
        [
            "type": .string("OBJECT"),
            "properties": .object(properties),
            "required": .array(requiredProperties.map { .string($0) })
        ]
    }

    private func stringSchema(nullable: Bool) -> CanopyJSONValue {
        .object([
            "type": .string("STRING"),
            "nullable": .bool(nullable)
        ])
    }
}
