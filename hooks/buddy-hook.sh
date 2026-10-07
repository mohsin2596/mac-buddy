#!/bin/sh
# Mac Buddy hook for Claude Code.
# Records the latest hook event of each session to ~/.mac-buddy/sessions/<id>.json,
# which the buddy app polls. Never prints anything, never blocks Claude.

dir="$HOME/.mac-buddy/sessions"
mkdir -p "$dir" || exit 0

# jq ships with macOS 15+; older systems usually have it from Homebrew.
JQ=$(command -v jq 2>/dev/null)
for p in /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
  [ -n "$JQ" ] && break
  [ -x "$p" ] && JQ="$p"
done
[ -n "$JQ" ] || exit 0

info=$("$JQ" -c '{
  event: .hook_event_name,
  tool: (.tool_name // ""),
  target: ((.tool_input.file_path // .tool_input.path // .tool_input.command
            // .tool_input.pattern // .tool_input.url // .tool_input.query
            // .tool_input.description // "") | tostring | .[0:120]),
  desc: ((.tool_input.description // "") | tostring | .[0:80]),
  cwd: (.cwd // ""),
  sid: (.session_id // "default")
}' 2>/dev/null) || exit 0

sid=$(printf '%s' "$info" | "$JQ" -r '.sid')
sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')
event=$(printf '%s' "$info" | "$JQ" -r '.event')

if [ "$event" = "SessionEnd" ]; then
  rm -f "$dir/$sid.json"
else
  printf '%s' "$info" > "$dir/$sid.json.tmp" && mv "$dir/$sid.json.tmp" "$dir/$sid.json"
fi
exit 0
