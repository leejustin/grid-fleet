import CryptoKit
import Foundation
import MetricKit

/// Crash, hang and resource reports from MetricKit.
///
/// iOS delivers these about once a day, from the previous day's use. They also show up in Xcode's Organizer
/// for TestFlight and App Store builds. If the player opted in to usage sharing, a short summary goes to
/// PostHog as well: the kind of problem, the app version, and a fingerprint of the crashing stack so
/// repeats can be grouped. No user data is involved. The latest raw payload is kept in Caches for debugging.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    @MainActor
    func start() {
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var events: [(String, [String: AnalyticsValue])] = []
        for payload in payloads {
            Self.keep(payload.jsonRepresentation(), named: "last-diagnostics.json")
            for crash in payload.crashDiagnostics ?? [] {
                events.append(("diagnostic_crash", [
                    "app_version": .string(crash.metaData.applicationBuildVersion),
                    "exception_type": .int(crash.exceptionType?.intValue ?? -1),
                    "signal": .int(crash.signal?.intValue ?? -1),
                    "reason": .string(String((crash.terminationReason ?? "").prefix(120))),
                    "signature": .string(Self.signature(of: crash.callStackTree)),
                ]))
            }
            for hang in payload.hangDiagnostics ?? [] {
                events.append(("diagnostic_hang", [
                    "app_version": .string(hang.metaData.applicationBuildVersion),
                    "seconds": .double(hang.hangDuration.converted(to: .seconds).value),
                    "signature": .string(Self.signature(of: hang.callStackTree)),
                ]))
            }
            for exception in payload.cpuExceptionDiagnostics ?? [] {
                events.append(("diagnostic_cpu", [
                    "app_version": .string(exception.metaData.applicationBuildVersion),
                    "cpu_seconds": .double(exception.totalCPUTime.converted(to: .seconds).value),
                    "signature": .string(Self.signature(of: exception.callStackTree)),
                ]))
            }
            for exception in payload.diskWriteExceptionDiagnostics ?? [] {
                events.append(("diagnostic_disk_writes", [
                    "app_version": .string(exception.metaData.applicationBuildVersion),
                    "megabytes": .double(exception.totalWritesCaused.converted(to: .megabytes).value),
                ]))
            }
        }
        let summary = events
        Task { @MainActor in
            for (name, properties) in summary { Analytics.shared.capture(name, properties) }
            Analytics.shared.flush()
        }
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        var events: [[String: AnalyticsValue]] = []
        for payload in payloads {
            Self.keep(payload.jsonRepresentation(), named: "last-metrics.json")
            var properties: [String: AnalyticsValue] = ["app_version": .string(payload.latestApplicationVersion)]
            if let memory = payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value {
                properties["peak_memory_mb"] = .double(memory.rounded())
            }
            if let cpu = payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value {
                properties["cpu_seconds"] = .double(cpu.rounded())
            }
            if let foreground = payload.applicationTimeMetrics?.cumulativeForegroundTime.converted(to: .minutes).value {
                properties["foreground_minutes"] = .double(foreground.rounded())
            }
            events.append(properties)
        }
        let summary = events
        Task { @MainActor in
            for properties in summary { Analytics.shared.capture("daily_metrics", properties) }
        }
    }

    /// A short, stable fingerprint of the top of a call stack: the same crash gives the same signature.
    nonisolated private static func signature(of tree: MXCallStackTree) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: tree.jsonRepresentation()) as? [String: Any],
              let stacks = json["callStacks"] as? [[String: Any]] else { return "unknown" }
        // Prefer the thread that crashed; otherwise the first one.
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var frames: [String] = []
        var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
        while let current = frame, frames.count < 6 {
            frames.append("\(current["binaryName"] ?? "?")+\(current["offsetIntoBinaryTextSegment"] ?? "?")")
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        let digest = SHA256.hash(data: Data(frames.joined(separator: "|").utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func keep(_ data: Data, named name: String) {
        try? data.write(to: URL.cachesDirectory.appending(path: name), options: .atomic)
    }
}
