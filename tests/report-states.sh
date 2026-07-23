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

STATES=(agent-data agent-empty off legacy-mitm)

# The phrase each state's report must contain, unique to that state.
phrase_for() {
    case "$1" in
        agent-data)      printf 'Mode: Java agent, in-process after TLS decrypt' ;;
        agent-empty)     printf 'Java agent active, but it logged no HTTP requests' ;;
        off)             printf 'no HTTP capture ran this session' ;;
        # A session that recorded the removed `mitmproxy` mode: honest on-disk facts,
        # no capture promise. This guards that the removed option can't reappear.
        legacy-mitm)     printf 'no longer supported' ;;
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

# Cross-run contamination guard (v2.16). The report states above are rendered by `-R`
# from an already-aggregated log, so they can't see the other half of the pipeline: the
# live aggregation reads the sandbox tmp, which firejail reuses across sessions. If the
# per-PID logs aren't cleared at the start of a run, a previous session's requests leak
# into this report. This drives the real reset_agent_tmp + aggregate_agent_logs on a tmp
# seeded with a stale file (old PID, 01:30) and a fresh one, and fails if the stale line
# survives the aggregate or the fresh one is missing. Remove the reset & this goes red.
total=$((total + 1))
# shellcheck disable=SC1090
source <(sed -n '/^reset_agent_tmp()/,/^}/p' "$RUN")
# shellcheck disable=SC1090
source <(sed -n '/^aggregate_agent_logs()/,/^}/p' "$RUN")
cwork="$(mktemp -d)"
ctmp="${cwork}/sandbox-tmp"
mkdir -p "$ctmp"
# Leftovers from a PREVIOUS session (old PID, old timestamp).
printf '[01:30:24.093] GET stale.example.org /old\n[01:30:24.100] STATUS: 200 REQ: 0 RESP: 1\n[01:30:24.101] BODY_OUT: empty\n[01:30:24.102] BODY_IN: x\n' > "${ctmp}/http-intercept-4.log"
printf '[01:30:24.050] SAW stale.previous.class\n' > "${ctmp}/agent-diag-4.log"
# Start-of-session cleanup, then the CURRENT session writes its own per-PID logs.
reset_agent_tmp "$ctmp"
printf '[11:36:44.500] GET repo.tlauncher.org /starterUpdateV1.json\n[11:36:44.600] STATUS: 200 REQ: 0 RESP: 2\n[11:36:44.601] BODY_OUT: empty\n[11:36:44.602] BODY_IN: y\n' > "${ctmp}/http-intercept-999.log"
printf '[11:36:44.400] HOOKED current.class\n' > "${ctmp}/agent-diag-999.log"
c_http="$(aggregate_agent_logs "${ctmp}/http-intercept-*.log")"
c_diag="$(aggregate_agent_logs "${ctmp}/agent-diag-*.log")"
c_ok=true
c_reason=""
if printf '%s%s' "$c_http" "$c_diag" | grep -q 'stale'; then
    c_ok=false; c_reason="stale previous-session line survived"
fi
if ! printf '%s' "$c_http" | grep -qF 'starterUpdateV1.json'; then
    c_ok=false; c_reason="current-session line missing"
fi
rm -rf "$cwork"
if [ "$c_ok" = true ]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "cross-contamination"
else
    printf 'FAIL  %s (%s)\n' "cross-contamination" "$c_reason"; failed+=("cross-contamination")
fi

printf -- '----\n%d/%d states verified\n' "$pass" "$total"
if [ "$pass" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
