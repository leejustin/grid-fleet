#!/bin/zsh
# Generates App Store screenshots with the debug demo scenes.
#
#   Marketing/make-screenshots.sh <app path> <device UDID> <set name> [--display internal]
#
# Build first: xcodebuild -scheme GridFleet -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build
# For iPhone Duo, open the device in Simulator or Device Hub first and half-fold it (simctl can't move the hinge),
# then pass --display internal to capture the inner screen. While the Duo is closed, that display is black.
set -e
APP=$1; DEV=$2; SET=$3; shift 3
DISPLAY_ARGS=("$@")
OUT="$(dirname $0)/Screenshots/$SET"
mkdir -p "$OUT"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl status_bar "$DEV" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 2>/dev/null || true
xcrun simctl install "$DEV" "$APP"

shoot() {
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$DEV" com.leejustin.gridfleet 2>/dev/null || true
  xcrun simctl launch "$DEV" com.leejustin.gridfleet -GFUITest YES -hasSeenTutorial YES -analyticsOptIn NO -followAction NO "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEV" screenshot "${DISPLAY_ARGS[@]}" "$OUT/$name.png" >/dev/null
  echo "$OUT/$name.png"
}

# Start from a clean harbor: no saved battle or rejoinable game on the home screen.
xcrun simctl spawn "$DEV" defaults delete com.leejustin.gridfleet savedBattle 2>/dev/null || true
xcrun simctl spawn "$DEV" defaults delete com.leejustin.gridfleet savedNearbyGame 2>/dev/null || true
shoot 01-home 6 -GFDemo none -FoldKit.simulatedPosture none
shoot 02-intro 4 -GFDemo intro -FoldKit.simulatedPosture none
shoot 03-battle 45 -GFDemo battle -GFDemoTurns 12 -GFDemoRival hard -FoldKit.simulatedPosture none
# Only a real fold may show the half-fold layout. Elsewhere, show the pegboard through its setting ("Always pegs"),
# which is exactly what a player on this device would see.
if [[ "${DISPLAY_ARGS[*]}" == *internal* ]]; then
  shoot 04-pegboard 40 -GFDemo battle -GFDemoTurns 12 -GFDemoRival medium -FoldKit.simulatedPosture none
else
  shoot 04-pegboard 40 -GFDemo battle -GFDemoTurns 12 -GFDemoRival medium -FoldKit.simulatedPosture none -boardStyle pegboard
fi
shoot 05-across-the-table 6 -GFDemo nearbyLobby -playerName Ava -FoldKit.simulatedPosture none
shoot 06-result 12 -GFDemo result -FoldKit.simulatedPosture none
shoot 07-logbook 6 -GFDemo logbook -FoldKit.simulatedPosture none
shoot 08-shipyard 6 -GFDemo shipyard -FoldKit.simulatedPosture none
