import Foundation

/// State of a light as reported by the Elgato API (port 9123, /elgato/lights).
struct LightState: Codable, Equatable {
    var on: Int            // 0 = off, 1 = on
    var brightness: Int    // 3...100
    var temperature: Int   // 143...344 (≈ 7000 K ... 2900 K)
}

/// Partial update: only the fields that are set are sent to the light.
struct LightPatch: Encodable {
    var on: Int?
    var brightness: Int?
    var temperature: Int?
}

/// Device details from /elgato/accessory-info.
struct AccessoryInfo: Decodable, Equatable {
    var productName: String?
    var displayName: String?
    var serialNumber: String?
    var firmwareVersion: String?
    var firmwareBuildNumber: Int?
    var hardwareBoardType: Int?
    var macAddress: String?
}

private struct LightsPayload: Decodable {
    var lights: [LightState]
}

private struct PatchPayload: Encodable {
    var numberOfLights = 1
    var lights: [LightPatch]
}

enum KeyLightError: LocalizedError {
    case noAddress, badResponse(Int), noLights

    var errorDescription: String? {
        switch self {
        case .noAddress: return "No address configured"
        case .badResponse(let code): return "Unexpected response (HTTP \(code))"
        case .noLights: return "No light found"
        }
    }
}

struct KeyLightClient {
    var host: String
    var port: Int = 9123

    private func url(_ path: String) -> URL? {
        var h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return nil }
        // IPv6 literals need brackets inside a URL.
        if h.contains(":") && !h.hasPrefix("[") { h = "[\(h)]" }
        return URL(string: "http://\(h):\(port)/elgato/\(path)")
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }()

    func fetch() async throws -> LightState {
        guard let url = url("lights") else { throw KeyLightError.noAddress }
        let (data, resp) = try await Self.session.data(from: url)
        try check(resp)
        let payload = try JSONDecoder().decode(LightsPayload.self, from: data)
        guard let first = payload.lights.first else { throw KeyLightError.noLights }
        return first
    }

    func fetchInfo() async throws -> AccessoryInfo {
        guard let url = url("accessory-info") else { throw KeyLightError.noAddress }
        let (data, resp) = try await Self.session.data(from: url)
        try check(resp)
        return try JSONDecoder().decode(AccessoryInfo.self, from: data)
    }

    /// Sends a partial update and returns the state the light reports back, if any.
    @discardableResult
    func send(_ patch: LightPatch) async throws -> LightState? {
        guard let url = url("lights") else { throw KeyLightError.noAddress }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(PatchPayload(lights: [patch]))
        let (data, resp) = try await Self.session.data(for: req)
        try check(resp)
        return (try? JSONDecoder().decode(LightsPayload.self, from: data))?.lights.first
    }

    @discardableResult
    func send(_ state: LightState) async throws -> LightState? {
        try await send(LightPatch(on: state.on, brightness: state.brightness, temperature: state.temperature))
    }

    private func check(_ resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KeyLightError.badResponse(http.statusCode)
        }
    }
}

enum ColorTemp {
    static let kelvinRange: ClosedRange<Double> = 2900...7000
    static func toKelvin(_ api: Int) -> Int { Int((1_000_000.0 / Double(max(api, 1)) / 50).rounded()) * 50 }
    static func toAPI(kelvin: Double) -> Int { min(344, max(143, Int((1_000_000.0 / kelvin).rounded()))) }
}
