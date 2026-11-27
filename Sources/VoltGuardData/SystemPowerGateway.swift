import Foundation
import IOKit.pwr_mgt
import VoltGuardDomain

public final class SystemPowerGateway: PowerManagementGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var lastLowPowerState: Bool?

    public init() {}

    deinit {
        releaseAssertion()
    }

    public func setPreventSleep(_ prevent: Bool, reason: String) {
        lock.lock()
        defer { lock.unlock() }

        if prevent && !hasAssertion {
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
                hasAssertion = true
            }
        } else if !prevent && hasAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            hasAssertion = false
        }
    }

    public func setLowPowerMode(_ enabled: Bool) async {
        // Low Power Mode requires root; executed by voltguard-helper via SMCCommandState.
        lock.withLock {
            lastLowPowerState = enabled
        }
    }

    private func releaseAssertion() {
        lock.lock()
        defer { lock.unlock() }
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            hasAssertion = false
        }
    }
}
