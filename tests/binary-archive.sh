#!/usr/bin/env bash
# Regression net for ROADMAP Phase 3, the binary archive.
#
# Its acceptance, run against the code that ships: two sessions in a row with the same
# jar leave one copy & two manifest lines for its hash, `new` then `sighting`. Around
# it: the automatic path at the end of a launch, the retention cap, & the manifest's
# shape.
#
# Like cleanup-signals.sh, it loads run.sh without its last line, `main "$@"`, with
# every XDG path pointed into a scratch dir, so the functions are tested as shipped.
# firejail is a stub on PATH that exits 3: no TLauncher, no network, no sudo.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"

WORK="$(mktemp -d)"
trap '[ -n "${KEEP_WORK:-}" ] || rm -rf "$WORK"' EXIT
LIB="${WORK}/run-lib.sh"
head -n -1 "$REPO/run.sh" > "$LIB"
mkdir -p "${WORK}/home" "${WORK}/run" "${WORK}/stub" "${WORK}/jars"
printf '#!/bin/sh\nexit 3\n' > "${WORK}/stub/firejail"
chmod +x "${WORK}/stub/firejail"

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

# lib DATA_DIR SCRIPT: run SCRIPT with run.sh's functions loaded & XDG_DATA_HOME at
# DATA_DIR, in a clean environment.
lib() {
    env -i PATH="${WORK}/stub:$PATH" HOME="${WORK}/home" USER=batest \
        XDG_DATA_HOME="$1" XDG_STATE_HOME="${WORK}/state" XDG_RUNTIME_DIR="${WORK}/run" \
        bash -c 'source "$1"; eval "$2"' _ "$LIB" "$2"
}

# A distinct jar per id. Not a real jar; the archive only hashes & copies bytes.
jar() { printf 'jar %s\n' "$1" > "${WORK}/jars/$1.jar"; printf '%s' "${WORK}/jars/$1.jar"; }

printf -- '--- 1. two sessions, one copy, two manifest lines ---\n'
D1="${WORK}/d1"
J="$(jar same)"
lib "$D1" "main -J -f '$J'" 2>/dev/null; rc1=$?
lib "$D1" "main -J -f '$J'" 2>/dev/null; rc2=$?
sum="$(sha256sum "$J")"; sum="${sum%% *}"
copies="$(find "${D1}/tlauncher-binary-archive" -name 'TLauncher-*.jar' | wc -l)"
events="$(awk -F'\t' -v s="$sum" '$4 == s {printf "%s ", $2}' "${D1}/tlauncher-binary-archive/manifest.tsv")"
[ "$rc1$rc2" = 00 ] && check "-J exits 0 both times" true "" \
    || check "-J exits 0 both times" false "exit codes $rc1 & $rc2"
[ "$copies" -eq 1 ] && check "one copy of the same jar" true "" \
    || check "one copy of the same jar" false "$copies copies"
[ "$events" = "new sighting " ] && check "manifest reads new, then sighting" true "" \
    || check "manifest reads new, then sighting" false "events: ${events:-none}"
cmp -s "$J" "${D1}/tlauncher-binary-archive/TLauncher-${sum}.jar" \
    && check "the copy matches the jar byte for byte" true "" \
    || check "the copy matches the jar byte for byte" false "cmp differs"

printf -- '--- 2. a launch archives at its end ---\n'
D2="${WORK}/d2"
J2="$(jar launched)"
lib "$D2" "setup_sandbox '$J2'; HOME_JAR='$J2'; run_sandboxed" 2>/dev/null; rc=$?
lines="$(grep -vc '^#' "${D2}/tlauncher-binary-archive/manifest.tsv" 2>/dev/null)"
[ "$rc" -eq 3 ] && check "TLauncher's exit code still comes through" true "" \
    || check "TLauncher's exit code still comes through" false "exit $rc, the stub exits 3"
[ "${lines:-0}" -eq 1 ] && check "one manifest line after a launch" true "" \
    || check "one manifest line after a launch" false "${lines:-0} lines"
src="$(awk -F'\t' '!/^#/ {print $7}' "${D2}/tlauncher-binary-archive/manifest.tsv" 2>/dev/null)"
[ "$src" = "$J2" ] \
    && check "the source column names the home jar" true "" \
    || check "the source column names the home jar" false "source: ${src:-none}"

printf -- '--- 3. the cap drops the copy seen longest ago ---\n'
D3="${WORK}/d3"
script=''
for n in 1 2 3 4 5 6 7 8 9 10; do
    script+="binary_archive_add '$(jar "k$n")' k$n; sleep 0.02; "
done
# k1 is seen again, so the oldest sighting is now k2's, & k11 pushes the count to 11.
script+="binary_archive_add '${WORK}/jars/k1.jar' k1; sleep 0.02; "
script+="binary_archive_add '$(jar k11)' k11"
lib "$D3" "$script" 2>/dev/null
k2="$(sha256sum "${WORK}/jars/k2.jar")"; k2="${k2%% *}"
k1="$(sha256sum "${WORK}/jars/k1.jar")"; k1="${k1%% *}"
copies="$(find "${D3}/tlauncher-binary-archive" -name 'TLauncher-*.jar' | wc -l)"
pruned="$(awk -F'\t' '$2 == "pruned" {print $4}' "${D3}/tlauncher-binary-archive/manifest.tsv")"
[ "$copies" -eq 10 ] && check "ten copies kept after eleven jars" true "" \
    || check "ten copies kept after eleven jars" false "$copies copies"
[ "$pruned" = "$k2" ] && check "the pruned one is the least recently seen" true "" \
    || check "the pruned one is the least recently seen" false "pruned: ${pruned:-none}"
[ -f "${D3}/tlauncher-binary-archive/TLauncher-${k1}.jar" ] \
    && check "a jar seen again survives the cap" true "" \
    || check "a jar seen again survives the cap" false "k1's copy is gone"

printf -- '--- 4. the manifest keeps its shape ---\n'
bad=0
for d in "$D1" "$D2" "$D3"; do
    m="${d}/tlauncher-binary-archive/manifest.tsv"
    [ "$(grep -c '^#' "$m")" -eq 1 ] || bad=$((bad + 1))
    bad=$((bad + $(awk -F'\t' 'NF != 7' "$m" | wc -l)))
done
[ "$bad" -eq 0 ] && check "one header & seven fields on every line" true "" \
    || check "one header & seven fields on every line" false "$bad bad line(s)"
left="$(find "$D1" "$D2" "$D3" -name '*.part' | wc -l)"
[ "$left" -eq 0 ] && check "no partial copy left behind" true "" \
    || check "no partial copy left behind" false "$left .part file(s)"

printf -- '----\n%d/%d binary-archive checks verified\n' "$pass" "$total"
if [ "$pass" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
