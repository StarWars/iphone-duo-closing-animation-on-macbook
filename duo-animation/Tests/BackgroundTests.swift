import XCTest
@testable import DuoLid

final class BackgroundTests: XCTestCase {
    private func ready(_ state: BackgroundState) -> Bool {
        state.canArm(angle: 110, fresh: true, permission: true, shortcut: true, display: true)
    }

    func testStartsOffUntilRequested() {
        var state = BackgroundState()
        XCTAssertFalse(ready(state))
        state.requested = true
        XCTAssertTrue(ready(state))
    }

    func testEachRequiredCapabilityBlocksAutomaticCapture() {
        var state = BackgroundState()
        state.requested = true
        XCTAssertFalse(state.canArm(angle: 110, fresh: false, permission: true, shortcut: true, display: true))
        XCTAssertFalse(state.canArm(angle: 110, fresh: true, permission: false, shortcut: true, display: true))
        XCTAssertFalse(state.canArm(angle: 110, fresh: true, permission: true, shortcut: false, display: true))
        XCTAssertFalse(state.canArm(angle: 110, fresh: true, permission: true, shortcut: true, display: false))
        XCTAssertTrue(ready(state))
    }

    func testResumptionRequiresAnOpenValidLid() {
        var state = BackgroundState()
        state.requested = true
        for angle: Double? in [nil, .nan, .infinity, -1, 8, 70, 89.999, 181] {
            XCTAssertFalse(state.canArm(angle: angle, fresh: true, permission: true, shortcut: true, display: true))
        }
        XCTAssertTrue(state.canArm(angle: 90, fresh: true, permission: true, shortcut: true, display: true))
    }

    func testResumptionUsesTheSelectedTrigger() {
        var state = BackgroundState()
        state.requested = true
        for angle in [30.0, 75, 110, 140] {
            let trigger = LidTrigger(angle: angle)
            XCTAssertFalse(state.canArm(angle: angle - 1, fresh: true, permission: true,
                                       shortcut: true, display: true, trigger: trigger))
            XCTAssertTrue(state.canArm(angle: angle, fresh: true, permission: true,
                                      shortcut: true, display: true, trigger: trigger))
            state.receive(.lock)
            XCTAssertFalse(state.canArm(angle: angle, fresh: true, permission: true,
                                       shortcut: true, display: true, trigger: trigger))
            state.receive(.unlock)
        }
    }

    func testWakeCannotResumeWhileStillLocked() {
        var state = BackgroundState()
        state.requested = true
        state.receive(.lock)
        state.receive(.sleep)
        state.receive(.wake)
        XCTAssertFalse(ready(state))
        state.receive(.unlock)
        XCTAssertTrue(ready(state))
        XCTAssertTrue(state.requested)
    }

    func testDisplayWakeCannotClearSystemSleep() {
        var state = BackgroundState()
        state.requested = true
        state.receive(.sleep)
        state.receive(.displaySleep)
        state.receive(.displayWake)
        XCTAssertFalse(ready(state))
        state.receive(.wake)
        XCTAssertTrue(ready(state))
    }

    func testUserSessionAndDisplayMustBothReturnBeforeResuming() {
        var state = BackgroundState()
        state.requested = true
        state.receive(.resignSession)
        state.receive(.displaySleep)
        state.receive(.activateSession)
        XCTAssertFalse(ready(state))
        state.receive(.displayWake)
        XCTAssertTrue(ready(state))
    }

    func testManualPauseSurvivesWakeAndUnlock() {
        var state = BackgroundState()
        state.requested = true
        state.receive(.lock)
        state.receive(.sleep)
        state.requested = false
        state.receive(.wake)
        state.receive(.unlock)
        XCTAssertFalse(state.suspended)
        XCTAssertFalse(ready(state))
    }
}
