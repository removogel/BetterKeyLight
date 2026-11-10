import Foundation

/// Zustand einer Leuchte laut Elgato-API (Port 9123, /elgato/lights).
struct LightState: Codable, Equatable {
    var on: Int            // 0 = aus, 1 = an
    var brightness: Int    // 3...100
    var temperature: Int   // 143...344 (≈ 7000 K ... 2900 K)
}

private struct LightsPayload: Codable {
    var numberOfLights: Int
    var lights: [LightState]
}

enum KeyLightError: LocalizedError {
    case noAddress, badResponse(Int), noLights

    var errorDescription: String? {
        switch self {
        case .noAddress: return "Keine IP-Adresse eingestellt"
        case .badResponse(let code): return "Ungültige Antwort (HTTP \(code))"
        case .noLights: return "Keine Leuchte gefunden"
        }
    }
}

struct KeyLightClient {
    var host: String
    var port: Int = 9123

    private var url: URL? {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { return nil }
        return URL(string: "http://\(h):\(port)/elgato/lights")
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }()

    func fetch() async throws -> LightState {
        guard let url else { throw KeyLightError.noAddress }
        let (data, resp) = try await Self.session.data(from: url)
        try check(resp)
        let payload = try JSONDecoder().decode(LightsPayload.self, from: data)
        guard let first = payload.lights.first else { throw KeyLightError.noLights }
        return first
    }

    @discardableResult
    func send(_ state: LightState) async throws -> LightState {
        guard let url else { throw KeyLightError.noAddress }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(LightsPayload(numberOfLights: 1, lights: [state]))
        let (data, resp) = try await Self.session.data(for: req)
        try check(resp)
        let payload = try? JSONDecoder().decode(LightsPayload.self, from: data)
        return payload?.lights.first ?? state
    }

    private func check(_ resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KeyLightError.badResponse(http.statusCode)
        }
    }
}

enum ColorTemp {
    static let kelvinRange: ClosedRange<Double> = 2900...7000
    static func toKelvin(_ api: Int) -> Int { Int((1_000_000.0 / Double(api) / 50).rounded()) * 50 }
    static func toAPI(kelvin: Double) -> Int { min(344, max(143, Int((1_000_000.0 / kelvin).rounded()))) }
}
