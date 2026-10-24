import Foundation
import Observation
import SwiftUI

/// Whether ambient animation (water shimmer, radar sweeps, idle flicker) is worth the battery.
/// Off with Reduce Motion or Low Power Mode. Game-critical animation, like shells landing, always plays.
@MainActor
@Observable
final class MotionBudget {
    static let shared = MotionBudget()

    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private init() {
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                MotionBudget.shared.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func allowsAmbient(reduceMotion: Bool) -> Bool {
        !reduceMotion && !lowPower
    }

}

/// Frames for a board: smooth until its last effect ends, gentler while aiming, a slow tick for ambient
/// motion, and none at all when nothing moves. Unlike a fixed interval, it winds itself down after effects
/// finish without the view having to be rebuilt.
struct BoardSchedule: TimelineSchedule {
    let liveUntil: Date
    let aiming: Bool
    /// Seconds between idle frames, or nil to stop when idle.
    let idleInterval: Double?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let lowFrequency = mode == .lowFrequency
        var date = startDate
        var finished = false
        return AnyIterator {
            guard !finished else { return nil }
            let current = date
            let step: Double?
            if current < liveUntil {
                step = lowFrequency ? 1 / 4 : 1 / 60
            } else if aiming {
                step = lowFrequency ? 1 : 1 / 30
            } else if let idleInterval {
                step = lowFrequency ? max(1, idleInterval) : idleInterval
            } else {
                step = nil
            }
            if let step {
                date = current.addingTimeInterval(step)
            } else {
                finished = true
            }
            return current
        }
    }
}
