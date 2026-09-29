#!/bin/sh
# Builds KeepLidOpen, copies it to ~/Applications and starts it at every login
# through a launchd agent (which also restarts it after a crash).
set -eu
cd "$(dirname "$0")/.."
label=io.github.sean-from-japan.KeepLidOpen
app="$HOME/Applications/KeepLidOpen.app"
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

scripts/build.sh
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
# Stopping the running copy turns the built-in display back on first.
launchctl bootout "$domain/$label" 2>/dev/null || true
rm -rf "$app"
cp -R build/KeepLidOpen.app "$app"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array><string>$app/Contents/MacOS/KeepLidOpen</string></array>
    <key>RunAtLoad</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/KeepLidOpen.log</string>
</dict>
</plist>
PLIST
launchctl bootstrap "$domain" "$plist"
echo "installed $app; log: ~/Library/Logs/KeepLidOpen.log"
