#!/usr/bin/env bash
# Regression net for the colour gate, docs/cli/cli-standard.md, section 4, rule 3.
#
# Each stream gets colour only when it is a terminal & NO_COLOR is unset or empty.
# A test has no terminal of its own, so `script` (util-linux) gives run.sh a pseudo-
# terminal & each case sends one stream somewhere else. Until v2.57 a single gate on
# stdout coloured both streams: case 2 wrote escape codes into a file & case 3 lost
# the colour of errors a person was looking at.
#
# WHY --bogus & --help: the first writes only to stderr, the second only to stdout, &
# neither launches anything. No network, no sudo, no TLauncher.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"
RUN="$REPO/run.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; total=0; skipped=0; failed=()
check() { # check NAME OK DETAIL
    total=$((total + 1))
    if [ "$2" = true ]; then
        pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
    else
        printf 'FAIL  %s (%s)\n' "$1" "$3"; failed+=("$1")
    fi
}
skip() { # skip NAME WHY
    total=$((total + 1)); skipped=$((skipped + 1))
    printf 'SKIP  %s (%s)\n' "$1" "$2"
}

ESC=$'\033'
has_esc() { case "$1" in *"$ESC"*) return 0 ;; *) return 1 ;; esac; }

# pty CMD: run CMD under a pseudo-terminal & print what reached that terminal.
pty() { script -qec "$1" /dev/null 2>/dev/null; }

if ! command -v script >/dev/null 2>&1; then
    skip "colour gate" "script(1) is not installed; NOT verified here"
    printf -- '----\n0/%d colour-gate checks verified (%d skipped, not verified)\n' "$total" "$skipped"
    exit 0
fi

printf -- '--- 1. stderr ---\n'
out="$(pty "bash '$RUN' --bogus")"
has_esc "$out" && check "stderr on a terminal is coloured" true "" \
    || check "stderr on a terminal is coloured" false "no escape code in: ${out:0:60}"

pty "bash '$RUN' --bogus 2>'$WORK/err'" >/dev/null
err="$(cat "$WORK/err" 2>/dev/null)"
{ grep -qF "Unknown option" <<< "$err" && ! has_esc "$err"; } \
    && check "stderr sent to a file has no colour, with stdout on a terminal" true "" \
    || check "stderr sent to a file has no colour, with stdout on a terminal" false "file: ${err:0:60}"

out="$(pty "bash '$RUN' --bogus >/dev/null")"
has_esc "$out" && check "stderr keeps its colour when stdout is not a terminal" true "" \
    || check "stderr keeps its colour when stdout is not a terminal" false "no escape code in: ${out:0:60}"

printf -- '--- 2. stdout ---\n'
out="$(pty "bash '$RUN' --help")"
has_esc "$out" && check "stdout on a terminal is coloured" true "" \
    || check "stdout on a terminal is coloured" false "no escape code in --help"

pty "bash '$RUN' --help >'$WORK/out'" >/dev/null
help_file="$(cat "$WORK/out" 2>/dev/null)"
{ grep -qF "USAGE" <<< "$help_file" && ! has_esc "$help_file"; } \
    && check "stdout sent to a file has no colour" true "" \
    || check "stdout sent to a file has no colour" false "file: ${help_file:0:60}"

printf -- '--- 3. NO_COLOR ---\n'
out="$(NO_COLOR=1 pty "bash '$RUN' --help; bash '$RUN' --bogus")"
{ grep -qF "Unknown option" <<< "$out" && ! has_esc "$out"; } \
    && check "NO_COLOR=1 turns colour off on both streams" true "" \
    || check "NO_COLOR=1 turns colour off on both streams" false "escape code present"

out="$(NO_COLOR='' pty "bash '$RUN' --bogus")"
has_esc "$out" && check "an empty NO_COLOR counts as unset" true "" \
    || check "an empty NO_COLOR counts as unset" false "no escape code with NO_COLOR=''"

printf -- '----\n%d/%d colour-gate checks verified\n' "$pass" "$total"
if [ "$pass" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
