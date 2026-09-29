# What the display system actually did

Measured while building KeepLidOpen, September 2026, on one machine:
MacBook Air (M5), macOS 26.6.2, one Dell S2725DSM monitor. Other Macs,
macOS versions, monitors and docks may behave differently. Each entry says what
was observed, how, and what KeepLidOpen does about it.

The log lines below are from KeepLidOpen's own log
(`~/Library/Logs/KeepLidOpen.log`), which records every display in
`CGSGetDisplayList` on each change: `#<id><b|e>` (built-in or external),
`active`, `online`, and the vendor and model numbers in hex.

## 1. After an unplug, the display list can be empty

With the built-in disabled and the monitor unplugged, `CGSGetDisplayList`
returned **zero displays**, or only a placeholder (see 2). The disabled built-in
was no longer listed, so a tool that looks up the built-in's ID in the list
before re-enabling it has nothing to work with. MacDisplay's `on` exited with
"Built-in display is not enumerated (lid closed / clamshell?)" although the lid
was open.

Re-enabling the **ID cached before the unplug** worked every time it was tried
(four unplug or power-off events):

```
no monitor
restoring built-in
cached-ID enable: 0
```

`0` is `kCGErrorSuccess`, and the panel lit up. Some tools avoid stored IDs
because re-enabling a stale ID has left panels undetectable elsewhere
(DisplayDeck issue #1); here the ID stayed `1` across every event. KeepLidOpen
tries the listed ID first, then the cached one, then
`CGRestorePermanentDisplayConfiguration`.

## 2. A placeholder display stays active when the last monitor goes away

Unplugging the monitor, or powering it off with the cable connected, left one
active, online display that is not a monitor:

```
displays: #11e active=1 online=1 vendor=756e6b6e model=76697274
```

The vendor reads "unkn" in ASCII and the model "virt". It got a new ID each
time (`#9`, `#10`, `#11`, `#12`). Counting it as an external monitor means
"a monitor is still connected, keep the built-in off", and the Mac stays black.

An early version of KeepLidOpen filtered out vendor `0xFFFFFFFF` only (a guess,
not a measurement) and failed exactly this way. Now vendor 0, `0xFFFFFFFF` and
"unkn" are ignored, and independently of that filter the built-in is recovered
whenever it has vanished from the list after KeepLidOpen switched it off.

## 3. Display sleep makes the monitor inactive, not absent

During display sleep the monitor stayed online but inactive:

```
displays: #3e active=0 online=1 vendor=10ac ... #1b active=0 online=0 vendor=610 ...
```

A watcher that treats "no active monitor" as an unplug will switch the built-in
on during every display sleep. KeepLidOpen does not recover while the displays
sleep (`NSWorkspace.screensDidSleepNotification` / `willSleepNotification`) and
reapplies the settings 3 s after they wake.

## 4. A long-running process stopped seeing changes

A first watcher looped with `sleep()` and no run loop. After it had recovered the
built-in once and the monitor was plugged back in, it kept reporting the old
state for minutes, while a freshly started process (`launchctl kickstart -k`)
read the current state immediately. A probe that only toggled the built-in did
**not** reproduce this, so the trigger is probably the re-plug; the exact cause
is not confirmed.

KeepLidOpen runs an `NSApplication` run loop with
`CGDisplayRegisterReconfigurationCallback`, and exits after each successful
recovery so that launchd starts a fresh process.

## 5. SIGTERM skips the normal quit path

`launchctl bootout`, `kill` and logout send SIGTERM, which ends an AppKit app
without calling `applicationWillTerminate`. If the built-in was off, it stayed
off with nothing left to bring it back on the next unplug. KeepLidOpen turns
SIGTERM into a normal quit, which re-enables the built-in first (verified with
`kill -TERM` and `launchctl kickstart -k`).

## 6. Disabled "for session", enabled "permanently"

`CGCompleteDisplayConfiguration(config, .permanently)` after disabling the
built-in would store the disabled state as the permanent configuration, which
turns `CGRestorePermanentDisplayConfiguration` from a rescue into a trap.
KeepLidOpen completes "off" with `.forSession` and "on" with `.permanently`, so
logging out also brings the panel back.

## Not measured

- Wake from system sleep with the built-in off. BetterDisplay users report that
  macOS turns the built-in back on after wake (BetterDisplay discussion #3779);
  KeepLidOpen reapplies its settings after wake, but that path has not been
  checked by hand on this machine.
- Intel Macs, base M3 (where another tool reports a WindowServer hang when
  re-enabling), docks, DisplayLink, AirPlay and Sidecar displays.
