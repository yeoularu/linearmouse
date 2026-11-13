// MIT License
// Copyright (c) 2026 LinearMouse

@testable import LinearMouse
import XCTest

final class InstantSpaceSwitchTests: XCTestCase {
    private func display(
        _ identifier: String,
        current: UInt64,
        spaces: [(UInt64, Int)]
    ) -> InstantSpaceSwitch.Display {
        .init(
            identifier: identifier,
            current: current,
            spaces: spaces.map { InstantSpaceSwitch.Space(id: $0.0, type: $0.1) }
        )
    }

    func testMovesToTheNeighborOnThePointerDisplay() {
        let displays = [
            display("other", current: 1, spaces: [(1, 0), (2, 0)]),
            display("pointer", current: 10, spaces: [(10, 0), (11, 4), (12, 0)])
        ]

        let right = InstantSpaceSwitch.target(
            displays: displays,
            pointerDisplayIdentifier: "pointer",
            direction: .right
        )
        XCTAssertEqual(right?.display, "pointer")
        XCTAssertEqual(right?.from, 10)
        XCTAssertEqual(right?.to, 11)

        let left = InstantSpaceSwitch.target(
            displays: displays,
            pointerDisplayIdentifier: "pointer",
            direction: .left
        )
        XCTAssertNil(left)
    }

    func testSkipsSpacesThatAreNotDesktopOrFullscreen() {
        let displays = [
            display("pointer", current: 1, spaces: [(1, 0), (9, 2), (3, 0)])
        ]

        let right = InstantSpaceSwitch.target(
            displays: displays,
            pointerDisplayIdentifier: "pointer",
            direction: .right
        )
        XCTAssertEqual(right?.to, 3)
    }

    func testUsesTheFirstDisplayWhenThePointerDisplayIsUnknown() {
        let displays = [
            display("first", current: 4, spaces: [(4, 0), (5, 0)])
        ]

        let right = InstantSpaceSwitch.target(
            displays: displays,
            pointerDisplayIdentifier: "missing",
            direction: .right
        )
        XCTAssertEqual(right?.display, "first")
        XCTAssertEqual(right?.to, 5)
    }

    func testStopsAtEitherEnd() {
        let displays = [
            display("pointer", current: 2, spaces: [(1, 0), (2, 0)])
        ]

        XCTAssertNil(InstantSpaceSwitch.target(
            displays: displays,
            pointerDisplayIdentifier: "pointer",
            direction: .right
        ))
    }

