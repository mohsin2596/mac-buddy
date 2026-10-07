#!/bin/sh
# Removes Mac Buddy, its hooks from Claude Code settings, and its state.
set -e

pkill -x MacBuddy 2>/dev/null || true
rm -rf "$HOME/Applications/MacBuddy.app"

JQ=$(command -v jq 2>/dev/null || echo /usr/bin/jq)
SETTINGS="$HOME/.claude/settings.json"
CMD="/bin/sh \"$HOME/.mac-buddy/hook.sh\""
if [ -f "$SETTINGS" ]; then
  tmp=$(mktemp)
  "$JQ" --arg cmd "$CMD" '
    if .hooks then
      .hooks |= (map_values(map(.hooks |= map(select(.command != $cmd))) | map(select(.hooks | length > 0)))
                 | with_entries(select(.value | length > 0)))
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
fi

rm -rf "$HOME/.mac-buddy"
echo "Mac Buddy removed."
