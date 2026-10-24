import Foundation
import GridFleetCore
import Observation

/// Player preferences, stored in UserDefaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var playerName: String { didSet { defaults.set(playerName, forKey: "playerName") } }
    var hapticsEnabled: Bool { didSet { Analytics.shared.capture("setting_changed", ["setting": "hapticsEnabled", "value": .bool(hapticsEnabled)]); defaults.set(hapticsEnabled, forKey: "haptics"); Haptics.enabled = hapticsEnabled } }
    var soundEnabled: Bool { didSet { Analytics.shared.capture("setting_changed", ["setting": "soundEnabled", "value": .bool(soundEnabled)]); defaults.set(soundEnabled, forKey: "sound"); SoundBoard.shared.enabled = soundEnabled } }
    /// Rival admirals talk during games against the computer.
    var rivalChatter: Bool { didSet { Analytics.shared.capture("setting_changed", ["setting": "rivalChatter", "value": .bool(rivalChatter)]); defaults.set(rivalChatter, forKey: "rivalChatter") } }
    /// Fire on the first tap instead of aim-then-confirm.
    var oneTapFire: Bool { didSet { Analytics.shared.capture("setting_changed", ["setting": "oneTapFire", "value": .bool(oneTapFire)]); defaults.set(oneTapFire, forKey: "oneTapFire") } }
    /// On a single screen, swing to your fleet while the enemy fires.
    var followAction: Bool { didSet { Analytics.shared.capture("setting_changed", ["setting": "followAction", "value": .bool(followAction)]); defaults.set(followAction, forKey: "followAction") } }
    var themeID: Theme.ID { didSet { Analytics.shared.capture("setting_changed", ["setting": "themeID", "value": .string(themeID.rawValue)]); defaults.set(themeID.rawValue, forKey: "theme") } }
    var skinID: ShipSkin.ID { didSet { Analytics.shared.capture("setting_changed", ["setting": "skinID", "value": .string(skinID.rawValue)]); defaults.set(skinID.rawValue, forKey: "skin") } }
    var blastStyle: BlastStyle { didSet { Analytics.shared.capture("setting_changed", ["setting": "blastStyle", "value": .string(blastStyle.rawValue)]); defaults.set(blastStyle.rawValue, forKey: "blast") } }
    /// Pegs when the phone is half-folded, unless the player picks one look for everything.
    var boardStylePreference: BoardStylePreference { didSet { defaults.set(boardStylePreference.rawValue, forKey: "boardStyle"); Analytics.shared.capture("setting_changed", ["setting": "boardStyle", "value": .string(boardStylePreference.rawValue)]) } }
    var lastRules: GameRules { didSet { defaults.set(try? JSONEncoder().encode(lastRules), forKey: "lastRules") } }
    var lastDifficulty: AIDifficulty { didSet { defaults.set(lastDifficulty.rawValue, forKey: "lastDifficulty") } }
    var hasSeenTutorial: Bool { didSet { defaults.set(hasSeenTutorial, forKey: "hasSeenTutorial") } }

    /// A stable anonymous id for room-code games.
    let captainID: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        playerName = defaults.string(forKey: "playerName") ?? "Captain"
        hapticsEnabled = defaults.flag("haptics", default: true)
        soundEnabled = defaults.flag("sound", default: true)
        rivalChatter = defaults.flag("rivalChatter", default: true)
        oneTapFire = defaults.bool(forKey: "oneTapFire")
        followAction = defaults.flag("followAction", default: true)
        themeID = defaults.string(forKey: "theme").flatMap(Theme.ID.init(rawValue:)) ?? .nightWatch
        skinID = defaults.string(forKey: "skin").flatMap(ShipSkin.ID.init(rawValue:)) ?? .steel
        blastStyle = defaults.string(forKey: "blast").flatMap(BlastStyle.init(rawValue:)) ?? .fireball
        boardStylePreference = defaults.string(forKey: "boardStyle").flatMap(BoardStylePreference.init(rawValue:)) ?? .automatic
        lastRules = defaults.data(forKey: "lastRules").flatMap { try? JSONDecoder().decode(GameRules.self, from: $0) } ?? .classic
        lastDifficulty = defaults.string(forKey: "lastDifficulty").flatMap(AIDifficulty.init(rawValue:)) ?? .medium
        hasSeenTutorial = defaults.bool(forKey: "hasSeenTutorial")
        if let id = defaults.string(forKey: "captainID") {
            captainID = id
        } else {
            captainID = UUID().uuidString
            defaults.set(captainID, forKey: "captainID")
        }
        Haptics.enabled = hapticsEnabled
        SoundBoard.shared.enabled = soundEnabled
    }
}

enum BoardStylePreference: String, CaseIterable, Identifiable {
    case automatic
    case pegboard
    case water

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Pegs when folded"
        case .pegboard: "Always pegs"
        case .water: "Always water"
        }
    }

    func resolve(spansFold: Bool) -> BoardStyle {
        switch self {
        case .automatic: spansFold ? .pegboard : .water
        case .pegboard: .pegboard
        case .water: .water
        }
    }
}

extension UserDefaults {
    /// A Boolean that also understands "YES"/"NO" from launch arguments, with a default when unset.
    func flag(_ key: String, default value: Bool) -> Bool {
        object(forKey: key) == nil ? value : bool(forKey: key)
    }
}
