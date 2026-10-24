import UIKit

/// Haptics for game moments. Silent when the player turns them off.
@MainActor
enum Haptics {
    static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    static func aim() { guard enabled else { return }; select.selectionChanged() }
    static func fire() { guard enabled else { return }; rigid.impactOccurred(intensity: 0.8) }
    static func splash() { guard enabled else { return }; soft.impactOccurred(intensity: 0.5) }
    static func hit() { guard enabled else { return }; medium.impactOccurred(intensity: 1) }
    /// A shell landing on your own fleet.
    static func takeHit() { guard enabled else { return }; heavy.impactOccurred(intensity: 1) }

    static func sunk() {
        guard enabled else { return }
        heavy.impactOccurred(intensity: 1)
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            heavy.impactOccurred(intensity: 0.7)
            try? await Task.sleep(for: .milliseconds(120))
            medium.impactOccurred(intensity: 0.5)
        }
    }

    static func victory() {
        SoundBoard.shared.play(.fanfare)
        guard enabled else { return }
        notify.notificationOccurred(.success)
    }

    static func defeat() {
        SoundBoard.shared.play(.lament)
        guard enabled else { return }
        notify.notificationOccurred(.error)
    }
    static func warning() { guard enabled else { return }; notify.notificationOccurred(.warning) }
    static func tap() { guard enabled else { return }; light.impactOccurred(intensity: 0.6) }

    /// A rising set of taps for the periscope.
    static func periscope() {
        SoundBoard.shared.play(.periscope, volume: 0.9)
        guard enabled else { return }
        Task {
            for i in 0..<4 {
                soft.impactOccurred(intensity: 0.3 + Double(i) * 0.15)
                try? await Task.sleep(for: .milliseconds(90))
            }
            rigid.impactOccurred(intensity: 0.9)
        }
    }
}
