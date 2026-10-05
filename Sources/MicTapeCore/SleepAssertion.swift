import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idle-sleeping while held, like `caffeinate -i`.
/// Closing the lid still sleeps the Mac.
public final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    private var held = false

    public init(reason: String) {
        held = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        ) == kIOReturnSuccess
    }

    public func release() {
        guard held else { return }
        IOPMAssertionRelease(id)
        held = false
    }

    deinit { release() }
}
