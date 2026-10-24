# Grid Fleet

A folding two-grid sea battle game for iPhone Duo. Half-fold the phone and the enemy grid stands on the top half while your fleet lies on the bottom half, like the folding board game. It also plays on any iPhone or iPad. See [SPEC.md](SPEC.md).

## What's here

| Path | What it is |
| --- | --- |
| `Packages/GridFleetCore` | The game, with no UI: boards, fleets, rules (Classic, Skirmish, Open Ocean, salvo, special weapons, the no-touching rule), the three computer opponents, sealed fleets with end-of-game audits, and the match ledger used for online play. |
| `Packages/FoldKit` | The fold-posture helper shared with Carriage and Firstlight: `FoldState`, `.foldAware()`, `FoldSplit`, and a developer posture simulator. |
| `GridFleet/` | The SwiftUI app. |
| `Config/` | Info.plist, entitlements and the StoreKit test configuration. |

The Xcode project uses synchronized folders, so a new file in `GridFleet/` is part of the app with no project edits.

## Build and test

Open `GridFleet.xcodeproj` and run the `GridFleet` scheme. The scheme uses `Config/GridFleet.storekit`, so purchases work in the simulator. Account setup (signing, App Store Connect, CloudKit, PostHog, TestFlight) is in [SETUP.md](SETUP.md).

UI tests (`GridFleetUITests`) tap through real flows: deploy and fire against the computer, the double-tap-to-fire guard, placing ships from the dock, dragging a ship onto the grid, and the pass-and-play cover. Run them with the scheme's Test action, or:

```bash
xcodebuild test -project GridFleet.xcodeproj -scheme GridFleet -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:GridFleetUITests
```

```bash
cd Packages/GridFleetCore && swift test
```

```bash
cd Packages/FoldKit && swift test
```

## The idea

Grid Fleet recreates the folding board game. Two friends sit across a table, each with a half-folded iPhone Duo held like the plastic case. The enemy grid stands up on the lid, your fleet lies in the tray, and pegs click in: white for a miss, red for a hit. Everything else (online play, the computer, regular iPhones and iPad) supports that one moment.

## Modes

- **Across the table (the main mode).** Two phones in the same room find each other with Bonjour over the local network or peer-to-peer Wi-Fi (Network framework). No account or internet is needed. One player taps the other's name; the inviter's rules apply. When the phones connect, both show the two captains facing each other and a coin flip for who fires first. The inviter's phone flips it and sends the result with the invite, and each rematch flips again. Code: `Services/NearbyLink.swift`, `Screens/ArrivalOverlay.swift`.
  - **Dropped connection:** if a phone locks or wanders off mid-game, the inviter keeps reaching out and the game resumes.
  - **App closed mid-game:** Home offers "Rejoin …". It reconnects to the same game and merges whatever the other phone played meanwhile.
  - **Rematch:** one tap after a game, over the same connection. The other phone gets a Play / Not now prompt.
  - **Local Network turned off:** the lobby explains and links to Settings.
