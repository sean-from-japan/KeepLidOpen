// Tests for Sources/Logic.swift. Run with scripts/test.sh.
// A plain executable, so it builds with the Command Line Tools alone.
import Foundation

var failures = 0
func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if condition {
        print("ok   \(name)")
    } else {
        print("FAIL \(name) (line \(line))")
        failures += 1
    }
}

// MARK: - Placeholder displays

check(!isMonitor(vendor: 0x756E_6B6E), "placeholder vendor \"unkn\" is not a monitor")
check(!isMonitor(vendor: 0xFFFF_FFFF), "unknown vendor is not a monitor")
check(!isMonitor(vendor: 0), "vendor 0 is not a monitor")
check(isMonitor(vendor: 0x10AC), "Dell (0x10AC) is a monitor")
check(isMonitor(vendor: 0x0610), "Apple (0x0610) is a monitor")

// MARK: - Settings

check(builtInShouldBeOn(connected: [], autoOff: true, perDisplay: [:]),
      "no monitor: built-in on")
check(!builtInShouldBeOn(connected: ["dell"], autoOff: true, perDisplay: [:]),
      "global off: built-in off")
check(builtInShouldBeOn(connected: ["dell"], autoOff: false, perDisplay: [:]),
      "global on: built-in on")
check(builtInShouldBeOn(connected: ["dell"], autoOff: true, perDisplay: ["dell": "on"]),
      "per-monitor on beats global off")
check(!builtInShouldBeOn(connected: ["dell"], autoOff: false, perDisplay: ["dell": "off"]),
      "per-monitor off beats global on")
check(builtInShouldBeOn(connected: ["dell", "projector"], autoOff: true, perDisplay: ["projector": "on"]),
      "any monitor that keeps the built-in on wins")
check(!builtInShouldBeOn(connected: ["dell"], autoOff: true, perDisplay: ["projector": "on"]),
      "a setting for a disconnected monitor does not apply")
check(!builtInShouldBeOn(connected: ["dell"], autoOff: true, perDisplay: ["dell": "bogus"]),
      "an unknown value falls back to the global setting")

// MARK: - Recovery, from situations measured on real hardware

func state(listed: Bool = true, on: Bool = false, monitor: Bool = false, owed: Bool = true,
           asleep: Bool = false, lid: Bool = false) -> RecoveryInput {
    RecoveryInput(builtInListed: listed, builtInOn: on, hasMonitor: monitor, recoveryOwed: owed,
                  displaysAsleep: asleep, lidClosed: lid)
}

check(needsRecovery(state(listed: false, monitor: false)),
      "unplug: display list became empty")
check(needsRecovery(state(listed: false, monitor: true)),
      "built-in vanished while a misjudged placeholder looks like a monitor")
check(needsRecovery(state(listed: true, monitor: false, owed: false)),
      "listed but off with no monitor, even if nothing was owed")
check(!needsRecovery(state(listed: true, monitor: true)),
      "switched off on purpose with a monitor attached")
check(!needsRecovery(state(listed: false, monitor: false, asleep: true)),
      "display sleep makes the monitor inactive; not an unplug")
check(!needsRecovery(state(listed: false, monitor: false, lid: true)),
      "lid closed (clamshell)")
check(!needsRecovery(state(on: true)),
      "built-in already on")
check(!needsRecovery(state(listed: false, monitor: false, owed: false)),
      "built-in absent and never switched off by us")

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
