import Foundation
import IOKit.pwr_mgt

enum PowerAssertionChecker {

    private static let mediaAssertionTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "PreventUserIdleSystemSleep"
    ]

    static func processHasMediaAssertion(pid: pid_t) -> Bool {
        var assertionsByProcess: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertionsByProcess)

        guard result == kIOReturnSuccess,
              let cfDict = assertionsByProcess?.takeRetainedValue() as NSDictionary? else {
            return false
        }

        let pidKey = NSNumber(value: pid)
        guard let assertions = cfDict[pidKey] as? [[String: Any]] else {
            return false
        }

        return assertions.contains { assertion in
            guard let type = assertion[kIOPMAssertionTypeKey] as? String,
                  let level = (assertion[kIOPMAssertionLevelKey] as? NSNumber)?.intValue else {
                return false
            }
            return level > 0 && mediaAssertionTypes.contains(type)
        }
    }
}
