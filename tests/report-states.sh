#!/usr/bin/env bash
# Regression net for the report's capture-state honesty (ROADMAP Phase 0).
#
# It drives the report through the real `run.sh -R` entry point against four
# synthetic session directories, one per capture state, & checks two things for
# each: the report prints that state's phrase, & it prints NONE of the other three.
# The second half is what would have caught the bug where the report said "run
# without -P" during an active agent session.
#
# WHY through `-R` & not a unit stub: `-R` is the real report entry point, so this
# exercises generate_incident_report -> report_network_capture exactly as a live
# session does. The only synthetic part is the session directory, which is just
# what a real session leaves on disk. A mock of the report functions would test the
# mock, not the code that ships. No network, no sudo, no TLauncher.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"
RUN="$REPO/run.sh"
FIX="$TESTS_DIR/fixtures"

STATES=(agent-data agent-empty off proxy-fallback)

# The phrase each state's report must contain, unique to that state.
phrase_for() {
    case "$1" in
        agent-data)      printf 'Mode: Java agent, in-process after TLS decrypt' ;;
        agent-empty)     printf 'Java agent active, but it logged no HTTP requests' ;;
        off)             printf 'no HTTP capture ran this session' ;;
        proxy-fallback)  printf 'mitmproxy fallback' ;;
    esac
}

pass=0
total=0
failed=()
for state in "${STATES[@]}"; do
    total=$((total + 1))
    work="$(mktemp -d)"
    cp -r "${FIX}/${state}/." "${work}/"
    # Hermetic: temp XDG so no real baseline, sandbox, or log dir is touched.
    XDG_DATA_HOME="${work}/xdg-data" XDG_STATE_HOME="${work}/xdg-state" \
        bash "$RUN" -R "$work" >/dev/null 2>&1
    report="${work}/INCIDENT_REPORT.md"

    ok=true
    reason=""
    if [ ! -f "$report" ]; then
        ok=false; reason="no report generated"
    else
        if ! grep -qF -- "$(phrase_for "$state")" "$report"; then
            ok=false; reason="missing own phrase"
        fi
        for other in "${STATES[@]}"; do
            [ "$other" = "$state" ] && continue
            if grep -qF -- "$(phrase_for "$other")" "$report"; then
                ok=false; reason="leaked '${other}' phrase"
            fi
        done
    fi

    if [ "$ok" = true ]; then
        pass=$((pass + 1)); printf 'PASS  %s\n' "$state"
    else
        printf 'FAIL  %s (%s)\n' "$state" "$reason"; failed+=("$state")
    fi
    rm -rf "$work"
done

printf -- '----\n%d/%d states verified\n' "$pass" "$total"
if [ "$pass" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
