#!/usr/bin/env bash
# Regression net for ROADMAP Phase 5, "cleanup survives every death it can see".
#
# Its three acceptance points, each run against the code that ships:
#   1. a session killed with SIGHUP leaves no `tlauncher-mon-` process;
#   2. with a monitor held alive after its session died, `flock -n` on the lockfile
#      succeeds from another shell, so no child still holds fd 200;
#   3. a monitor killed mid-cycle leaves no temp file behind in $TMPDIR.
#
# WHY it loads run.sh instead of copying it: the functions under test (spawn_monitor,
# cleanup, kill_tree, the monitor preamble with first_seen_loop) & the `trap` line are
# taken from run.sh itself, everything but its last line, `main "$@"`. Loading it has
# no side effect beyond defining them, checked with every XDG path pointed into a
# scratch dir. So a change to any of them is tested as shipped, with no copy to drift.
# The monitor body is a stub: no firejail, no TLauncher, no network, no sudo.
#
# What check 1 can't tell on bash 5.2.21: there the EXIT trap already runs on an
# untrapped HUP, so it passes even with HUP dropped from run.sh's trap line (tried on
# 2026-10-01). It proves the outcome, no monitor survives a HUP, & guards the HUP in
# the trap only on a bash that skips the EXIT trap for it. Check 2 does fail without
# `200>&-` in spawn_monitor, & check 3 without the per-loop scratch path; both were
# tried the same day.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"

WORK="$(mktemp -d)"
LIB="${WORK}/run-lib.sh"
head -n -1 "$REPO/run.sh" > "$LIB"
mkdir -p "${WORK}/run" "${WORK}/tmp"

pass=0
total=0
failed=()
check() { # check NAME OK DETAIL
    total=$((total + 1))
    if [ "$2" = true ]; then
        pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
    else
        printf 'FAIL  %s (%s)\n' "$1" "$3"; failed+=("$1")
    fi
}

# Every session gets its own id, so the pgrep patterns below can't match each other
# or anything outside this test.
SID_BASE="cstest$$"
# Every process this test starts carries SID_BASE in its command line: monitors via
# their tlauncher-mon- tag, sessions & the firejail stand-in via their arguments.
reap() { pkill -KILL -f "${SID_BASE}" 2>/dev/null || true; }
trap 'reap; [ -n "${KEEP_WORK:-}" ] || rm -rf "$WORK"' EXIT

# A session the way run_sandboxed starts one: take the lock on fd 200, export the
# session vars, spawn a monitor whose body is a first_seen_loop over a stub producer
# that spends most of each cycle inside the producer, then wait to be killed.
session() { # session SID
    # exec, so the PID the caller holds is the session shell itself & a signal sent to
    # it reaches run.sh's trap, not a wrapper subshell.
    exec env -i PATH="$PATH" HOME="${WORK}/home" USER=cstest \
        XDG_DATA_HOME="${WORK}/data" XDG_STATE_HOME="${WORK}/state" \
        XDG_RUNTIME_DIR="${WORK}/run" TMPDIR="${WORK}/tmp" \
        bash -c '
            source "$1"
            SESSION_ID="$2"; SESSION_DIR="$3"; VERBOSE=false
            mkdir -p "$SESSION_DIR"
            export SESSION_ID SESSION_DIR
            exec 200>"$LOCKFILE"
            flock -n 200 || exit 9
            spawn_monitor stub '"'"'first_seen_loop "$SESSION_DIR/stub.log" "$SESSION_DIR/.seen_stub" "sleep 0.4; echo tick" 0.1'"'"'
            printf "ready\n"
            # The stand-in for firejail closes fd 200 the way run_sandboxed launches it.
            bash -c "sleep 60" "fj-$SESSION_ID" 200>&- &
            wait $!
        ' _ "$LIB" "$1" "${WORK}/$1"
}

wait_for() { # wait_for SECONDS COMMAND...: poll until COMMAND succeeds
    local i n=$(( $1 * 10 )); shift
    for ((i = 0; i < n; i++)); do "$@" && return 0; sleep 0.1; done
    return 1
}
mon_alive() { pgrep -f "tlauncher-mon-$1" >/dev/null 2>&1; }

printf -- '--- 1. SIGHUP runs cleanup & reaps the monitors ---\n'
SID1="${SID_BASE}hup"
session "$SID1" > "${WORK}/s1.out" 2>&1 &
S1=$!
wait_for 5 mon_alive "$SID1"; started=$?
kill -HUP "$S1" 2>/dev/null
wait "$S1" 2>/dev/null
sleep 0.5
if [ "$started" -ne 0 ]; then
    check "SIGHUP leaves no tlauncher-mon- process" false "the stub monitor never started"
elif mon_alive "$SID1"; then
    check "SIGHUP leaves no tlauncher-mon- process" false "still alive: $(pgrep -f "tlauncher-mon-$SID1" | tr '\n' ' ')"
else
    check "SIGHUP leaves no tlauncher-mon- process" true ""
fi
# cleanup() also removes first_seen_loop's per-loop scratch file from the session dir.
[ -z "$(find "${WORK}/${SID1}" -name '.seen_*.cur' 2>/dev/null)" ] \
    && check "cleanup removes the monitor's scratch file" true "" \
    || check "cleanup removes the monitor's scratch file" false "a .seen_*.cur survived in the session dir"

printf -- '--- 2. an orphaned monitor does not hold the lock ---\n'
SID2="${SID_BASE}lock"
session "$SID2" > "${WORK}/s2.out" 2>&1 &
S2=$!
wait_for 5 mon_alive "$SID2"
# SIGKILL can't be trapped, so cleanup never runs & the monitor is orphaned: the case
# where an inherited fd 200 would keep the session lock held after its owner died.
kill -KILL "$S2" 2>/dev/null
wait "$S2" 2>/dev/null
sleep 0.3
if ! mon_alive "$SID2"; then
    check "flock -n succeeds while an orphaned monitor lives" false "no orphan to test against"
elif flock -n "${WORK}/run/tlauncher-cstest.lock" true; then
    check "flock -n succeeds while an orphaned monitor lives" true ""
else
    check "flock -n succeeds while an orphaned monitor lives" false "lock still held with the orphan alive"
fi
reap

printf -- '--- 3. a monitor killed mid-cycle leaves no temp file ---\n'
# The stub producer sleeps 0.4 s of every 0.5 s cycle, so KILL lands mid-cycle. Five
# sessions, each killed the same way; every temp file first_seen_loop could leave
# would land in this TMPDIR.
for n in 1 2 3 4 5; do
    sid="${SID_BASE}tmp${n}"
    session "$sid" > /dev/null 2>&1 &
    s=$!
    wait_for 5 mon_alive "$sid"
    sleep 0.7
    pkill -KILL -f "tlauncher-mon-${sid}" 2>/dev/null
    kill -KILL "$s" 2>/dev/null
    wait "$s" 2>/dev/null
done
reap
left="$(find "${WORK}/tmp" -mindepth 1 2>/dev/null | wc -l)"
[ "$left" -eq 0 ] \
    && check "a killed monitor leaves nothing in TMPDIR" true "" \
    || check "a killed monitor leaves nothing in TMPDIR" false "$left file(s) left in TMPDIR"

printf -- '----\n%d/%d cleanup-signals checks verified\n' "$pass" "$total"
if [ "$pass" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
