import XCTest
@testable import DuoLid

final class GestureTests: XCTestCase {
    func testHoldsAndReversesWithoutChangingReference() {
        var tracker = GestureTracker()
        tracker.reset(at: 123)
        XCTAssertEqual(tracker.update(122), .idle)
        XCTAssertEqual(tracker.update(90), .idle)
        XCTAssertEqual(tracker.update(89.999), .bending(reference: 90, angle: 89.999))
        for angle in [80.0, 65, 65, 89, 70, 88] {
            XCTAssertEqual(tracker.update(angle), .bending(reference: 90, angle: angle))
        }
        XCTAssertEqual(tracker.update(123), .idle)
        XCTAssertFalse(tracker.active)
    }

    func testAlwaysUsesNinetyRegardlessOfOpenPosture() {
        var tracker = GestureTracker()
        XCTAssertEqual(tracker.update(100), .idle)
        XCTAssertEqual(tracker.update(125), .idle)
        XCTAssertEqual(tracker.update(122), .idle)
        XCTAssertEqual(tracker.update(90), .idle)
        XCTAssertEqual(tracker.update(89), .bending(reference: 90, angle: 89))
        XCTAssertEqual(tracker.update(90), .idle)
        XCTAssertEqual(tracker.update(89), .bending(reference: 90, angle: 89))
    }

    func testNearClosureDiscardsPriorGesture() {
        var tracker = GestureTracker()
        tracker.reset(at: 120)
        _ = tracker.update(80)
        XCTAssertEqual(tracker.update(8), .closed)
        XCTAssertNil(tracker.reference)
        XCTAssertFalse(tracker.active)
        XCTAssertEqual(tracker.update(50), .idle)
        XCTAssertEqual(tracker.update(100), .idle)
        XCTAssertEqual(tracker.update(97), .idle)
        XCTAssertEqual(tracker.update(89), .bending(reference: 90, angle: 89))
    }

    func testInvalidMeasurementsNeverBecomeAnAngle() {
        var tracker = GestureTracker()
        tracker.reset(at: 120)
        for value in [Double.nan, .infinity, -.infinity, -1, 181] {
            XCTAssertEqual(tracker.update(value), .invalid)
            XCTAssertEqual(tracker.reference, 90)
            XCTAssertFalse(tracker.active)
        }
    }

    func testResetStopsAnActiveGesture() {
        var tracker = GestureTracker()
        tracker.reset(at: 120)
        _ = tracker.update(60)
        tracker.reset(at: 105)
        XCTAssertFalse(tracker.active)
        XCTAssertEqual(tracker.update(105), .idle)
        XCTAssertEqual(tracker.update(102), .idle)
        XCTAssertEqual(tracker.update(89), .bending(reference: 90, angle: 89))
    }

    func testReportLengthAndRangeAreValidated() {
        XCTAssertEqual(LidReport.angle(bytes: [1, 120, 0, 0, 0, 0, 0, 0], length: 8), 120)
        XCTAssertEqual(LidReport.angle(bytes: [1, 0, 0], length: 3), 0)
        XCTAssertNil(LidReport.angle(bytes: [1, 120], length: 2))
        XCTAssertNil(LidReport.angle(bytes: [1, 120, 0], length: 8))
        XCTAssertNil(LidReport.angle(bytes: [1, 181, 0], length: 3))
        XCTAssertNil(LidReport.angle(bytes: [1, 0, 1], length: 3))
    }

    func testFilterReversesAndExplicitlyResets() {
        var filter = AngleFilter()
        filter.ingest(120, time: 0)
        filter.ingest(90, time: 0)
        let closing = filter.sample(at: 0.05) ?? 120
        filter.ingest(110, time: 0.05)
        let reopening = filter.sample(at: 0.1) ?? 0
        XCTAssertLessThan(closing, 120)
        XCTAssertGreaterThan(reopening, closing)
        filter.reset()
        XCTAssertEqual(filter.update(70, time: 1), 70)
        XCTAssertNil(filter.update(.nan, time: 2))
        XCTAssertFalse(filter.ingest(69, time: 0.5))
        XCTAssertEqual(filter.value, 70)
    }

    func testWholeDegreeReportsTransitionAcrossSeveralFrames() {
        var filter = AngleFilter()
        filter.ingest(90, time: 0)
        filter.ingest(89, time: 0)
        var previous = 90.0
        var largestStep = 0.0
        for frame in 1...120 {
            let current = filter.sample(at: Double(frame) / 60) ?? 0
            XCTAssertGreaterThanOrEqual(current, 89)
            XCTAssertLessThanOrEqual(current, previous)
            largestStep = max(largestStep, previous - current)
            if frame == 1 { XCTAssertGreaterThan(current, 89.85) }
            previous = current
        }
        XCTAssertLessThan(largestStep, 0.035, "An isolated degree must move gently across many frames")
        XCTAssertEqual(filter.value, 89)
        XCTAssertTrue(filter.isSettled)
        XCTAssertEqual(filter.sample(at: 3), 89)
    }

    func testDampingIsIndependentOfPresentationCadence() {
        var values: [Double] = []
        for rate in [30, 60, 120] {
            var filter = AngleFilter()
            filter.ingest(90, time: 0)
            filter.ingest(80, time: 0)
            for frame in 1...(rate / 5) { _ = filter.sample(at: Double(frame) / Double(rate)) }
            values.append(filter.value ?? 0)
        }
        XCTAssertEqual(values[0], values[1], accuracy: 0.000001)
        XCTAssertEqual(values[1], values[2], accuracy: 0.000001)
    }

