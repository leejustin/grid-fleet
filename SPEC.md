# Grid Fleet — spec

Pitch: the classic hidden-fleet game, laid out like the folding board game. Half-fold the Duo and the enemy grid stands on the top half while your fleet lies on the bottom half. Play online against friends on any iPhone or iPad, with the Duo as the best way to play. Many Sea Battle apps exist and none support the Duo. A Surface Duo web demo with this layout got press. Naming: "Battleship" is a Hasbro trademark. The rules are free to use, but not the name, logo or board art.

## Platform rules (all apps)
- Build with Xcode 27.1 and the iOS 27.1 SDK, or the app shows black borders on the inner screen.
- Draw only on the inner screen while open. Third-party apps get no general way to use the outer screen while open, and no API says which panel a window is on.
- Detect half-fold posture and the hinge with Apple's posture and trait APIs. Folding is a trait change, so the app keeps its state.
- It must run well on regular iPhones too.
- From April 2027 every submission needs iPhone Duo screenshots.
- Shared stack: Swift and SwiftUI, support iOS 27+, SwiftData plus iCloud, StoreKit 2, GameKit. One shared fold-posture helper is reused across all three apps (Carriage, Grid Fleet, Firstlight).

## Rules (MVP)
- A 10 × 10 grid per player.
- A fleet of 5 ships with lengths 5, 4, 3, 3 and 2, placed horizontally or vertically. Optional rule: ships can't touch diagonally.
- Players take turns firing one shot; hit, miss or sunk shows on both grids.
- The first player to sink the whole enemy fleet wins.
- Later variants: salvo (one shot per ship still afloat), special weapons, 8 × 8 quick games.

## Layout by posture
- Half-folded (hero mode): enemy grid on top (tap to fire), your fleet with incoming hits on the bottom.
- Fully open and flat: one grid on each half.
- Closed or regular iPhone: the enemy grid full screen, with a swipe or tab to see your fleet.
- iPad: both grids side by side.

## Game modes
- MVP: vs computer (easy, medium and hard AI; this also lets App Review test with one device); online with friends through a Game Center turn-based match (invite Game Center friends or send a link in Messages; games can last minutes or days); quick match through Game Center matchmaking.
- v1.1: pass and play (closing the phone or tapping "Hide" covers your fleet); room code (a 6-character code, needing CloudKit public DB or Firebase).
- Later: live real-time match with a turn timer.

## Fold moments
Opening the phone from closed to half-fold starts your turn with a "periscope up" animation. Hits on your fleet shake the bottom half with a heavy haptic. In pass and play, closing the phone instantly hides your fleet.

## Technical notes
- Use SwiftUI with Canvas (enough for simple grids and faster to build than SpriteKit).
- Online play: GameKit turn-based matches store state on Apple's servers, so there's no backend for the MVP.
- Cheating: both phones receive the match data. For the MVP, store each fleet as a hash (fleet + random salt) and reveal it at game end so either side can verify. Add a server referee only if the game grows.
- Turn-based Game Center sends "your turn" notifications.

## Monetization
Free with vs computer and online play. A $2.99 unlock adds hard AI, salvo mode and extra boards. Cosmetic packs at $0.99–$1.99 (ship skins, ocean themes, explosions); nothing pay-to-win. No ads during matches.

## Risks and open questions
- Empty matchmaking at launch: answer with strong AI, friend invites and full cross-play with regular iPhones.
- It's the biggest build of the three.
- Open question: Android later? Game Center is Apple-only.

## Submission checklist
Built with the iOS 27.1 SDK; tested in all postures in Device Hub; works on a regular iPhone; Duo and regular screenshots; original name, icon and art (no Hasbro assets); App Review notes explain the fold features; privacy details filled in; in-app purchases tested in the sandbox.
