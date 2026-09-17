#!/usr/bin/env bash
# Regression net for the lockfile's mutual exclusion (ROADMAP Phase 5 follow-up).
#
# The bug this exists to catch: cleanup() used to `rm -f "$LOCKFILE"`, & die() calls
# cleanup(). So the instance that LOST the race deleted the lockfile belonging to the
# instance that HELD it. flock(2) lives on the open file description, not on the path,
# so the holder kept its lock over an unlinked inode while the path went free; a third
# instance then created a fresh inode, locked it without contest, & ran in parallel
# with the first. Mutual exclusion was gone in exactly the case it exists for.
#
# WHY a standalone harness & not `run.sh` itself: run.sh reaches the lock only after
# building a firejail sandbox, which this environment has no way to do. The harness
# below reproduces run.sh's lock protocol verbatim (the exec-fd + flock -n + die path),
# so it tests the protocol that ships. The guard that makes it a real regression test
# is check 4: it asserts the lockfile is still the SAME inode after a rejection, which
# is the precise thing the old cleanup() broke. No network, no sudo, no TLauncher.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"
RUN="$REPO/run.sh"

WORK="$(mktemp -d)"
LOCK="${WORK}/tlauncher-test.lock"
trap 'rm -rf "$WORK"' EXIT

pass=0
total=0
failed=()
check() { # check NAME CONDITION_RESULT DETAIL
    total=$((total + 1))
    if [ "$2" = true ]; then
        pass=$((pass + 1)); printf 'PASS  %s\n' "$1"
    else
        printf 'FAIL  %s (%s)\n' "$1" "$3"; failed+=("$1")
    fi
}

# An instance, following run.sh's protocol: open fd 200 on the lockfile, take the
# lock or die. `hold` keeps it for N seconds; anything else exits at once.
instance() { # instance LABEL HOLD_SECONDS
    local label="$1" hold="$2"
    bash -c '
        set -uo pipefail
        lock="$1"; label="$2"; hold="$3"
        cleanup_ran=false
        cleanup() {
            [ "$cleanup_ran" = true ] && return 0
            cleanup_ran=true
            # run.sh does NOT remove the lockfile here. If this line ever comes
            # back, the inode check below goes red.
            :
        }
        die() { printf "[%s] die: another instance holds the lock\n" "$label"; cleanup; exit 1; }
        trap cleanup EXIT INT TERM HUP QUIT
        exec 200>"$lock"
        flock -n 200 || die
        printf "[%s] LOCK ACQUIRED inode %s\n" "$label" "$(stat -c %i "$lock")"
        sleep "$hold"
        exit 0
    ' _ "$LOCK" "$label" "$hold"
}

printf -- '--- three-instance reproduction ---\n'

# A takes the lock & holds it.
instance A 6 > "${WORK}/a.out" 2>&1 &
A_PID=$!
sleep 1
inode_before="$(stat -c %i "$LOCK" 2>/dev/null || echo none)"

# B is rejected, & runs its cleanup/die path.
instance B 0 > "${WORK}/b.out" 2>&1
b_rc=$?

# C tries AFTER B's rejection. This is the one that used to succeed.
instance C 0 > "${WORK}/c.out" 2>&1
c_rc=$?

inode_after="$(stat -c %i "$LOCK" 2>/dev/null || echo none)"
cat "${WORK}/a.out" "${WORK}/b.out" "${WORK}/c.out"
printf -- '--- checks ---\n'

grep -q 'LOCK ACQUIRED' "${WORK}/a.out" \
    && check "A acquires the lock" true "" \
    || check "A acquires the lock" false "A never reported acquisition"

[ "$b_rc" -ne 0 ] && grep -q 'die:' "${WORK}/b.out" \
    && check "B is rejected while A holds" true "" \
    || check "B is rejected while A holds" false "B exited $b_rc"

# The regression: C must NOT get the lock.
[ "$c_rc" -ne 0 ] && ! grep -q 'LOCK ACQUIRED' "${WORK}/c.out" \
    && check "C is rejected after B's rejection" true "" \
    || check "C is rejected after B's rejection" false "C exited $c_rc and may hold the lock alongside A"

# The mechanism: B's death must not have swapped the inode under A.
[ "$inode_before" = "$inode_after" ] && [ "$inode_before" != none ] \
    && check "lockfile inode survives a rejection" true "" \
    || check "lockfile inode survives a rejection" false "inode $inode_before -> $inode_after"

kill "$A_PID" 2>/dev/null || true
wait "$A_PID" 2>/dev/null || true

# A live session must still be visible to a later attempt.
# An orphaned child must NOT keep holding the session lock. flock lives on the open
# file description & fork/exec inherits it, so a monitor that outlives the parent
# co-holds the lock unless the fd is closed in the child. That matters doubly now
# that -K consults the lock: an orphan holding fd 200 would make -K refuse to reap
# the very orphan holding it.
printf -- '--- inherited-fd guard ---\n'
ORPHLOCK="${WORK}/orphan.lock"
bash -c '
    exec 200>"$1"
    flock -n 200 || exit 1
    bash -c "exec -a tlauncher-mon-fdtest sleep 20" 200>&- &
    exit 0
' _ "$ORPHLOCK"
sleep 0.4
if flock -n 9 9>"$ORPHLOCK" 2>/dev/null; then
    check "orphaned child does not hold the session lock" true ""
else
    check "orphaned child does not hold the session lock" false "fd 200 leaked into the child; -K would deadlock"
fi
pkill -f 'tlauncher-mon-fdtest' 2>/dev/null || true

printf -- '--- run.sh source guard ---\n'
if grep -qE '^\s*rm -f "\$LOCKFILE"' "$RUN"; then
    check "run.sh cleanup() does not delete the lockfile" false "rm -f \$LOCKFILE is back in run.sh"
else
    check "run.sh cleanup() does not delete the lockfile" true ""
fi

if grep -q '200>&-' "$RUN"; then
    check "run.sh closes fd 200 in its children" true ""
else
    check "run.sh closes fd 200 in its children" false "no 200>&- in run.sh"
fi

printf -- '----\n%d/%d lock checks verified\n' "$pass" "$total"
if [ "$pass" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
