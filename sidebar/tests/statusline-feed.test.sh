#!/bin/bash
# Tests for statusline-feed.sh (macOS and Linux). Needs bash 3.2 or later
# and jq, the same as the feed. Run from anywhere:
#
#   bash sidebar/tests/statusline-feed.test.sh
#
# Each case runs the real feed with HOME pointed at a scratch folder holding
# stand-ins for Orca's status line script and a -Then program, which log what
# they're given. Nothing outside the scratch folder is touched.

FEED="$(cd "$(dirname "$0")/.." && pwd)/statusline-feed.sh"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/feed-test.XXXXXX") || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

failures=0
cases=0
INPUT='{"session_id":"test-session","rate_limits":{"five_hour":{"used_percentage":1}},"model":{"id":"x"}}'

fail() { echo "  FAIL: $1"; failures=$((failures + 1)); }

# stand_in <path> <log> <prints> [exit code]: a program that appends its
# stdin to <log>, then a "--" line, prints <prints> and exits.
stand_in() {
  printf '#!/bin/sh\ncat >> "%s"\nprintf "\\n--\\n" >> "%s"\necho %s\nexit %s\n' "$2" "$2" "$3" "${4:-0}" > "$1"
  chmod +x "$1"
}

# A fresh HOME with a stand-in for Orca's script, and a -Then program.
setup() {
  T="$SCRATCH/case$cases"
  mkdir -p "$T/home/.orca/agent-hooks" "$T/bin"
  ORCA="$T/home/.orca/agent-hooks/claude-statusline.sh"
  stand_in "$ORCA" "$T/orca.log" ORCA-OUT
  OTHER="$T/bin/other-statusline"
  stand_in "$OTHER" "$T/then.log" THEN-OUT
}

# run <stdin> [env assignments...] -- [feed args...]
run() {
  input=$1; shift
  envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "$1" = "--" ] && shift
  OUT=$(printf '%s' "$input" | env -u ORCA_PANE_KEY HOME="$T/home" ${envs[@]+"${envs[@]}"} bash "$FEED" "$@")
  CODE=$?
}

calls() { [ -f "$1" ] && grep -c '^--$' "$1" || echo 0; }
saved() { cat "$T/home/.claude/state/statusline/test-session.json" 2>/dev/null; }

check() {
  # check <name> <expected out> <expected orca calls> <expected then calls> <expect saved: yes|no>
  [ "$CODE" = 0 ] || fail "$1: exit code $CODE, expected 0"
  [ "$OUT" = "$2" ] || fail "$1: printed '$OUT', expected '$2'"
  [ "$(calls "$T/orca.log")" = "$3" ] || fail "$1: Orca's script ran $(calls "$T/orca.log") times, expected $3"
  [ "$(calls "$T/then.log")" = "$4" ] || fail "$1: the -Then program ran $(calls "$T/then.log") times, expected $4"
  if [ "$5" = yes ]; then
    [ "$(saved)" = "$INPUT" ] || fail "$1: the saved file doesn't match the input"
  else
    [ -z "$(ls "$T/home/.claude/state/statusline" 2>/dev/null)" ] || fail "$1: a file was saved, expected none"
  fi
  if [ "$3" != 0 ]; then
    [ "$(sed -n 1p "$T/orca.log" 2>/dev/null)" = "$INPUT" ] || fail "$1: Orca's script was given different input"
  fi
  if [ "$4" != 0 ]; then
    [ "$(sed -n 1p "$T/then.log" 2>/dev/null)" = "$INPUT" ] || fail "$1: the -Then program was given different input"
  fi
}

t() { cases=$((cases + 1)); echo "$cases. $1"; setup; }

t "outside Orca: saves, prints nothing, Orca not run"
run "$INPUT" --
check "outside Orca" "" 0 0 yes

t "in an Orca terminal: saves, then hands the input to Orca's script"
run "$INPUT" ORCA_PANE_KEY=tab1:1 --
check "in Orca" "ORCA-OUT" 1 0 yes

t "in an Orca terminal, Orca's script missing: saves, nothing else"
rm -f "$ORCA"
run "$INPUT" ORCA_PANE_KEY=tab1:1 --
check "no Orca script" "" 0 0 yes

t "in an Orca terminal, Orca's script not executable: not run (Orca's own line needs that too)"
chmod -x "$ORCA"
run "$INPUT" ORCA_PANE_KEY=tab1:1 --
check "Orca script not executable" "" 0 0 yes

t "an empty ORCA_PANE_KEY counts as outside Orca"
run "$INPUT" ORCA_PANE_KEY= --
check "empty pane key" "" 0 0 yes

t "-Then outside Orca: saves, runs the program, prints what it prints"
run "$INPUT" -- -Then "$OTHER"
check "-Then outside Orca" "THEN-OUT" 0 1 yes

t "-Then in an Orca terminal: both run once, the -Then program's output is shown"
run "$INPUT" ORCA_PANE_KEY=tab1:1 -- -Then "$OTHER"
check "-Then in Orca" "THEN-OUT" 1 1 yes

t "-Then naming Orca's script, in an Orca terminal: Orca's script runs once, not twice"
run "$INPUT" ORCA_PANE_KEY=tab1:1 -- -Then "$ORCA"
check "-Then is Orca" "ORCA-OUT" 1 0 yes

t "-Then naming Orca's script by another spelling of the path: still once"
run "$INPUT" ORCA_PANE_KEY=tab1:1 -- -Then "$T/home/.orca/./agent-hooks/../agent-hooks/claude-statusline.sh"
check "-Then is Orca, odd path" "ORCA-OUT" 1 0 yes

t "a -Then program that fails: the feed still exits 0"
stand_in "$OTHER" "$T/then.log" THEN-OUT 3
run "$INPUT" -- -Then "$OTHER"
check "-Then fails" "THEN-OUT" 0 1 yes

t "a -Then program that doesn't exist: the feed still saves and exits 0"
run "$INPUT" -- -Then "$T/bin/no-such-program"
check "-Then missing" "" 0 0 yes

t "a bad session id: nothing saved, but the input still goes to Orca and -Then"
BAD='{"session_id":"../escape","rate_limits":{}}'
run "$BAD" ORCA_PANE_KEY=tab1:1 -- -Then "$OTHER"
[ "$CODE" = 0 ] || fail "bad id: exit code $CODE"
[ -z "$(ls "$T/home/.claude/state/statusline" 2>/dev/null)" ] || fail "bad id: a file was saved"
[ "$(calls "$T/orca.log")" = 1 ] || fail "bad id: Orca's script ran $(calls "$T/orca.log") times, expected 1"
[ "$(calls "$T/then.log")" = 1 ] || fail "bad id: the -Then program ran $(calls "$T/then.log") times, expected 1"
[ "$OUT" = "THEN-OUT" ] || fail "bad id: printed '$OUT'"

t "input that isn't JSON: nothing saved, exits 0"
run "not json" --
[ "$CODE" = 0 ] || fail "not JSON: exit code $CODE"
[ -z "$(ls "$T/home/.claude/state/statusline" 2>/dev/null)" ] || fail "not JSON: a file was saved"

echo
if [ "$failures" = 0 ]; then
  echo "All $cases cases passed (bash $BASH_VERSION)."
else
  echo "$failures check(s) failed across $cases cases (bash $BASH_VERSION)."
  exit 1
fi
