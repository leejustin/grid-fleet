import CoreGraphics
import Foundation
import Testing
@testable import FoldKit

@Suite("Fold geometry")
struct FoldGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 400, height: 800)

    @Test func horizontalHingeSplitsTopAndBottom() {
        let hinge = CGRect(x: 0, y: 390, width: 400, height: 20)
        let panels = FoldGeometry.panels(container: screen, hinge: hinge)
        #expect(panels.first == CGRect(x: 0, y: 0, width: 400, height: 390))
        #expect(panels.second == CGRect(x: 0, y: 410, width: 400, height: 390))
    }

    @Test func gutterWidensAThinHinge() {
        let hinge = FoldGeometry.centerHinge(in: screen)
        let panels = FoldGeometry.panels(container: screen, hinge: hinge, minimumGutter: 16)
        #expect(panels.first.maxY == 392)
        #expect(panels.second.minY == 408)
    }

    @Test func verticalHingeSplitsLeftAndRight() {
        let hinge = CGRect(x: 195, y: 0, width: 10, height: 800)
        let panels = FoldGeometry.panels(container: screen, hinge: hinge)
        #expect(panels.first.width == 195)
        #expect(panels.second.minX == 205)
    }

    @Test func containerBelowTheHingeIsNotSplitOffscreen() {
        // A view that sits wholly below the fold gets an empty first panel, not a negative one.
        let lower = CGRect(x: 0, y: 500, width: 400, height: 300)
        let panels = FoldGeometry.panels(container: lower, hinge: CGRect(x: 0, y: 399, width: 400, height: 2))
        #expect(panels.first.height == 0)
        #expect(panels.second == lower)
    }

    @Test func laptopPostureGivesLandscapeHalves() {
        // iPhone Duo's inner screen, upright, in points.
        let duo = CGRect(x: 0, y: 0, width: 669, height: 951)
        let hinge = try! #require(FoldGeometry.hinge(screen: duo, window: duo))
        let panels = FoldGeometry.panels(container: duo, hinge: hinge)
        #expect(panels.first.width > panels.first.height)
        #expect(panels.second.width > panels.second.height)
    }

    @Test func windowOnOneSideOfTheFoldIsNotSplit() {
        let duo = CGRect(x: 0, y: 0, width: 669, height: 951)
        let bottomHalf = CGRect(x: 0, y: 480, width: 669, height: 471)
        #expect(FoldGeometry.hinge(screen: duo, window: bottomHalf) == nil)
        // A window straddling the fold still splits, at the screen's fold rather than its own middle.
        let tall = CGRect(x: 0, y: 200, width: 669, height: 751)
        #expect(FoldGeometry.hinge(screen: duo, window: tall)?.midY == 475.5)
    }

    @MainActor @Test func monitorReportsNoSplitForAOneSidedWindow() throws {
        let defaults = try #require(UserDefaults(suiteName: "FoldKitWindowTests"))
        defaults.removePersistentDomain(forName: "FoldKitWindowTests")
        let monitor = FoldMonitor(defaults: defaults)
        monitor.update(systemPosture: .halfFolded, angle: 1.9)
        monitor.update(windowFrame: CGRect(x: 0, y: 480, width: 669, height: 471), screenFrame: CGRect(x: 0, y: 0, width: 669, height: 951))
        #expect(monitor.state.posture == .halfFolded)
        #expect(!monitor.state.splitsWindow)
    }

    @Test func sidewaysWindowFoldsDownTheMiddle() {
        let hinge = FoldGeometry.centerHinge(in: CGRect(x: 0, y: 0, width: 800, height: 400))
        #expect(hinge.width == 1)
        #expect(hinge.midX == 400)
    }

    @MainActor @Test func systemPostureDrivesStateUnlessSimulated() throws {
        let defaults = try #require(UserDefaults(suiteName: "FoldKitSystemTests"))
        defaults.removePersistentDomain(forName: "FoldKitSystemTests")
        let monitor = FoldMonitor(defaults: defaults)
        monitor.update(windowFrame: screen)
        monitor.update(systemPosture: .halfFolded, angle: 1.9)
        #expect(monitor.state.posture == .halfFolded)
        #expect(!monitor.state.isSimulated)
        #expect(monitor.state.hinge?.midY == 400)
        monitor.simulatedPosture = .closed
        #expect(monitor.state.posture == .closed)
        monitor.simulatedPosture = nil
        #expect(monitor.state.posture == .halfFolded)
    }

    @Test func noHingeSplitsInHalf() {
        let panels = FoldGeometry.panels(container: screen, hinge: nil)
        #expect(panels.first.height == 400)
        #expect(panels.second.height == 400)
    }

    @MainActor @Test func simulationOverridesAndPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "FoldKitTests"))
        defaults.removePersistentDomain(forName: "FoldKitTests")
        let monitor = FoldMonitor(defaults: defaults)
        #expect(monitor.state.posture == .unfoldable)
        monitor.update(windowFrame: screen)
        monitor.simulatedPosture = .halfFolded
        #expect(monitor.state.posture == .halfFolded)
        #expect(monitor.state.isSimulated)
        #expect(monitor.state.hinge?.midY == 400)
        #expect(FoldMonitor(defaults: defaults).simulatedPosture == .halfFolded)
    }

    @MainActor @Test func hingeAngleFollowsTheSystemOrTheSimulation() throws {
        let defaults = try #require(UserDefaults(suiteName: "FoldKitAngleTests"))
        defaults.removePersistentDomain(forName: "FoldKitAngleTests")
        let monitor = FoldMonitor(defaults: defaults)
        #expect(monitor.effectiveHingeAngle == nil)
        // Rounded to two degrees.
        monitor.update(systemPosture: .halfFolded, angle: 91.3 * .pi / 180)
        let system = try #require(monitor.effectiveHingeAngle)
        #expect(abs(system - 92 * .pi / 180) < 0.0001)
        // A simulated half fold uses a typical angle, or the one set for testing.
        monitor.simulatedPosture = .halfFolded
        #expect(abs((monitor.effectiveHingeAngle ?? 0) - 110 * .pi / 180) < 0.0001)
        defaults.set("80", forKey: FoldMonitor.simulatedAngleKey)
        #expect(abs((monitor.effectiveHingeAngle ?? 0) - 80 * .pi / 180) < 0.0001)
        monitor.simulatedPosture = .flat
        #expect(monitor.effectiveHingeAngle == .pi)
    }
}