    func testQuantizedMotionWithRepeatedReportsAndReversalNeverOvershoots() {
        var filter = AngleFilter()
        _ = filter.update(90, time: 0)
        var previous = 90.0
        for frame in 1...120 {
            let raw = frame <= 60 ? 90 - Double(frame / 6) : 80 + Double((frame - 60) / 6)
            let current = filter.update(raw, time: Double(frame) / 60) ?? 0
            XCTAssertGreaterThanOrEqual(current, min(previous, raw))
            XCTAssertLessThanOrEqual(current, max(previous, raw))
            previous = current
        }
        for frame in 121...150 { _ = filter.update(90, time: Double(frame) / 60) }
        XCTAssertEqual(filter.value, 90)
        XCTAssertTrue(filter.isSettled)
    }

    func testFrameFilteringHoldsAndChangesDirectionWithoutOvershoot() {
        var filter = AngleFilter()
        filter.ingest(90, time: 0)
        filter.ingest(89, time: 0)
        let first = filter.sample(at: 1.0 / 60) ?? 0
        XCTAssertGreaterThan(first, 89)
        XCTAssertLessThan(first, 90)
        for frame in 2...120 { _ = filter.sample(at: Double(frame) / 60) }
        XCTAssertEqual(filter.value, 89)
        filter.ingest(90, time: 2)
        let reverse = filter.sample(at: 2 + 1.0 / 60) ?? 0
        XCTAssertGreaterThan(reverse, 89)
        XCTAssertLessThan(reverse, 90)
    }

    func testNewReadingAfterPausedDrawingDoesNotSnap() {
        var filter = AngleFilter()
        filter.ingest(80, time: 0)
        XCTAssertTrue(filter.isSettled)
        // Healthy repeated reports continue while a settled view draws nothing.
        for frame in 1..<120 { filter.ingest(80, time: Double(frame) / 60) }
        filter.ingest(79, time: 2)
        XCTAssertEqual(filter.value, 80)
        XCTAssertFalse(filter.isSettled)
        let first = filter.sample(at: 2 + 1.0 / 60) ?? 0
        XCTAssertGreaterThan(first, 79.99)
        XCTAssertLessThan(first, 80)
    }

    func testOneDegreeEveryTwoSecondsStaysSmoothIncludingDrawingPauses() {
        var filter = AngleFilter()
        filter.ingest(80, time: 0)
        var previous = 80.0
        var largestStep = 0.0
        var movingFrames = 0
        for frame in 1...840 {
            let raw = 80 - Double(min(5, frame / 120))
            filter.ingest(raw, time: Double(frame) / 60)
            // Same pause/resume rule as the real preview/overlay.
            let current = filter.isSettled ? (filter.value ?? 0) : (filter.sample(at: Double(frame) / 60) ?? 0)
            XCTAssertGreaterThanOrEqual(current, raw)
            XCTAssertLessThanOrEqual(current, previous)
            largestStep = max(largestStep, previous - current)
            if frame >= 240 && frame < 360 && previous - current > 0.0001 { movingFrames += 1 }
            previous = current
        }
        XCTAssertLessThan(largestStep, 0.035)
        XCTAssertGreaterThan(movingFrames, 100, "The two-second interval should contain sustained fractional motion")
        XCTAssertEqual(filter.value, 75)
        XCTAssertTrue(filter.isSettled)
    }

    func testSlowMotionHoldAndReversalSettleWithoutOvershoot() {
        var filter = AngleFilter()
        filter.ingest(80, time: 0)
        filter.ingest(79, time: 2)
        filter.ingest(78, time: 4)
        _ = filter.sample(at: 4.5)
        let previous = filter.value ?? 0
        filter.ingest(79, time: 4.5)
        let reversed = filter.sample(at: 4.5 + 1.0 / 60) ?? 0
        XCTAssertGreaterThan(reversed, previous)
        XCTAssertLessThan(reversed, 79)
        for frame in 1...240 { _ = filter.sample(at: 4.5 + Double(frame) / 60) }
        XCTAssertEqual(filter.value, 79)
        XCTAssertTrue(filter.isSettled)
        XCTAssertEqual(filter.sample(at: 20), 79)
    }

    func testSlowMotionReturnsToFastResponseForLargerReports() {
        var filter = AngleFilter()
        filter.ingest(80, time: 0)
        filter.ingest(79, time: 2)
        filter.ingest(78, time: 4)
        XCTAssertEqual(filter.responseTime, 0.55)
        _ = filter.sample(at: 4.2)
        filter.ingest(70, time: 4.2)
        XCTAssertEqual(filter.responseTime, 0.065)
        XCTAssertEqual(filter.sample(at: 4.6) ?? 0, 70, accuracy: 0.002)
    }

    func testFastWholeDegreeMotionKeepsResponsiveTracking() {
        var filter = AngleFilter()
        filter.ingest(90, time: 0)
        for frame in 1...120 {
            let raw = 90 - Double(frame / 2) // 30 degrees/second
            filter.ingest(raw, time: Double(frame) / 60)
            let presented = filter.sample(at: Double(frame) / 60) ?? 0
            XCTAssertGreaterThanOrEqual(presented, raw)
            if frame >= 30 {
                XCTAssertLessThan(presented - raw, 2.6)
                XCTAssertEqual(filter.responseTime, 0.065)
            }
        }
    }

    func testDelayedReportCannotIntegratePastItsNewMeasuredBound() {
        var filter = AngleFilter()
        filter.ingest(90, time: 0)
        filter.ingest(80, time: 0)
        let previous = filter.sample(at: 0.05) ?? 0
        XCTAssertGreaterThan(previous, 84)
        filter.ingest(84, time: 1)
        XCTAssertGreaterThanOrEqual(filter.value ?? 0, 84)
        XCTAssertLessThanOrEqual(filter.value ?? 0, previous)
        XCTAssertEqual(filter.sample(at: 1.1), 84)
        XCTAssertTrue(filter.isSettled)
    }
}
