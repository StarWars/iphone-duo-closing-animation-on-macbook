import XCTest
@testable import DuoLid

final class TriggerTests: XCTestCase {
    func testSavedAndEditedAnglesStayWithinWholeDegreeRange() {
        XCTAssertEqual(LidTrigger().angle, 90)
        XCTAssertEqual(LidTrigger(angle: 79.4).angle, 79)
        XCTAssertEqual(LidTrigger(angle: 79.5).angle, 80)
        XCTAssertEqual(LidTrigger(angle: -1).angle, 30)
        XCTAssertEqual(LidTrigger(angle: 200).angle, 140)
        for angle in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(LidTrigger(angle: angle).angle, 90)
        }
    }

    func testOpenGateRejectsInvalidAndBelowTriggerReadings() {
        for angle in [30.0, 75, 90, 110, 140] {
            let trigger = LidTrigger(angle: angle)
            XCTAssertFalse(trigger.isOpen(angle - 0.001))
            XCTAssertTrue(trigger.isOpen(angle))
            XCTAssertTrue(trigger.isOpen(180))
            for reading in [Double.nan, .infinity, -1, 181] {
                XCTAssertFalse(trigger.isOpen(reading))
            }
        }
    }

    func testCustomThresholdHoldsReversesAndRemovesImmediately() {
        for angle in [30.0, 75, 90, 110, 140] {
            var tracker = GestureTracker(trigger: LidTrigger(angle: angle))
            XCTAssertEqual(tracker.update(angle + 10), .idle)
            XCTAssertEqual(tracker.update(angle), .idle)
            XCTAssertEqual(tracker.update(angle - 0.001), .bending(reference: angle, angle: angle - 0.001))
            for reading in [angle - 10, angle - 10, angle - 2, angle - 15] {
                XCTAssertEqual(tracker.update(reading), .bending(reference: angle, angle: reading))
            }
            XCTAssertEqual(tracker.update(angle), .idle)
            XCTAssertFalse(tracker.active)
            XCTAssertEqual(tracker.update(angle - 1), .bending(reference: angle, angle: angle - 1))
        }
    }

    func testNearClosureRequiresReopeningToTheCustomTrigger() {
        for angle in [30.0, 75, 110, 140] {
            var tracker = GestureTracker(trigger: LidTrigger(angle: angle))
            _ = tracker.update(angle - 5)
            XCTAssertEqual(tracker.update(8), .closed)
            XCTAssertNil(tracker.reference)
            XCTAssertEqual(tracker.update(angle - 1), .idle)
            XCTAssertEqual(tracker.update(angle), .idle)
            XCTAssertEqual(tracker.update(angle - 1), .bending(reference: angle, angle: angle - 1))
        }
    }

    func testChangingTriggerDiscardsActiveGestureAndWaitsForOpening() {
        var tracker = GestureTracker()
        _ = tracker.update(80)
        XCTAssertTrue(tracker.active)
        tracker.configure(trigger: LidTrigger(angle: 110))
        XCTAssertFalse(tracker.active)
        XCTAssertEqual(tracker.reference, 110)
        XCTAssertEqual(tracker.update(100), .idle)
        XCTAssertEqual(tracker.update(110), .idle)
        XCTAssertEqual(tracker.update(109), .bending(reference: 110, angle: 109))
        tracker.configure(trigger: LidTrigger(angle: 75))
        XCTAssertEqual(tracker.update(80), .idle)
        XCTAssertEqual(tracker.update(74), .bending(reference: 75, angle: 74))
    }

    func testVisualRangeStartsAtTriggerAndFinishesNearClosure() {
        for angle: Float in [30, 75, 90, 110, 140] {
            var state = EffectState()
            state.referenceAngle = angle
            state.angle = angle + 10
            XCTAssertEqual(state.fold, 0)
            state.angle = angle
            XCTAssertEqual(state.fold, 0)
            state.angle = (angle + 10) / 2
            XCTAssertEqual(state.fold, 40, accuracy: 0.00001)
            state.angle = 10
            XCTAssertEqual(state.fold, 80, accuracy: 0.00001)
        }
    }
}
