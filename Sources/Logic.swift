// Decisions that do not touch the display system, so they can be tested.

/// What a monitor asks the built-in display to do.
enum Policy: String {
    case off, on
}

/// Vendor numbers that do not belong to a physical monitor.
///
/// When the last monitor is unplugged or powered off, macOS can keep a
/// placeholder display active. On a MacBook Air (M5) with macOS 26.6.2 it
/// reported vendor 0x756E6B6E ("unkn") and model 0x76697274 ("virt").
/// Counting it as a monitor keeps the built-in off and the Mac black.
let placeholderVendors: Set<UInt32> = [0, 0xFFFF_FFFF, 0x756E_6B6E]

func isMonitor(vendor: UInt32) -> Bool {
    !placeholderVendors.contains(vendor)
}

/// Whether the built-in display should be on while these monitors are connected.
///
/// `perDisplay` maps a monitor key to "off" or "on"; a monitor without an entry
/// follows `autoOff`. With several monitors, one that keeps the built-in on wins.
func builtInShouldBeOn(connected keys: [String], autoOff: Bool, perDisplay: [String: String]) -> Bool {
    let fallback: Policy = autoOff ? .off : .on
    return keys.isEmpty || keys.contains { (perDisplay[$0].flatMap(Policy.init(rawValue:)) ?? fallback) == .on }
}

struct RecoveryInput {
    /// The built-in appears in the private display list (a disabled built-in
    /// stays listed while a monitor is attached).
    var builtInListed: Bool
    var builtInOn: Bool
    var hasMonitor: Bool
    /// The built-in was seen disabled while a monitor was attached.
    var recoveryOwed: Bool
    var displaysAsleep: Bool
    var lidClosed: Bool
}

/// Whether the built-in display must be switched back on now.
func needsRecovery(_ state: RecoveryInput) -> Bool {
    // Display sleep makes monitors inactive; that is not an unplug.
    guard !state.displaysAsleep, !state.builtInOn, !state.lidClosed else { return false }
    if !state.hasMonitor && (state.builtInListed || state.recoveryOwed) { return true }
    // The built-in vanished although we switched it off: recover even if
    // something still looks like a monitor, so a misjudged placeholder can
    // never keep the screen black.
    return !state.builtInListed && state.recoveryOwed
}
