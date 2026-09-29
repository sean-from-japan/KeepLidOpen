// Reading and switching displays. The disconnect uses two private SkyLight
// symbols, resolved at runtime; there is no public API for it.
import AppKit
import CoreGraphics
import IOKit

private typealias GetDisplayList = @convention(c)
    (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
private typealias ConfigureEnabled = @convention(c)
    (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

private let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
private let getDisplayList: GetDisplayList? = {
    guard let skyLight, let symbol = dlsym(skyLight, "CGSGetDisplayList") else { return nil }
    return unsafeBitCast(symbol, to: GetDisplayList.self)
}()
private let configureEnabled: ConfigureEnabled? = {
    guard let skyLight, let symbol = dlsym(skyLight, "CGSConfigureDisplayEnabled") else { return nil }
    return unsafeBitCast(symbol, to: ConfigureEnabled.self)
}()

let privateAPIAvailable = getDisplayList != nil && configureEnabled != nil

private let stamp = ISO8601DateFormatter()
func log(_ message: String) {
    fputs("\(stamp.string(from: Date())) \(message)\n", stderr)
}

// Unlike the public lists, this still includes a software-disabled display.
private func displayIDs() -> [CGDirectDisplayID] {
    guard let getDisplayList else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: 64)
    var count: UInt32 = 0
    guard getDisplayList(UInt32(ids.count), &ids, &count) == .success, count <= ids.count else { return [] }
    return Array(ids.prefix(Int(count)))
}

// Stable across reconnects, unlike the display ID.
private func key(of id: CGDirectDisplayID) -> String {
    if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
       let string = CFUUIDCreateString(nil, uuid) {
        return string as String
    }
    return "edid-\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
}

func lidIsClosed() -> Bool {
    guard let matching = IOServiceMatching("IOPMrootDomain") else { return false }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                 kCFAllocatorDefault, 0)?.takeRetainedValue()
    return (value as? Bool) == true
}

func builtInIsActive() -> Bool {
    var ids = [CGDirectDisplayID](repeating: 0, count: 64)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return false }
    return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
}

func name(of id: CGDirectDisplayID) -> String {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
    return screen?.localizedName ?? "Display \(id)"
}

@discardableResult
func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> CGError {
    guard let configureEnabled else { return .failure }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { return .failure }
    let result = configureEnabled(config, id, enabled)
    guard result == .success else {
        CGCancelDisplayConfiguration(config)
        return result
    }
    // Off lasts for this login session only, so logging out or restoring the
    // permanent configuration always brings the panel back.
    return CGCompleteDisplayConfiguration(config, enabled ? .permanently : .forSession)
}

struct Snapshot {
    let builtIn: CGDirectDisplayID?
    let builtInOn: Bool
    let externals: [CGDirectDisplayID]
    let externalKeys: [String]
    let summary: String

    init() {
        let ids = displayIDs()
        builtIn = ids.first { CGDisplayIsBuiltin($0) != 0 }
        builtInOn = builtIn.map { CGDisplayIsOnline($0) != 0 } ?? false
        externals = ids.filter {
            CGDisplayIsBuiltin($0) == 0 && isMonitor(vendor: CGDisplayVendorNumber($0)) && CGDisplayIsActive($0) != 0
        }
        externalKeys = externals.map(key(of:))
        summary = ids.map { id in
            "#\(id)\(CGDisplayIsBuiltin(id) != 0 ? "b" : "e") active=\(CGDisplayIsActive(id))"
                + " online=\(CGDisplayIsOnline(id)) vendor=\(String(CGDisplayVendorNumber(id), radix: 16))"
                + " model=\(String(CGDisplayModelNumber(id), radix: 16))"
        }.joined(separator: " ")
    }
}
