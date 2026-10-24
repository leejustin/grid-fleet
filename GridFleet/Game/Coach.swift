import Foundation
import GridFleetCore
import Observation

/// Walks a new captain through a first game against Ensign Pip, one tip at a time. Each tip shows in a card
/// from Pip, and the part of the screen it's about is highlighted until the player uses it.
@MainActor
@Observable
final class Coach {
    enum Step: String, Comparable {
        case deploy, aim, fire, result, goal, done

        private var order: Int {
            switch self {
            case .deploy: 0
            case .aim: 1
            case .fire: 2
            case .result: 3
            case .goal: 4
            case .done: 5
            }
        }

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.order < rhs.order }
    }

    private(set) var step: Step = .deploy
    /// Called once, when the player finishes or skips the tips.
    var onFinish: (() -> Void)?

    var isActive: Bool { step != .done }

    @ObservationIgnored private var stepStartedAt = Date.now

    init() {
        Analytics.shared.capture("coach_started")
    }

    /// Follows along as the player plays, moving to the next tip once the current one has been acted on.
    func observe(_ session: BattleSession) {
        switch step {
        case .deploy:
            move(to: .aim)
        case .aim, .fire:
            if session.target.shotsFired > 0 {
                move(to: .result)
            } else if step == .aim, !session.aims.isEmpty {
                move(to: .fire)
            } else if step == .fire, session.aims.isEmpty {
                // They took their aim back.
                step = .aim
            }
        case .result:
            // Shown once the turn comes back, next to the player's first mark. Aiming again moves on.
            if session.status == .yourTurn, !session.aims.isEmpty || session.target.shotsFired > 1 { move(to: .goal) }
        case .goal:
            if session.target.shotsFired > 1 { move(to: .done) }
        case .done:
            break
        }
    }

    func skip() {
        guard isActive else { return }
        Analytics.shared.capture("coach_skipped", ["step": .string(step.rawValue)])
        step = .done
        onFinish?()
    }

    private func move(to next: Step) {
        guard step < next else { return }
        Analytics.shared.capture("coach_step", [
            "step": .string(step.rawValue),
            "seconds": .int(Int(Date.now.timeIntervalSince(stepStartedAt))),
        ])
        step = next
        stepStartedAt = .now
        if next == .done {
            Analytics.shared.capture("coach_finished")
            onFinish?()
        }
    }
}
