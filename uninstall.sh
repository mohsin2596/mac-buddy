#!/bin/sh
# Removes Mac Buddy, its hooks from Claude Code settings, and its state.
set -e

for app in "/Applications/MacBuddy.app" "$HOME/Applications/MacBuddy.app"; do
  if [ -x "$app/Contents/MacOS/MacBuddy" ]; then
    "$app/Contents/MacOS/MacBuddy" --disconnect || true
    break
  fi
done

pkill -x MacBuddy 2>/dev/null || true
rm -rf "/Applications/MacBuddy.app" "$HOME/Applications/MacBuddy.app" "$HOME/.mac-buddy"
echo "Mac Buddy removed."
