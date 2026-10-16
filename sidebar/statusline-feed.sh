#!/bin/bash
# statusLine command for sessions running the sidebar mod.
#
# Claude Code hands the status line facts mods can't read (fast_mode, the
# prompt cache's real TTL, expiry and recache size, added dirs). This saves
# that JSON per session, where the mod reads it.
#
#   ~/.claude/state/statusline/<session_id>.json   (written atomically)
#
# -Then <program> passes the same input on to another status line program and
# prints what that prints, so the slot can be shared. Without -Then it prints
# nothing, so no status line is drawn under the prompt.
#
# In an Orca terminal (ORCA_PANE_KEY is set), the input also goes to Orca's
# own status line script when it's installed, as Orca's status line would do.
# It can't be named with -Then: Orca replaces a status line that names it.

FEED_DIR="$HOME/.claude/state/statusline"
ORCA_SCRIPT="$HOME/.orca/agent-hooks/claude-statusline.sh"

then_prog=
[ "$1" = "-Then" ] && then_prog=$2

input=$(cat)

sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
case "$sid" in
  ''|*/*|.*) sid= ;;
  *)
    mkdir -p "$FEED_DIR"
    printf '%s' "$input" > "$FEED_DIR/$sid.json.$$.tmp" && mv "$FEED_DIR/$sid.json.$$.tmp" "$FEED_DIR/$sid.json"
    ;;
esac

# The path with its folder resolved, to tell whether two paths are one file.
real_path() {
  d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) && printf '%s/%s' "$d" "$(basename "$1")"
}

# Orca's status line runs its script only when it's a readable, executable file.
to_orca=
if [ -n "$ORCA_PANE_KEY" ] && [ -f "$ORCA_SCRIPT" ] && [ -r "$ORCA_SCRIPT" ] && [ -x "$ORCA_SCRIPT" ]; then
  to_orca=1
  # -Then naming Orca's script already runs it.
  [ -n "$then_prog" ] && [ "$(real_path "$then_prog")" = "$(real_path "$ORCA_SCRIPT")" ] && to_orca=
fi

if [ -n "$then_prog" ]; then
  printf '%s' "$input" | "$then_prog"
fi

# What's shown is the -Then program's output when there is one, else Orca's.
if [ -n "$to_orca" ]; then
  if [ -n "$then_prog" ]; then
    printf '%s' "$input" | /bin/sh "$ORCA_SCRIPT" > /dev/null
  else
    printf '%s' "$input" | /bin/sh "$ORCA_SCRIPT"
  fi
fi

# Ended sessions leave their file behind; drop week-old ones now and then.
if [ -n "$sid" ] && [ $((RANDOM % 50)) -eq 0 ]; then
  find "$FEED_DIR" -name '*.json' -mtime +7 -delete 2>/dev/null
fi

exit 0
