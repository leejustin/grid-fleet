# Grid Fleet setup checklist

These steps need your Apple and PostHog accounts. Everything else is in the repo. Do them in order; each takes a few minutes.

## 1. Signing (needed before the app installs on a real phone)

1. Open `GridFleet.xcodeproj` in Xcode 27.1.
2. Select the **GridFleet** target, open **Signing & Capabilities**, and choose your team. Leave "Automatically manage signing" on.
3. Keep the bundle ID `com.leejustin.gridfleet`, or change it everywhere it appears:
   - the target's Bundle Identifier
   - the iCloud container `iCloud.com.leejustin.gridfleet` (in `Config/GridFleet.entitlements` and `Persistence.cloudContainer`)
   - the product IDs in `Config/GridFleet.storekit` and `Unlock.productID`
4. Check that Xcode lists these capabilities (the entitlements file already asks for them):
   - Game Center
   - iCloud with CloudKit, container `iCloud.com.leejustin.gridfleet`
   - Push Notifications, used by CloudKit sync
   - Background Modes › Remote notifications
5. Do the same for the **GridFleetUITests** target if you'll run UI tests on a device.

## 2. App Store Connect

1. **Create the app** with the bundle ID above. Primary category: Games › Board. Secondary: Games › Strategy.
2. **Game Center:** turn it on for the app. No leaderboards are needed for 1.0.
3. **In-app purchases:** create four non-consumables, matching `Config/GridFleet.storekit`:

   | Product ID | Price | Name |
   | --- | --- | --- |
   | `com.leejustin.gridfleet.admiral` | $2.99 | Admiral's Commission |
   | `com.leejustin.gridfleet.oceans` | $1.99 | Ocean Themes |
   | `com.leejustin.gridfleet.hulls` | $0.99 | Hull Skins |
   | `com.leejustin.gridfleet.blasts` | $0.99 | Blast FX |

   Turn on Family Sharing for each. Each one needs a review screenshot of the Shipyard; see `Marketing/Screenshots`.
4. **Sandbox testers:** add two under Users and Access › Sandbox. Sign each into a different test device (Settings › Developer › Sandbox Account) to try purchases and to play yourself through Game Center.
5. **App Privacy:** answer to match `GridFleet/PrivacyInfo.xcprivacy`:
   - Data used to track you: none.
   - Data not linked to you:
     - Product Interaction (Analytics)
     - Crash Data (App Functionality)
     - Performance Data (App Functionality)
     - Gameplay Content (App Functionality)
6. **Age rating:** Infrequent/Mild Cartoon or Fantasy Violence (ships get sunk). No other content.
7. **Review notes:** paste `Marketing/AppReviewNotes.md`.

## 3. CloudKit (iCloud sync and room codes)

Open the [CloudKit Console](https://icloud.developer.apple.com/) and pick `iCloud.com.leejustin.gridfleet`.

1. **Create the schema in Development.** Run the app once on a device or simulator that's signed into iCloud, finish a game, and open a room code. That creates the record types.
2. **Room permissions:** in Schema › Security Roles, give **Authenticated** users **Create, Read, Write** on the `Room` record type. Without this, only the room's host can write, so guests can't join.
3. **Deploy to Production** under Schema › Deploy Schema Changes before any TestFlight or App Store build. Production builds use the production schema; if you skip this, iCloud sync and room codes fail silently for customers.
4. **Optional:** add a scheduled job or a small server task that deletes `Room` records older than 30 days. The app never deletes them.

## 4. PostHog (opt-in analytics)

1. Create a PostHog project. Use the EU region if your players are mostly in Europe.
2. Paste the project API key (it starts with `phc_`) into `Config/Info.plist` under `PostHogAPIKey`. For EU, set `PostHogHost` to `https://eu.i.posthog.com`.
3. Nothing is sent until a player says yes. They're asked after their first finished game, and can change it in Settings › Privacy.
4. To test without real users, run a debug build with `-PostHogAPIKeyOverride phc_… -PostHogHostOverride https://us.i.posthog.com`.
5. Useful insights to set up:
   - **Funnel:** `app_opened` → `game_started` → `deploy_finished` → `game_finished`
   - **Tutorial drop-off:** `tutorial_closed` broken down by `page`
   - **Fiddly aiming:** average `misfire_taps` and `aim_changes` from `game_finished`
   - **Across-the-table success:** `nearby_invite_sent` → `nearby_connected` → `game_finished` where `mode = nearby`
   - **Crashes:** `diagnostic_crash` grouped by `signature`

## 5. TestFlight

1. In Xcode, choose Product › Archive with the **GridFleet** scheme, then Distribute App › TestFlight & App Store.
2. Add yourself and a friend as internal testers.
3. Crashes and hangs from TestFlight builds appear in Xcode › Window › Organizer › Crashes. With analytics on, they also arrive in PostHog as `diagnostic_*` events, about a day later.

## 6. Two-phone checklist (do this on real hardware)

The across-the-table mode is the heart of the app, and the simulator can't cover these:

- [ ] The first launch of Across the table shows the Local Network prompt. Allowing it finds the other phone within a few seconds.
- [ ] Denying it shows "Local Network is off" with an Open Settings button. Turning it on in Settings and coming back works.
- [ ] Both phones on different Wi-Fi networks, or Wi-Fi on with no network joined: peer-to-peer Wi-Fi still connects.
- [ ] Lock one phone mid-game for 30 seconds, then unlock: "Reconnected" appears and the game continues.
- [ ] Swipe the app away on one phone mid-game, reopen it: Home shows "Rejoin …" and the game picks up where it was.
- [ ] Finish a game, tap Rematch on one phone, and Play on the other.
- [ ] On iPhone Duo: half-fold to get the pegboard, open flat for two equal halves, and close to get the outer-screen layout. Opening onto your turn raises the periscope.
- [ ] Pass and play on a Duo: closing the phone hides the fleet immediately.
- [ ] Connecting shows both names and a coin flip on both phones, and both agree on who fires first.
- [ ] On iPhone Duo, slowly close from flat toward 60°: the shadow on your fleet deepens smoothly, without flicker.
- [ ] Debug build: in Settings › Developer › Sound and haptics lab, play every sound and haptic at normal volume. Note any level changes and copy them into `SoundBoard`.
- [ ] iPad with a Magic Keyboard: arrows aim, Return fires, and the pointer outlines cells.

## 7. Before every submission

- [ ] Built with Xcode 27.1 or later.
- [ ] Unit tests: `swift test` in `Packages/GridFleetCore` and `Packages/FoldKit`.
- [ ] UI tests: the GridFleet scheme's test action.
- [ ] Screenshots regenerated (`Marketing/make-screenshots.sh`), Duo included (required from April 2027). For the Duo, unfold the simulator by hand in Simulator or Device Hub first (simctl can't move the hinge), then run the script with `--display internal`.
- [ ] CloudKit schema deployed to production.
- [ ] In-app purchases tested in the sandbox.