    func testRapidReversalWaitsForTheFirstSwitch() {
        var submitted: [UInt64] = []
        let coordinator = InstantSpaceSwitch.Coordinator { _, to, _ in
            submitted.append(to)
            return true
        }
        let original = display("screen", current: 10, spaces: [(10, 0), (11, 0), (12, 0)])
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0))
        XCTAssertTrue(coordinator.perform(display: original, direction: .left, now: 0.01))
        XCTAssertEqual(submitted, [11])
        coordinator.reconcile(displays: [original], now: 0.02)
        XCTAssertEqual(submitted, [11])
        coordinator.reconcile(
            displays: [display("screen", current: 11, spaces: [(10, 0), (11, 0), (12, 0)])], now: 0.03
        )
        XCTAssertEqual(submitted, [11, 10])
        coordinator.reconcile(displays: [original], now: 0.04)
        XCTAssertTrue(coordinator.pending.isEmpty)
    }

    func testRapidForwardInputKeepsTheFinalDestination() {
        var submitted: [UInt64] = []
        let coordinator = InstantSpaceSwitch.Coordinator { _, to, _ in
            submitted.append(to)
            return true
        }
        let original = display("screen", current: 10, spaces: [(10, 0), (11, 0), (12, 0)])
        for time in [0.0, 0.01, 0.02] {
            XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: time))
        }
        XCTAssertEqual(submitted, [11])
        coordinator.reconcile(
            displays: [display("screen", current: 11, spaces: [(10, 0), (11, 0), (12, 0)])], now: 0.03
        )
        XCTAssertEqual(submitted, [11, 12])
        coordinator.reconcile(
            displays: [display("screen", current: 12, spaces: [(10, 0), (11, 0), (12, 0)])], now: 0.04
        )
        XCTAssertTrue(coordinator.pending.isEmpty)
    }

    func testTimeoutDropsTheUnconfirmedRequestAndTheNextInputTriesAgain() {
        var submissions = 0
        let coordinator = InstantSpaceSwitch.Coordinator { _, _, _ in
            submissions += 1
            return true
        }
        let original = display("screen", current: 10, spaces: [(10, 0), (11, 0), (12, 0)])
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0))
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0.1))
        coordinator.reconcile(displays: [original], now: 0.49)
        XCTAssertFalse(coordinator.pending.isEmpty)
        coordinator.reconcile(displays: [original], now: 0.5)
        XCTAssertTrue(coordinator.pending.isEmpty)
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0.6))
        XCTAssertEqual(submissions, 2)
        coordinator.reconcile(displays: nil, now: 0.7)
        XCTAssertTrue(coordinator.pending.isEmpty)
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0.8))
        XCTAssertEqual(submissions, 3)
    }

    func testExternalSwitchAndDisconnectedDisplayDiscardPendingInput() {
        let coordinator = InstantSpaceSwitch.Coordinator { _, _, _ in true }
        let original = display("screen", current: 10, spaces: [(10, 0), (11, 0), (12, 0)])
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0))
        coordinator.reconcile(
            displays: [display("screen", current: 12, spaces: [(10, 0), (11, 0), (12, 0)])], now: 0.1
        )
        XCTAssertTrue(coordinator.pending.isEmpty)
        XCTAssertTrue(coordinator.perform(display: original, direction: .right, now: 0.2))
        coordinator.reconcile(displays: [], now: 0.3)
        XCTAssertTrue(coordinator.pending.isEmpty)
    }

    func testRejectedSubmissionFallsBackButBoundaryDoesNot() {
        let coordinator = InstantSpaceSwitch.Coordinator { _, _, _ in false }
        let original = display("screen", current: 10, spaces: [(10, 0), (11, 0)])
        XCTAssertFalse(coordinator.perform(display: original, direction: .right, now: 0))
        XCTAssertTrue(coordinator.perform(display: original, direction: .left, now: 0))
        XCTAssertTrue(coordinator.pending.isEmpty)
    }

    func testExternalSwitchIsReconciledBeforeNewInput() {
        var submitted: [UInt64] = []
        let coordinator = InstantSpaceSwitch.Coordinator { _, to, _ in
            submitted.append(to)
            return true
        }
        let spaces: [(UInt64, Int)] = [(10, 0), (11, 0), (12, 0), (13, 0)]
        XCTAssertTrue(coordinator.perform(
            display: display("A", current: 10, spaces: spaces), direction: .right, now: 0
        ))
        XCTAssertTrue(coordinator.perform(
            display: display("A", current: 12, spaces: spaces), direction: .right, now: 0.001
        ))
        XCTAssertEqual(submitted, [11, 13])
    }

    func testDecodesAndMergesTheBetaSetting() throws {
        let scheme = try JSONDecoder().decode(
            Scheme.self,
            from: Data(#"{"buttons":{"instantSpaceSwitch":true}}"#.utf8)
        )
        XCTAssertEqual(scheme.buttons.instantSpaceSwitch, true)

        var buttons = Scheme.Buttons()
        scheme.buttons.merge(into: &buttons)
        XCTAssertEqual(buttons.instantSpaceSwitch, true)

        var disabled = Scheme.Buttons()
        disabled.instantSpaceSwitch = false
        disabled.merge(into: &buttons)
        XCTAssertEqual(buttons.instantSpaceSwitch, false)
    }
}
