import Foundation
import GridFleetCore
import SwiftUI

enum RivalMood: Equatable {
    case neutral, smug, angry, shocked, happy, defeated
}

/// A computer opponent with a flag and a voice.
struct Rival: Identifiable, Equatable {
    let id: AIDifficulty
    let rank: String
    let name: String
    let tagline: String
    /// Each rival flies the signal flag for their initial.
    let flag: SignalFlag

    var fullName: String { "\(rank) \(name)" }

    static let pip = Rival(id: .easy, rank: "Ensign", name: "Pip", tagline: "Eager, earnest, slightly seasick.", flag: .papa)
    static let gale = Rival(id: .medium, rank: "Commander", name: "Gale", tagline: "By the book. The book is very short.", flag: .golf)
    static let thorn = Rival(id: .hard, rank: "Admiral", name: "Thorn", tagline: "Has never lost. Says so often.", flag: .zulu)

    static func `for`(_ difficulty: AIDifficulty) -> Rival {
        switch difficulty {
        case .easy: .pip
        case .medium: .gale
        case .hard: .thorn
        }
    }
}

/// Something a rival says.
struct RivalLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let mood: RivalMood
}

/// Moments a rival might react to.
enum RivalMoment: CaseIterable {
    case opening
    case playerHit, playerMissed, playerSank, playerStreak
    case rivalHit, rivalMissed, rivalSank
    case rivalLastShip, playerLastShip
    case rivalWon, rivalLost, playerResigned

    /// How likely the rival is to speak, so they don't narrate every shot.
    var chance: Double {
        switch self {
        case .playerHit, .rivalHit: 0.5
        case .playerMissed, .rivalMissed: 0.28
        default: 1
        }
    }

    /// Lines that may interrupt the cooldown between remarks.
    var isMajor: Bool { chance == 1 }
}

/// Decides when a rival speaks and what they say.
struct RivalDirector {
    let rival: Rival
    private var lastSpoke = Date.distantPast
    private var recent: [String] = []

    init(rival: Rival) {
        self.rival = rival
    }

    /// A line for the moment, or nil if the rival keeps quiet. `%@` in a line becomes `subject`.
    mutating func line(for moment: RivalMoment, subject: String? = nil) -> RivalLine? {
        guard moment.isMajor || (Date.now.timeIntervalSince(lastSpoke) > 2.5 && Double.random(in: 0..<1) < moment.chance) else { return nil }
        let options = RivalScript.lines(for: rival.id, moment)
        let fresh = options.filter { !recent.contains($0.0) }
        guard let (template, mood) = (fresh.isEmpty ? options : fresh).randomElement() else { return nil }
        recent.append(template)
        if recent.count > 8 { recent.removeFirst() }
        lastSpoke = .now
        let text = template.replacingOccurrences(of: "%@", with: subject ?? "ship")
        return RivalLine(text: text, mood: mood)
    }
}

/// What each rival says. Original writing; keep it light.
enum RivalScript {
    static func lines(for rival: AIDifficulty, _ moment: RivalMoment) -> [(String, RivalMood)] {
        switch rival {
        case .easy: pip(moment)
        case .medium: gale(moment)
        case .hard: thorn(moment)
        }
    }

    private static func pip(_ moment: RivalMoment) -> [(String, RivalMood)] {
        switch moment {
        case .opening: [("Ensign Pip reporting! Um. Ready when you are!", .happy), ("First command! Please go easy. Or don't! Wait—", .shocked), ("I placed my ships with a ruler and everything.", .happy)]
        case .playerHit: [("Ow! I mean, the ship says ow.", .shocked), ("Was that on purpose?!", .shocked), ("Okay, okay, that one counts.", .neutral)]
        case .playerMissed: [("Water! Lots of it out there!", .happy), ("Phew. Phew phew phew.", .happy), ("Missed me! I think? Yes!", .happy)]
        case .playerSank: [("My %@! I'd only just named it!", .defeated), ("Glub glub. That's the sound it made.", .defeated), ("Can I get a do-over? No? Okay.", .defeated)]
        case .playerStreak: [("Stop being so good at this!", .angry), ("Is there a pause button on war?", .shocked)]
        case .rivalHit: [("I hit something! Did I? I did!", .happy), ("Beginner's luck counts!", .happy), ("Sorry! Not sorry! Sorry.", .smug)]
        case .rivalMissed: [("Aw. Splash.", .neutral), ("I was aiming for the water. Strategically.", .neutral), ("Recalculating! Badly!", .shocked)]
        case .rivalSank: [("I sank your whole %@! Mom's gonna hear about this.", .happy), ("That's going in my logbook. In pen.", .smug)]
        case .rivalLastShip: [("Last ship! Totally fine! Everything's fine!", .shocked), ("Little boat, you're my only friend now.", .defeated)]
        case .playerLastShip: [("One ship left? Should I feel bad? I feel bad.", .neutral), ("Almost there! Go me!", .happy)]
        case .rivalWon: [("I WON? I won! Can you sign my logbook?", .happy), ("Good game! Was it good for you? It was for me!", .happy)]
        case .rivalLost: [("Good game, Captain. I'll practice. So much practice.", .defeated), ("You sank everything. Respect. Ow, but respect.", .defeated)]
        case .playerResigned: [("Wait, you're giving up? On me?", .shocked)]
        }
    }

