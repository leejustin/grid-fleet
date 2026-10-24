import Foundation
import Observation
import UIKit

/// A value attached to an analytics event.
enum AnalyticsValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

extension AnalyticsValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .double(value) }
}

/// Opt-in, anonymous usage events sent to PostHog.
///
/// Nothing is collected unless the build has a PostHog project key (`PostHogAPIKey` in Info.plist) and the
/// player has said yes. Events carry a random install ID, never a name, Game Center ID or iCloud identity,
/// and are sent with `$process_person_profile: false` so PostHog keeps no person profile.
@MainActor
@Observable
final class Analytics {
    static let shared = Analytics()

    private struct Event: Encodable {
        let event: String
        let properties: [String: AnalyticsValue]
        let timestamp: String
    }

    private struct Batch: Encodable {
        let api_key: String
        let batch: [Event]
    }

    /// Whether this build has a PostHog key. Without one, analytics doesn't exist.
    let isConfigured: Bool
    private(set) var optedIn: Bool
    /// Whether the player has been asked.
    private(set) var hasAnswered: Bool

    private let apiKey: String
    private let endpoint: URL?
    private var installID: String
    private var queue: [Event] = []
    private var flushTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let timestamp = ISO8601DateFormatter()

    /// Set from the current fold posture so every event carries it.
    var posture = "unknown"

    private init() {
        var key = (Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        var host = (Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "https://us.i.posthog.com"
        #if DEBUG
        // Launch arguments can point a debug build at a test project or a local mock server.
        if let override = UserDefaults.standard.string(forKey: "PostHogAPIKeyOverride") { key = override }
        if let override = UserDefaults.standard.string(forKey: "PostHogHostOverride") { host = override }
        #endif
        apiKey = key
        endpoint = URL(string: host)?.appending(path: "batch/")
        isConfigured = !key.isEmpty && endpoint != nil
        optedIn = defaults.bool(forKey: "analyticsOptIn")
        hasAnswered = defaults.object(forKey: "analyticsOptIn") != nil
        installID = defaults.string(forKey: "analyticsInstallID") ?? UUID().uuidString
        defaults.set(installID, forKey: "analyticsInstallID")
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    var isActive: Bool { isConfigured && optedIn }

    func setOptedIn(_ value: Bool) {
        optedIn = value
        hasAnswered = true
        defaults.set(value, forKey: "analyticsOptIn")
        if value {
            capture("analytics_opted_in")
        } else {
            queue.removeAll()
            // A fresh ID if they ever opt back in, so old and new sessions can't be joined.
            installID = UUID().uuidString
            defaults.set(installID, forKey: "analyticsInstallID")
        }
    }

    func capture(_ name: String, _ properties: [String: AnalyticsValue] = [:]) {
        guard isActive else { return }
        var props = properties
        props["distinct_id"] = .string(installID)
        props["$process_person_profile"] = false
        props["$lib"] = "grid-fleet-ios"
        props["app_version"] = .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        props["os_version"] = .string(UIDevice.current.systemVersion)
        props["device"] = .string(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        props["posture"] = .string(posture)
        queue.append(Event(event: name, properties: props, timestamp: timestamp.string(from: .now)))
        if queue.count >= 20 {
            flush()
        } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.flushTask = nil
                self?.flush()
            }
        }
    }

    /// Sends queued events. Failed sends go back on the queue (up to a limit) for next time.
    func flush() {
        guard isActive, !queue.isEmpty, let endpoint else { return }
        let events = queue
        queue.removeAll()
        guard let body = try? JSONEncoder().encode(Batch(api_key: apiKey, batch: events)) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        Task {
            let ok: Bool
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            } catch {
                ok = false
            }
            if !ok, self.isActive {
                self.queue = Array((events + self.queue).suffix(200))
            }
        }
    }
}
