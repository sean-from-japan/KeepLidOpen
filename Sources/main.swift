// KeepLidOpen: a menu bar app that keeps a MacBook on its external monitors
// with the lid open, and brings the built-in display back when they go away.
import AppKit
import CoreGraphics
import SwiftUI

let label = Bundle.main.bundleIdentifier ?? "io.github.sean-from-japan.KeepLidOpen"

final class Controller: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
    private let terminateSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    private let popover = NSPopover()
    private let model = PanelModel()
    private var lastBuiltInID: CGDirectDisplayID
    private var recoveryOwed: Bool
    // Starts empty so that launching with a monitor attached counts as connecting it.
    private var lastExternalKeys: Set<String> = []
    private var builtInWasOn: Bool?
    // "Just for now" switch: wins over the settings until the monitors change.
    private var temporary = false
    // Sleep and wake flip the panel by themselves; those flips are not the user's.
    private var ignoreFlipsUntil = Date.distantPast
    private var asleep = false
    private var misses = 0
    private var nextRestore = Date.distantPast
    private var lastSummary = ""
    private var lastSettings = ""
    private var lastIcon = ""

    private var autoOff: Bool {
        get { defaults.bool(forKey: "autoOffOnConnect") }
        set { defaults.set(newValue, forKey: "autoOffOnConnect") }
    }
    // Monitor key -> "off" | "on". A monitor without an entry follows autoOff.
    private var perDisplay: [String: String] {
        get { defaults.dictionary(forKey: "perDisplay") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "perDisplay") }
    }
    private var displayNames: [String: String] {
        get { defaults.dictionary(forKey: "displayNames") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "displayNames") }
    }
    private var cachedBuiltIn: CGDirectDisplayID? { lastBuiltInID != 0 ? lastBuiltInID : nil }

    override init() {
        defaults.register(defaults: ["autoOffOnConnect": true])
        lastBuiltInID = CGDirectDisplayID(defaults.integer(forKey: "lastBuiltInID"))
        recoveryOwed = defaults.bool(forKey: "recoveryOwed")
        super.init()
    }

    private func builtInShouldBeOn(_ s: Snapshot) -> Bool {
        KeepLidOpen.builtInShouldBeOn(connected: s.externalKeys, autoOff: autoOff, perDisplay: perDisplay)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.switchNow = { [weak self] in self?.switchNow() }
        model.setAutoOff = { [weak self] in self?.setAutoOff($0) }
        model.setChoice = { [weak self] in self?.setPerDisplay($0, $1) }
        model.close = { [weak self] in self?.popover.performClose(nil) }
        model.quit = { NSApp.terminate(nil) }
        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .applicationDefined
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        // launchctl bootout, kill and logout send SIGTERM, which would skip
        // applicationWillTerminate and could leave the built-in off with
        // nothing watching it.
        signal(SIGTERM, SIG_IGN)
        terminateSignal.setEventHandler { NSApp.terminate(nil) }
        terminateSignal.resume()

        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if !flags.contains(.beginConfigurationFlag) { DispatchQueue.main.async { controller.tick() } }
        }, nil)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                log(name.rawValue)
                self?.asleep = true
                self?.ignoreFlipsUntil = .distantFuture
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                log(name.rawValue)
                self?.asleep = false
                self?.ignoreFlipsUntil = Date().addingTimeInterval(8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.applyPolicy(reason: "wake") }
            }
        }

        timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        log(privateAPIAvailable ? "started" : "started, but the SkyLight symbols are missing; nothing can be switched")
    }

    // Opening the app again (Finder, Spotlight, Launchpad) shows its panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePanel() }
        return false
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            tick()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting must never leave a disabled panel with nothing watching it.
        let s = Snapshot()
        if !s.builtInOn, let id = s.builtIn ?? cachedBuiltIn {
            log("quit: enabling built-in \(setEnabled(id, true).rawValue)")
        }
    }

    func tick() {
        let s = Snapshot()
        if s.summary != lastSummary {
            log("displays: \(s.summary)")
            lastSummary = s.summary
        }
        if let id = s.builtIn, id != lastBuiltInID {
            lastBuiltInID = id
            defaults.set(Int(id), forKey: "lastBuiltInID")
        }
        // Also catches `defaults write` from the command line.
        let settings = "autoOffOnConnect=\(autoOff) perDisplay=\(perDisplay.sorted { $0.key < $1.key })"
        if settings != lastSettings {
            log(settings)
            let changed = !lastSettings.isEmpty
            lastSettings = settings
            if changed {
                temporary = false
                applyPolicy(reason: "setting")
                return
            }
        }

        if s.builtInOn {
            setRecoveryOwed(false)
        } else if s.builtIn != nil && !s.externals.isEmpty {
            setRecoveryOwed(true)
        }

        // Switches made from the panel, a Shortcut or another tool all show up here.
        let current: Bool? = s.builtIn == nil ? nil : s.builtInOn
        if !s.externals.isEmpty, let was = builtInWasOn, let now = current, was != now,
           Date() >= ignoreFlipsUntil {
            temporary = now != builtInShouldBeOn(s)
            log("built-in switched \(now ? "on" : "off") by hand; temporary=\(temporary)")
        }
        builtInWasOn = current

        let keys = Set(s.externalKeys)
        if keys != lastExternalKeys {
            var names = displayNames
            for (id, key) in zip(s.externals, s.externalKeys) { names[key] = name(of: id) }
            if names != displayNames { displayNames = names }
            log(keys.isEmpty ? "no monitor"
                : "monitors: " + s.externalKeys.map { "\(names[$0] ?? "?") \($0)" }.joined(separator: ", "))
            lastExternalKeys = keys
            temporary = false
            if !keys.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.applyPolicy(reason: "connect") }
            }
        }

        let recovery = RecoveryInput(builtInListed: s.builtIn != nil, builtInOn: s.builtInOn,
                                     hasMonitor: !s.externals.isEmpty, recoveryOwed: recoveryOwed,
                                     displaysAsleep: asleep, lidClosed: lidIsClosed())
        if needsRecovery(recovery) {
            misses += 1
            if misses >= 2, Date() >= nextRestore {
                misses = 0
                nextRestore = Date().addingTimeInterval(8)
                if restore() {
                    // A long-lived process once stopped seeing display changes
                    // after a recovery and a re-plug, while a fresh process read
                    // them correctly. A nonzero exit makes launchd start a new one.
                    log("restored; exiting so launchd starts a fresh process")
                    exit(75)
                }
            }
        } else {
            misses = 0
        }
        updateIcon(s)
        refreshPanel(s)
    }

    private func refreshPanel(_ s: Snapshot) {
        let names = displayNames
        let connected = s.externalKeys
        let keys = connected + perDisplay.keys.filter { !connected.contains($0) }.sorted()
        let monitors = keys.map {
            PanelModel.Monitor(id: $0, name: names[$0] ?? tr("不明なモニター", "Unknown monitor"),
                               connected: connected.contains($0), choice: perDisplay[$0] ?? "")
        }
        let externalNames = s.externals.map(name(of:))
        if model.builtInOn != s.builtInOn { model.builtInOn = s.builtInOn }
        if model.externalNames != externalNames { model.externalNames = externalNames }
        if model.temporary != temporary { model.temporary = temporary }
        if model.settingWantsOn != builtInShouldBeOn(s) { model.settingWantsOn = builtInShouldBeOn(s) }
        if model.autoOff != autoOff { model.autoOff = autoOff }
        if model.monitors != monitors { model.monitors = monitors }
    }

    private func setRecoveryOwed(_ owed: Bool) {
        guard owed != recoveryOwed else { return }
        recoveryOwed = owed
        defaults.set(owed, forKey: "recoveryOwed")
    }

    // Brings the built-in to what the settings ask for, unless "just for now" wins.
    private func applyPolicy(reason: String) {
        let s = Snapshot()
        guard !s.externals.isEmpty, !temporary else { return }
        let wantOn = builtInShouldBeOn(s)
        guard wantOn != s.builtInOn, let id = s.builtIn ?? cachedBuiltIn else { return }
        ignoreFlipsUntil = Date().addingTimeInterval(4)
        log("\(reason): built-in \(wantOn ? "on" : "off") \(setEnabled(id, wantOn).rawValue)")
        tick()
    }

    private func restore() -> Bool {
        log("restoring built-in")
        if let id = Snapshot().builtIn { setEnabled(id, true) }
        if builtInIsActive() { return true }
        // After the last monitor is unplugged the display list can be empty,
        // but the ID seen before the unplug still re-enables the panel.
        if let id = cachedBuiltIn { log("cached-ID enable: \(setEnabled(id, true).rawValue)") }
        sleep(1)
        if builtInIsActive() { return true }
        log("restoring permanent configuration")
        CGRestorePermanentDisplayConfiguration()
        sleep(1)
        return builtInIsActive()
    }

    private func updateIcon(_ s: Snapshot) {
        let symbol = s.builtInOn ? "laptopcomputer" : "laptopcomputer.slash"
        guard symbol != lastIcon, let button = statusItem.button else { return }
        lastIcon = symbol
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KeepLidOpen")
        image?.isTemplate = true
        button.image = image
        button.title = image == nil ? "KeepLidOpen" : ""
    }

    private func switchNow() {
        let s = Snapshot()
        guard !s.externals.isEmpty, let id = s.builtIn ?? cachedBuiltIn else { return }
        let turnOn = !s.builtInOn
        ignoreFlipsUntil = Date().addingTimeInterval(4)
        log("just for now: built-in \(turnOn ? "on" : "off") \(setEnabled(id, turnOn).rawValue)")
        temporary = turnOn != builtInShouldBeOn(s)
        tick()
    }

    private func setAutoOff(_ value: Bool) {
        guard value != autoOff else { return }
        autoOff = value
        temporary = false
        applyPolicy(reason: "setting")
        tick()
    }

    private func setPerDisplay(_ key: String, _ value: String) {
        var map = perDisplay
        map[key] = value.isEmpty ? nil : value
        perDisplay = map
        temporary = false
        applyPolicy(reason: "setting")
        tick()
    }
}

// Opened by hand, hand over to launchd so crash restarts and the exit after a
// recovery keep working, then leave. Without the agent, run on our own.
if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != label {
    let kickstart = Process()
    kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    kickstart.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
    if (try? kickstart.run()) != nil {
        kickstart.waitUntilExit()
        if kickstart.terminationStatus == 0 { exit(0) }
    }
    log("launchd agent \(label) not loaded; running without crash restart")
}

let controller = Controller()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = controller
app.run()
