#!/bin/sh
# Stops KeepLidOpen (which turns the built-in display back on) and removes it.
set -eu
label=io.github.sean-from-japan.KeepLidOpen
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$HOME/Applications/KeepLidOpen.app"
echo "removed. Settings remain in 'defaults read $label'; delete them with 'defaults delete $label'."
