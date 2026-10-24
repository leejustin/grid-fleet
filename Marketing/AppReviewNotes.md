# Notes for App Review

**Grid Fleet** is a two-player sea battle game built for iPhone Duo. It also plays fully on any iPhone or iPad.

## Testing with one device

Choose **Play the computer** on the home screen. No account or second device is needed. Deploy your fleet (Shuffle places it for you), then tap a cell on the enemy grid twice to fire. The computer answers every shot, and a game takes a few minutes.

## Fold features (iPhone Duo)

- **Half-folded:** the enemy grid sits on the top half, which stands up like the lid of the folding board game, and your fleet lies on the bottom half. The boards switch to a pegboard look: white pegs for misses, red for hits.
- **Fully open:** each half of the inner screen shows one grid.
- **Closed, or on a regular iPhone:** the enemy grid fills the screen, and your fleet is a swipe away.
- **Opening the phone on your turn** plays a short "periscope up" animation.
- **In pass and play** (two people sharing one phone), closing the phone covers the fleet immediately.

The app draws only on the inner screen while the device is open. It reads the fold with the public `onHingeChange` API.

## Two-player modes

- **Across the table:** two phones in the same room connect over the local network or peer-to-peer Wi-Fi to play each other. This is why the app asks for Local Network access. It doesn't need an account or an internet connection.
- **Online:** Game Center turn-based and real-time matches.
- **Room code:** a six-character code shared through CloudKit, for friends without Game Center.

## Fair play

In two-device games, each fleet stays on its own phone. Only a salted hash is shared. At the end both fleets are revealed and each phone checks the other against its hash and every reported hit and miss.

## In-app purchases

- **Admiral's Commission:** the hardest computer opponent, salvo mode, two extra board sizes and special weapons.
- **Three cosmetic packs:** themes, ship colors and explosion styles.

Nothing purchasable affects online fairness, and there are no ads. Everything can be tested with a sandbox account from the Shipyard screen.

## Privacy

There's no tracking and no ads. Anonymous usage statistics are sent only if the player opts in after their first game, and they can change it in Settings › Privacy. Crash and performance reports come from MetricKit and are included only for players who opted in.

"Battleship" is a Hasbro trademark. Grid Fleet uses the public-domain rules with its own name, art and code, and contains no Hasbro assets.
