#!/bin/sh
# Builds Mac Buddy, installs it to ~/Applications, wires up Claude Code hooks, and launches it.
set -e
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift is required. Install the Xcode Command Line Tools:  xcode-select --install" >&2
  exit 1
fi
JQ=$(command -v jq 2>/dev/null || true)
if [ -z "$JQ" ]; then
  echo "jq is required (built into macOS 15+). Install it with:  brew install jq" >&2
  exit 1
fi

./build.sh

# App
mkdir -p "$HOME/Applications"
pkill -x MacBuddy 2>/dev/null || true
rm -rf "$HOME/Applications/MacBuddy.app"
cp -R build/MacBuddy.app "$HOME/Applications/"

# Hook script
mkdir -p "$HOME/.mac-buddy/sessions"
cp hooks/buddy-hook.sh "$HOME/.mac-buddy/hook.sh"
chmod +x "$HOME/.mac-buddy/hook.sh"

# Claude Code settings (merged, existing hooks kept)
SETTINGS="$HOME/.claude/settings.json"
CMD="/bin/sh \"$HOME/.mac-buddy/hook.sh\""
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-macbuddy"

"$JQ" --arg cmd "$CMD" '
  .hooks //= {} |
  reduce ("UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
          "PermissionRequest", "Stop", "SessionStart", "SessionEnd") as $e (.;
    if any(.hooks[$e][]?.hooks[]?; .command == $cmd) then .
    else .hooks[$e] += [{"matcher": "", "hooks": [{"type": "command", "command": $cmd, "timeout": 5}]}]
    end)
' "$SETTINGS.bak-macbuddy" > "$SETTINGS"

echo "Hooks added to $SETTINGS (backup: $SETTINGS.bak-macbuddy)"
open "$HOME/Applications/MacBuddy.app"
echo "Mac Buddy is running. Right-click it for options, or open it again for Settings."
