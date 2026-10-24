import XCTest

/// Taps through the app the way a player would. Runs on any iPhone simulator.
@MainActor
final class GridFleetUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-GFUITest", "YES",
            "-hasSeenTutorial", "YES",
            "-analyticsOptIn", "NO",
            "-rivalChatter", "NO",
            "-oneTapFire", "NO",
            "-FoldKit.simulatedPosture", "none",
        ]
    }

    // MARK: Helpers

    private func element(_ identifier: String, in container: XCUIElement? = nil) -> XCUIElement {
        (container ?? app).descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        return element
    }

    /// Polls until the condition holds, or fails the test after the timeout.
    private func waitUntil(_ description: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.25))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }

    private func startComputerGame() {
        app.launch()
        waitFor(element("play-computer")).tap()
        waitFor(element("start-game")).tap()
    }

    private func deployRandomly() {
        waitFor(element("shuffle")).tap()
        let ready = element("ready")
        XCTAssertTrue(ready.isEnabled, "Ready should be enabled once every ship is placed")
        ready.tap()
    }

    private func skipIntroIfShown() {
        let intro = element("rival-intro")
        if intro.waitForExistence(timeout: 4) { intro.tap() }
    }

    // MARK: Tests

    func testDeployAndFireAgainstTheComputer() {
        startComputerGame()
        deployRandomly()
        skipIntroIfShown()

        let board = waitFor(element("enemy-board"))
        let cell = waitFor(element("cell-E5", in: board))
        // First tap aims, second fires.
        cell.tap()
        XCTAssertTrue(cell.label.contains("aimed"), "The first tap should aim: \(cell.label)")
        cell.tap()

        let shots = element("stat-shots")
        waitUntil("one shot counted", timeout: 8) { shots.label.hasPrefix("1") }

        // The computer answers, then it's our turn again.
        let status = element("turn-status")
        waitUntil("our turn again", timeout: 20) { status.label.contains("Your turn") }
        let result = element("cell-E5", in: board).label
        XCTAssertTrue(result.contains("miss") || result.contains("hit"), "E5 should show the result: \(result)")
    }

    func testCannotFireTwiceAtTheSameCell() {
        startComputerGame()
        deployRandomly()
        skipIntroIfShown()
        let board = waitFor(element("enemy-board"))
        let cell = waitFor(element("cell-A1", in: board))
        cell.tap()
        cell.tap()
        let status = element("turn-status")
        waitUntil("our turn again", timeout: 20) { status.label.contains("Your turn") }
        // Tapping a cell already fired at doesn't aim it.
        cell.tap()
        XCTAssertFalse(element("fire").isEnabled)
    }

    func testPlacingShipsFromTheDock() {
        startComputerGame()
        let ready = waitFor(element("ready"))
        XCTAssertFalse(ready.isEnabled, "Ready stays off until the whole fleet is placed")
        for kind in ["carrier", "cruiser", "destroyer", "submarine", "patrol"] {
            waitFor(element("dock-\(kind)")).tap()
        }
        XCTAssertTrue(ready.isEnabled)
        waitFor(element("clear")).tap()
        XCTAssertFalse(ready.isEnabled)
    }

    func testDraggingAShipOntoTheGrid() {
        startComputerGame()
        let board = waitFor(element("deploy-board"))
        let carrier = waitFor(element("dock-carrier"))
        let target = waitFor(element("cell-C3", in: board))
        carrier.press(forDuration: 0.2, thenDragTo: target)
        // A placed carrier names itself on the cells it covers.
        let covered = board.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Carrier'"))
        waitUntil("the carrier on five cells", timeout: 5) { covered.count == 5 }
    }

    func testPassAndPlayHidesEachFleet() {
        app.launch()
        waitFor(element("pass-and-play")).tap()
        waitFor(element("start-game")).tap()
        deployRandomly()
        // The first captain's fleet is covered before the phone changes hands.
        let hold = waitFor(element("handoff-hold"))
        XCTAssertTrue(hold.label.contains("Player 2"))
        hold.press(forDuration: 1.2)
        // The second captain deploys their own fleet.
        waitFor(element("shuffle"))
        XCTAssertTrue(app.staticTexts["Player 2's fleet"].exists)
    }

    func testKeyboardAimsAndFires() {
        startComputerGame()
        deployRandomly()
        skipIntroIfShown()
        let board = waitFor(element("enemy-board"))
        // The first arrow press lands in the middle of the board (F6), the next moves right.
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        let cell = waitFor(element("cell-G6", in: board))
        waitUntil("G6 aimed", timeout: 3) { cell.label.contains("aimed") }
        // Space on the aimed cell fires. (Return does too on a real keyboard, but XCUITest's synthetic
        // Return never reaches the app in the simulator, so it can't be tested here.)
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        // The shot is away once it's no longer our turn; then the computer answers and G6 shows the result.
        let status = element("turn-status")
        waitUntil("the shot fired", timeout: 5) { !status.label.contains("Your turn") }
        waitUntil("our turn again", timeout: 20) { status.label.contains("Your turn") }
        let result = element("cell-G6", in: waitFor(element("enemy-board"))).label
        XCTAssertTrue(result.contains("miss") || result.contains("hit"), "G6 should show the result: \(result)")
    }

    func testGuidedFirstGame() {
        app.launchArguments += ["-hasSeenTutorial", "NO"]
        app.launch()
        waitFor(element("first-battle")).tap()
        deployRandomly()
        skipIntroIfShown()
        let tips = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Tip from Ensign Pip'"))
        waitUntil("the aiming tip", timeout: 5) { tips.firstMatch.label.contains("Tap any square") }
        let board = waitFor(element("enemy-board"))
        let cell = waitFor(element("cell-B2", in: board))
        cell.tap()
        waitUntil("the firing tip", timeout: 5) { tips.firstMatch.label.contains("tap Fire") }
        waitFor(element("fire")).tap()
        // The next tip waits for our turn to come back, then explains the mark we just made.
        let status = element("turn-status")
        waitUntil("our turn again", timeout: 20) { status.label.contains("Your turn") }
        waitUntil("the hit and miss tip", timeout: 5) { tips.firstMatch.label.contains("means a miss") }
        waitFor(element("cell-C3", in: board)).tap()
        waitUntil("the goal tip", timeout: 5) { tips.firstMatch.label.contains("sink all five") }
    }
}
