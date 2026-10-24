import Foundation
import Observation

/// The game on screen, if any.
enum ActiveGame: Identifiable {
    case local(LocalGame)
    case online(OnlineGame)

    var id: ObjectIdentifier {
        switch self {
        case .local(let game): ObjectIdentifier(game)
        case .online(let game): ObjectIdentifier(game)
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var activeGame: ActiveGame?
    /// A room code from a gridfleet://room/CODE link, waiting to be joined.
    var pendingRoomCode: String?
    var showsShipyard = false
    var shipyardFocus: Unlock?
    #if DEBUG
    var demoNewGame = false
    #endif

    func handle(_ url: URL) {
        guard url.scheme == "gridfleet" else { return }
        // gridfleet://room/K7Q2XP
        if url.host() == "room", let code = url.pathComponents.dropFirst().first {
            pendingRoomCode = RoomTransport.normalize(code)
        }
    }

    func openShipyard(focus: Unlock? = nil) {
        Analytics.shared.capture("shipyard_opened", ["focus": .string(focus?.rawValue ?? "none")])
        shipyardFocus = focus
        showsShipyard = true
    }
}
