import Foundation
import Security
import SwiftUI

enum APIError: LocalizedError {
    case unauthorized
    case serverError(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Сессия истекла или требуется вход по паролю CRM."
        case .serverError(let msg):
            return msg
        case .invalidURL:
            return "Некорректный URL сервера."
        }
    }
}

// MARK: - Keychain Helper

enum KeychainStore {
    private static let service = "fun.wallburn.trainbot.ios"
    private static let tokenAccount = "bearer_token"

    static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - TrainBot API Client

@MainActor
final class TrainBotAPIClient: ObservableObject {
    static let shared = TrainBotAPIClient()

    @AppStorage("trainbot_base_url") var baseURL: String = "https://fitness.wallburn.fun"
    @Published var token: String? = KeychainStore.loadToken()
    @Published var isAuthenticated: Bool = KeychainStore.loadToken() != nil

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        return URLSession(configuration: config)
    }()

    private func makeRequest(path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: trimmedBase + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError("Нет ответа от сервера")
        }
        if http.statusCode == 401 {
            logout()
            throw APIError.unauthorized
        }
        if !(200...299).contains(http.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("Ошибка сервера (\(http.statusCode))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Auth

    func login(password: String, deviceName: String = UIDevice.current.name) async throws {
        let req = try makeRequest(
            path: "/api/v2/auth/token",
            method: "POST",
            body: ["password": password, "device_name": deviceName, "ttl_days": 180]
        )
        let res = try await perform(req, as: AuthTokenResponse.self)
        KeychainStore.saveToken(res.token)
        self.token = res.token
        self.isAuthenticated = true
    }

    func logout() {
        KeychainStore.deleteToken()
        self.token = nil
        self.isAuthenticated = false
    }

    // MARK: Bootstrap & Equipment

    func fetchBootstrap() async throws -> BootstrapResponse {
        let req = try makeRequest(path: "/api/v2/bootstrap")
        return try await perform(req, as: BootstrapResponse.self)
    }

    func fetchEquipment(query: String = "", category: String = "") async throws -> [EquipmentItem] {
        var comps = URLComponents(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/api/v2/equipment")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "limit", value: "250")
        ]
        guard let url = comps?.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        if let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let res = try await perform(req, as: EquipmentListResponse.self)
        return res.items
    }

    func resolveEquipment(
        qrPayload: String? = nil,
        query: String? = nil,
        equipmentId: String? = nil,
        imageJPEGData: Data? = nil,
        activate: Bool = true
    ) async throws -> MachineResolveResponse {
        var body: [String: Any] = ["activate": activate]
        if let qr = qrPayload, !qr.isEmpty { body["qr_payload"] = qr }
        if let q = query, !q.isEmpty { body["query"] = q }
        if let eqId = equipmentId, !eqId.isEmpty { body["equipment_id"] = eqId }
        if let img = imageJPEGData { body["image_base64"] = img.base64EncodedString() }

        let req = try makeRequest(path: "/api/v2/equipment/resolve", method: "POST", body: body)
        return try await perform(req, as: MachineResolveResponse.self)
    }

    func bindQR(qrCode: String, equipmentId: String, label: String = "") async throws {
        let req = try makeRequest(
            path: "/api/v2/equipment/bind-qr",
            method: "POST",
            body: ["qr_code": qrCode, "equipment_id": equipmentId, "label": label]
        )
        _ = try await session.data(for: req)
    }

    // MARK: Quick Set Logging & Undo

    func logQuickSet(
        equipmentId: String?,
        exercise: String?,
        weight: String,
        sets: Int = 1,
        reps: String,
        rir: String = "2",
        comment: String = ""
    ) async throws -> QuickSetResponse {
        var body: [String: Any] = [
            "weight": weight,
            "sets": sets,
            "reps": reps,
            "rir": rir,
            "comment": comment
        ]
        if let eqId = equipmentId { body["equipment_id"] = eqId }
        if let ex = exercise { body["exercise"] = ex }
        let req = try makeRequest(path: "/api/v2/workouts/quick-set", method: "POST", body: body)
        return try await perform(req, as: QuickSetResponse.self)
    }

    func undoWorkout(id: Int) async throws {
        let req = try makeRequest(path: "/api/v2/workouts/\(id)", method: "DELETE")
        _ = try await session.data(for: req)
    }

    // MARK: InBody OCR & History

    func fetchInBodyHistory() async throws -> InBodyHistoryResponse {
        let req = try makeRequest(path: "/api/v2/inbody")
        return try await perform(req, as: InBodyHistoryResponse.self)
    }

    func uploadInBody(fileData: Data, mimeType: String, filename: String) async throws -> InBodyUploadResponse {
        let body: [String: Any] = [
            "file_base64": fileData.base64EncodedString(),
            "mime_type": mimeType,
            "filename": filename
        ]
        let req = try makeRequest(path: "/api/v2/inbody/upload", method: "POST", body: body)
        return try await perform(req, as: InBodyUploadResponse.self)
    }

    // MARK: Apple HealthKit Sync

    func syncHealthKit(payload: [String: Any]) async throws {
        let req = try makeRequest(path: "/api/v2/healthkit/sync", method: "POST", body: payload)
        _ = try await session.data(for: req)
    }

    // MARK: AI Coach Chat

    func sendCoachMessage(_ text: String) async throws -> CoachChatResponse {
        let req = try makeRequest(path: "/api/v2/chat", method: "POST", body: ["message": text])
        return try await perform(req, as: CoachChatResponse.self)
    }

    // MARK: Visual PNG Cards

    func fetchCardPNG(type: String, date: String? = nil, equipmentId: String? = nil) async throws -> Data {
        var comps = URLComponents(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/api/v2/cards/\(type)")
        var items: [URLQueryItem] = []
        if let date = date { items.append(URLQueryItem(name: "date", value: date)) }
        if let eqId = equipmentId { items.append(URLQueryItem(name: "equipment_id", value: eqId)) }
        if !items.isEmpty { comps?.queryItems = items }
        guard let url = comps?.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        if let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await session.data(for: req)
        return data
    }

    func equipmentImageURL(for equipmentId: String) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return URL(string: "\(trimmedBase)/api/equipment/\(equipmentId)/image")
    }
}
