#!/usr/bin/env bash
# Runs every suite in tests/, then re-runs the flakiness-sensitive ones N times.
#
# WHY the repetition exists: doc-sync.sh used to fail about one run in five and
# passed the four in between, so a single green run proved nothing. The bug was a
# SIGPIPE race (DESIGN principle 3, "A pipe whose consumer can finish first"), and
# the shape of that bug is that it is invisible unless you look more than once. The
# fix is in, & this keeps the door shut: if an intermittent failure comes back, the
# repeat catches it here instead of on whichever run happens to be unlucky.
#
# N is REPEATS, default 3, low enough to run on every commit. Raise it for proof:
#   REPEATS=200 tests/run-all.sh
# Only the suites named in REPEATED below are repeated. The other two drive real
# processes & locks, take seconds each, & have never been observed intermittent, so
# repeating them would cost minutes to re-prove something already stable.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPEATS="${REPEATS:-3}"

SUITES=(doc-sync.sh lock-exclusion.sh report-states.sh)
REPEATED=(doc-sync.sh)

rc=0
for suite in "${SUITES[@]}"; do
    printf '========  %s  ========\n' "$suite"
    bash "${TESTS_DIR}/${suite}" || rc=1
    printf '\n'
done

for suite in "${REPEATED[@]}"; do
    printf '========  %s x%s (flakiness)  ========\n' "$suite" "$REPEATS"
    fails=0
    for i in $(seq 1 "$REPEATS"); do
        if ! out="$(bash "${TESTS_DIR}/${suite}" 2>&1)"; then
            fails=$((fails + 1)); rc=1
            printf 'FAIL  run %s of %s:\n%s\n' "$i" "$REPEATS" "$out"
        fi
    done
    printf '%s: %s/%s runs green, %s failed\n\n' \
        "$suite" "$((REPEATS - fails))" "$REPEATS" "$fails"
done

[ "$rc" -eq 0 ] && printf 'ALL GREEN\n' || printf 'SOMETHING FAILED\n'
exit "$rc"