- **First battle.** New players see "Your first battle" on the home screen: a game against Ensign Pip, who explains each step in a tip card as it comes up (placing ships, aiming, firing, reading pegs, the enemy's reply). The part of the screen being explained pulses until it's used. Players can skip the tips with the card's close button or the battle menu, or long-press the card and pick "I know how to play". Code: `Game/Coach.swift`.
- **Vs Computer (practice).** Ensign (random, with half-hearted follow-ups), Commander (checkerboard hunt, then targeting) and Admiral (probability density over every legal placement, plus sensible use of special weapons). On average they sink a fleet in about 75, 52 and 45 shots.
- **Online (Game Center turn-based).** Invite friends (or send a Messages link) through Game Center's matchmaker, or quick-match. Matchmaking only pairs players who chose the same rules.
- **Live (Game Center real-time).** Both players are in the app at once, with a 30-second turn timer.
- **Pass & Play.** Fleets stay covered between turns. Closing the phone, leaving the app or tapping Hide covers them at once, and a press-and-hold reveals them again.
- **Room Code.** A six-character code shared through CloudKit's public database. It needs iCloud but not Game Center.

All online modes share `MatchLedger`. Each fleet is published only as a salted SHA-256 hash. Shots go into the ledger unresolved, and the defender's device answers them, since only that device knows the fleet. At the end both fleets are revealed, and each side checks the other's against its seal and against every reported hit, miss and sinking.

## Design system

`GridFleet/Design/Typography.swift` and `Components.swift` define the look. Keep new screens inside it:
- **Type:** system text styles (`.headline`, `.body`, `.footnote` and so on) in sentence case, so Dynamic Type works. The expanded heavy width is for the "Grid Fleet" wordmark only.
- **Spacing:** the `Space` scale (4, 8, 12, 16, 20, 24, 32, 48) and two corner radii (`Radius.small` 12, `Radius.card` 20).
- **Surfaces:** flat `.surface()` cards with a hairline edge. Liquid Glass only on floating controls: the battle menu, timer and close buttons.
- **Accent color:** only for the primary action, your turn, and selection. No glows on UI chrome; the light and fire live on the board.
- **Lists:** `ListRow` / `RowDivider` / `ContentSection` for anything list-like. Pushed screens use native large titles (`oceanNavigation`).

## Rivals, sound and medals

- **Rival admirals.** Each computer level has a character: Ensign Pip (eager, nervous), Commander Gale (dry, clipped) and Admiral Thorn (theatrical villain). Each is shown by a real maritime signal flag instead of a face: Pip flies Papa, Gale flies Golf, and Thorn flies Zulu, the battle flag Admiral Togo hoisted at Tsushima. The flag ripples while its rival talks and fades when they lose. Rivals face off with you before the battle, react to hits, sinks, streaks and last ships, and get the last word on the result screen. Players can turn off Rival chatter in Settings. The lines are in `GridFleet/Game/Rivals.swift`.
- **Sound.** Every effect is synthesized at launch (`SoundBoard`): shell whistle, splash, explosion, sinking groan, sonar ping, torpedo, radio chirp and fanfares. There are no audio files. Sound mixes with the player's music and respects the silent switch. Debug builds have a sound lab (Settings › Developer › Sound and haptics lab) for playing each effect and haptic on a real device and setting each sound's level. Levels are saved on the device and used everywhere that sound plays, so tuned values can be copied into `SoundBoard` before release.
- **Streaks and medals.** Consecutive hits are called out ("Hit ×3 · Hat trick"). Nine medals (bronze, silver, gold) are awarded at the end of a game, stored in iCloud and shown in the logbook's medal case. The rules are in `GridFleetCore/Medals.swift` and have tests.
- **Resume.** Games against the computer and pass-and-play games save after every turn, so a closed app shows "Resume battle" on the home screen.

## Usage analytics (PostHog, opt-in)

`GridFleet/Services/Analytics.swift` is a small client for PostHog's `/batch/` API, with no SDK dependency.

- **Off until set up:** it does nothing until `PostHogAPIKey` in `Config/Info.plist` is filled in. Project keys (`phc_…`) are meant to ship in apps. For an EU project, set `PostHogHost` to `https://eu.i.posthog.com`.
- **Opt-in:** after their first finished game, players are asked once whether to share. They can change it any time in Settings › Privacy.
- **Anonymous:** events carry a random install ID and `$process_person_profile: false`. No names, Game Center IDs or iCloud identities are sent. Opting out drops anything not yet sent and resets the ID.
- **Events:**
  - `app_opened`, `posture_changed`
  - `tutorial_closed` (which page, finished or not)
  - `coach_started`, `coach_step` (which tip, seconds on it), `coach_finished`, `coach_skipped` (at which tip)
  - `nearby_coin_flip` (whether this phone fires first)
  - `game_started`, `deploy_finished` (seconds, shuffles, drags, failed drops, rotations)
  - `game_finished` and `game_abandoned`, with mis-taps, aim changes, median aim time, accuracy, turns, result and medals
  - `game_resumed`, `rival_intro_skipped`, `fleet_hidden`
  - `shipyard_opened`, `purchase_started`, `purchase_completed`, `purchase_cancelled`
  - `matchmaking_opened`, `room_created`, `room_joined`, `online_error`
  - `setting_changed`
- **App Store privacy label:** with a key set, declare "Product Interaction" usage data, not linked to identity and not used for tracking.
- **Testing locally:** debug builds accept `-PostHogAPIKeyOverride <key> -PostHogHostOverride <url>` to point at a test project or a local mock.

## Battery

Boards draw in two layers. A static layer (plate, grid, labels, settled ships) redraws only when the board changes. A live layer redraws only while something moves: 60 frames per second until the last effect ends, 30 while aiming, a slow tick for ambient shimmer, and nothing at all when idle (`BoardSchedule` in `Design/MotionBudget.swift`). Ambient motion stops with Reduce Motion or Low Power Mode. Gameplay screens hold the ocean backdrop still. On the simulator, an idle battle dropped from about 10–12% CPU to 5–8%.

## Diagnostics and privacy

- **Crash and hang reports:** MetricKit's daily reports go to PostHog as `diagnostic_crash`, `diagnostic_hang`, `diagnostic_cpu`, `diagnostic_disk_writes` and `daily_metrics`, for opted-in players only. Each carries a stack fingerprint so repeats can be grouped. TestFlight and App Store crashes also appear in Xcode's Organizer.
- **Privacy manifest:** `GridFleet/PrivacyInfo.xcprivacy` declares the UserDefaults API reason and the data types collected: product interaction, crash, performance and gameplay content. None of it is linked to identity, and none is used for tracking.

## Pegboard

When the phone is half-folded, boards switch to a molded plastic pegboard (`Board/PegboardPainter.swift`). Shots arrive as falling pegs that click into their holes, and your ships are plastic pieces with a peg hole per section. Settings › Board can choose "Pegs when folded" (the default), "Always pegs" or "Always water". The palette and shapes are our own, not any real product's.

The hinge angle lights the pegboard (`Board/LidLight.swift`): the standing half casts a shadow across the top of your fleet and the crease darkens. Both deepen as the phone closes and fade out as it opens flat. The angle comes from `onHingeChange`, rounded to 2° so opening the phone doesn't redraw constantly. In the simulator, `-FoldKit.simulatedAngle 80` sets it while simulating a half fold.

## Keyboard and pointer

With a hardware keyboard, the arrow keys move a cursor on the enemy board (with one shot to place, the aim follows it). Space marks or unmarks a target, Return fires, 1 to 4 pick a weapon when special weapons are on, and T turns the torpedo. With a pointer, the cell under it is outlined.

## Layout by posture

- **Half-folded or flat:** enemy grid above the hinge, your fleet below it (`FoldSplit`).
- **iPad portrait:** the same stacked layout.
- **Landscape, including iPad landscape:** side by side.
- **Regular iPhone or closed:** the enemy grid fills the screen, with a mini-map of your fleet under it. Swipe or use the tab to see your fleet. "Follow the action" swings over while the enemy fires.

Fold moments: opening the phone onto your turn raises the periscope, hits on your fleet shake it with a heavy haptic, and in pass and play closing the phone hides your fleet.

## Before shipping

1. **Xcode 27.1 / iOS 27.1 SDK.** Required, or the app shows black borders on the inner screen. FoldKit reads the real hinge with SwiftUI's `onHingeChange` (iOS 27.1+): partially open is half-folded, and fully open is flat. The API doesn't report where the hinge is, so FoldKit places it across the middle of the window's long side. The developer posture simulator (Settings › Developer, or `-FoldKit.simulatedPosture halfFolded`) still overrides it for testing on other devices.
2. **Signing:** set a development team. The bundle ID is `com.leejustin.gridfleet`.
3. **Game Center:** enable it for the app in App Store Connect.
4. **iCloud:** create the container `iCloud.com.leejustin.gridfleet`. For room codes, give the `Room` record type write access for authenticated users in the CloudKit Dashboard. By default only a record's creator can change it, so a guest couldn't join.
5. **In-app purchases:** create these non-consumables, matching `Config/GridFleet.storekit`:
   - `com.leejustin.gridfleet.admiral` ($2.99): Admiral AI, salvo, Skirmish and Open Ocean boards, special weapons
   - `com.leejustin.gridfleet.oceans` ($1.99)
   - `com.leejustin.gridfleet.hulls` ($0.99)
   - `com.leejustin.gridfleet.blasts` ($0.99)

## Edge cases to know about

- **Online winner's reveal.** In turn-based play, the winner reveals their fleet the next time they open the match. Until then it stays open on Game Center and the loser can't check the winner's fleet yet.
- **Turn timeouts and quits.** If a turn-based player quits or lets the 7-day turn clock run out, they forfeit. The other player wins when they next open the match.
- **Live matches.** Leaving the app drops the Game Center connection, which counts as a forfeit. The first player repeats their opening message until the second player answers, so a slow start doesn't split the game.
- **Room codes.** These need the CloudKit `Room` write permission described above. Each phone checks for changes every 3 seconds while the room is open. Old rooms are never deleted, so add a cleanup job if usage grows.
- **Paid rules online.** An invited friend can play a salvo or special-weapons match without owning the Admiral's Commission. That's intentional, so friends can always play together.
- **Two devices, one match.** The sealed fleet syncs through iCloud. If the second device opens the match before sync catches up, the app says the fleet was deployed on another device.

## Screenshots and visual checks (debug builds)

`-GFDemo nearbyHost` and `-GFDemo nearbyGuest` on two simulators play a whole across-the-table game against each other: discovery, invite, deploy, every shot, and the end-of-game check. Add `-playerName Ava` to set the names.

`-GFDemo <scene>` jumps to a screen. Scenes: `intro`, `deploy`, `battle`, `salvo`, `specials`, `result`, `handoff`, `logbook`, `shipyard`, `online`, `room`, `newgame`, `settings`, `soundlab`, `rivals` (every portrait in every mood), `coachDeploy` and `coach` (the guided first game; add `-GFDemoTurns 1` to see it after the first shot), and `home` (add `-GFDemoSeen NO` to show the first-battle card). Add `-GFDemoRival easy|medium|hard` to choose the opponent. Mix in any setting, for example `-theme abyss` or `-FoldKit.simulatedPosture halfFolded`:

```bash
xcrun simctl launch booted com.leejustin.gridfleet -GFDemo battle -FoldKit.simulatedPosture halfFolded
```

## Naming

"Battleship" is a Hasbro trademark. Grid Fleet uses the public-domain rules with its own name, icon and art. The ships are drawn in code. The app icon is a layered Liquid Glass icon (`GridFleet/AppIcon.icon`), so the system makes the dark and tinted versions. Its layers come from `Marketing/Icon/render-icon.swift`; open the `.icon` in Icon Composer to adjust glass, shadows or translucency.