    private static func gale(_ moment: RivalMoment) -> [(String, RivalMood)] {
        switch moment {
        case .opening: [("Commander Gale. Let's keep this efficient.", .neutral), ("I've read your file. It was short.", .smug), ("Grid's live. Make your shots count.", .neutral)]
        case .playerHit: [("Noted.", .angry), ("Lucky. Don't make it a habit.", .angry), ("Damage within tolerances.", .neutral)]
        case .playerMissed: [("Open water. Again.", .smug), ("That was a fish. You've upset a fish.", .smug), ("Your gunner should be reviewed.", .smug)]
        case .playerSank: [("Losing the %@ was not in the plan.", .angry), ("Fine. I'll adjust.", .angry), ("That's going in the incident report.", .angry)]
        case .playerStreak: [("Somebody's been studying.", .shocked), ("All right. You have my attention.", .neutral)]
        case .rivalHit: [("Contact.", .smug), ("Right where the numbers said.", .smug), ("Bracketing your position.", .smug)]
        case .rivalMissed: [("Adjusting.", .neutral), ("Eliminating possibilities.", .neutral), ("A miss is still information.", .neutral)]
        case .rivalSank: [("Your %@ is off the board.", .smug), ("Efficient.", .smug)]
        case .rivalLastShip: [("One hull left. That's all I need.", .angry), ("Unconventional. Not over.", .angry)]
        case .playerLastShip: [("One ship. Shall we wrap this up?", .smug), ("Endgame. Try to keep up.", .smug)]
        case .rivalWon: [("Mission complete. Debrief at oh-six-hundred.", .happy), ("Efficient. Thank you for your time.", .smug)]
        case .rivalLost: [("Well played. I'll want a rematch.", .defeated), ("I'll be reviewing the tapes.", .defeated)]
        case .playerResigned: [("Retreat accepted. Wise.", .smug)]
        }
    }

    private static func thorn(_ moment: RivalMoment) -> [(String, RivalMood)] {
        switch moment {
        case .opening: [("Admiral Thorn. Your fleet will make a charming reef.", .smug), ("I've sunk better captains before breakfast.", .smug), ("Begin, little captain. I'll try not to yawn.", .smug)]
        case .playerHit: [("A scratch! A SCRATCH!", .angry), ("You dare?", .angry), ("Enjoy it. It won't happen twice.", .angry)]
        case .playerMissed: [("Ha! The sea mocks you.", .smug), ("Do you even own a chart?", .smug), ("Splendid. Do it again.", .smug)]
        case .playerSank: [("My %@! You'll pay for that in steel.", .angry), ("That was my favorite. Now I'm cross.", .angry), ("Insolent! INSOLENT!", .angry)]
        case .playerStreak: [("Impossible. Who trained you?", .shocked), ("Luck. It must be luck.", .shocked)]
        case .rivalHit: [("I felt that from here.", .smug), ("Found you.", .smug), ("There's nowhere to hide on my ocean.", .smug)]
        case .rivalMissed: [("Hm. A warning shot.", .neutral), ("The sea is wide. I am patient.", .neutral), ("I'm narrowing it down.", .smug)]
        case .rivalSank: [("Your %@ sleeps with the fishes now.", .happy), ("Another trophy for the mantelpiece.", .happy), ("Glorious.", .happy)]
        case .rivalLastShip: [("One ship is all an Admiral needs.", .angry), ("You think this is over? How adorable.", .angry)]
        case .playerLastShip: [("One ship left. How poetic.", .smug), ("Shall I have the band play for it?", .smug)]
        case .rivalWon: [("As foretold. Bow, captain.", .happy), ("Write home. Tell them of Thorn.", .happy)]
        case .rivalLost: [("Impossible! I demand a rematch!", .defeated), ("This isn't over. Thorn always returns.", .defeated)]
        case .playerResigned: [("Surrender accepted. Graciously. Smugly.", .smug)]
        }
    }
}
