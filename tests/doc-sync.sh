#!/usr/bin/env bash
# Regression net for documentation/code sync (docs/cli-standard.md).
#
# The repo deliberately keeps a long `--help` AND a full manual page, which
# duplicates CONTENT on purpose. That is only affordable if it cannot duplicate
# MAINTENANCE: an option added to the parser and forgotten in one of the two
# documents has to fail here rather than rot quietly. Same for exit codes, which
# no user could discover at all before the manual page existed.
#
# WHY it drives the real entry points: every check below reads `--help` and
# `--print-man` as a user gets them, and the parser out of run.sh itself. A fixture
# copy of either would test the fixture. No network, no sudo, no TLauncher.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TESTS_DIR/.." && pwd)"
RUN="$REPO/run.sh"

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

HELP="$(bash "$RUN" --help 2>/dev/null)"
MAN="$(bash "$RUN" --print-man 2>/dev/null)"
# OPTIONS runs from its own header to the next .SH.
# roff escapes every hyphen as \- , so compare against an unescaped copy.
MAN_PLAIN="$(printf '%s\n' "$MAN" | sed 's/\\-/-/g')"
MAN_OPTIONS="$(printf '%s\n' "$MAN_PLAIN" | awk '/^\.SH OPTIONS$/{f=1;next} /^\.SH /{f=0} f')"
MAN_EXIT="$(printf '%s\n' "$MAN_PLAIN" | awk '/^\.SH EXIT STATUS$/{f=1;next} /^\.SH /{f=0} f')"

# Long options the parser accepts, straight from the case arms.
parser_long_opts() {
    awk '/^ *-.*\)/ {
            line=$0
            sub(/\).*/, "", line)
            gsub(/^ +/, "", line)
            n=split(line, parts, "|")
            for (i=1; i<=n; i++) if (parts[i] ~ /^--/) print parts[i]
         }' "$RUN" | sort -u
}
# Short options likewise (-v, -ml, ...), excluding the catch-all -*).
parser_short_opts() {
    awk '/^ *-.*\)/ {
            line=$0
            sub(/\).*/, "", line)
            gsub(/^ +/, "", line)
            n=split(line, parts, "|")
            for (i=1; i<=n; i++) if (parts[i] ~ /^-[A-Za-z]+$/) print parts[i]
         }' "$RUN" | sort -u
}

printf -- '--- 1. every parsed option is documented in both places ---\n'
missing_help=""; missing_man=""
while IFS= read -r opt; do
    [ -z "$opt" ] && continue
    case "$HELP" in *"$opt"*) ;; *) missing_help="${missing_help} ${opt}" ;; esac
    case "$MAN_OPTIONS" in *"${opt#--}"*) ;; *) missing_man="${missing_man} ${opt}" ;; esac
done < <(parser_long_opts)
while IFS= read -r opt; do
    [ -z "$opt" ] && continue
    case "$HELP" in *"$opt"*) ;; *) missing_help="${missing_help} ${opt}" ;; esac
    case "$MAN_OPTIONS" in *"${opt#-}"*) ;; *) missing_man="${missing_man} ${opt}" ;; esac
done < <(parser_short_opts)
[ -z "$missing_help" ] && check "every parsed option appears in --help" true "" \
    || check "every parsed option appears in --help" false "missing:${missing_help}"
[ -z "$missing_man" ] && check "every parsed option appears in man OPTIONS" true "" \
    || check "every parsed option appears in man OPTIONS" false "missing:${missing_man}"

printf -- '--- 2. no documented option is absent from the parser ---\n'
known="$( { parser_long_opts; parser_short_opts; } | tr -d ' ')"
ghosts=""
while IFS= read -r opt; do
    [ -z "$opt" ] && continue
    case $'\n'"${known}"$'\n' in *$'\n'"${opt}"$'\n'*) ;; *) ghosts="${ghosts} ${opt}" ;; esac
done < <(printf '%s\n' "$HELP" \
            | grep -oE '^[[:space:]]+-[A-Za-z-]+(,[[:space:]]*--[a-z][a-z-]+)?' \
            | grep -oE '\-\-[a-z][a-z-]+' | sort -u)
[ -z "$ghosts" ] && check "no --option in --help is missing from the parser" true "" \
    || check "no --option in --help is missing from the parser" false "not parsed:${ghosts}"

printf -- '--- 3. every reachable exit code is in EXIT STATUS ---\n'
missing_codes=""
while IFS= read -r code; do
    [ -z "$code" ] && continue
    grep -qE "^\.B ${code}\$" <<< "$MAN_EXIT" || missing_codes="${missing_codes} ${code}"
done < <(grep -oE '^readonly EX_[A-Z_]+=[0-9]+' "$RUN" | grep -oE '[0-9]+$' | sort -un)
[ -z "$missing_codes" ] && check "every EX_* code is documented in EXIT STATUS" true "" \
    || check "every EX_* code is documented in EXIT STATUS" false "undocumented:${missing_codes}"

printf -- '--- 4. --help and --print-man are clean on stdout ---\n'
h_err="$(bash "$RUN" --help 2>&1 >/dev/null)"; h_rc=$?
m_err="$(bash "$RUN" --print-man 2>&1 >/dev/null)"; m_rc=$?
{ [ "$h_rc" -eq 0 ] && [ -z "$h_err" ]; } \
    && check "--help exits 0 with nothing on stderr" true "" \
    || check "--help exits 0 with nothing on stderr" false "rc=$h_rc stderr='${h_err:0:60}'"
{ [ "$m_rc" -eq 0 ] && [ -z "$m_err" ]; } \
    && check "--print-man exits 0 with nothing on stderr" true "" \
    || check "--print-man exits 0 with nothing on stderr" false "rc=$m_rc stderr='${m_err:0:60}'"

printf -- '--- 5. the roff parses ---\n'
# mandoc grades its own output & the three grades do not mean the same thing.
# ERROR & WARNING say the roff is malformed: the page renders wrong or not at all,
# so they turn this red. STYLE says the source is untidy (a text line past 80 bytes,
# a date format it would rather see) while the page renders correctly; it prints as
# a note & does NOT fail, because a typographic preference should not block a commit
# that changes no behaviour. If you want the stricter bar, move STYLE into the first
# branch; the point is that the decision is written down rather than implied by
# "any output at all is a failure", which is what this check used to do.
if command -v mandoc >/dev/null 2>&1; then
    lint="$(mandoc -Tlint 2>&1 <<< "$MAN")"
    hard="$(grep -E ': (ERROR|WARNING|UNSUPP|SYSERR):' <<< "$lint" || true)"
    soft="$(grep -E ': STYLE:' <<< "$lint" || true)"
    [ -z "$hard" ] \
        && check "roff is free of mandoc ERROR/WARNING" true "" \
        || check "roff is free of mandoc ERROR/WARNING" false "${hard:0:120}"
    [ -n "$soft" ] && printf 'NOTE  mandoc STYLE (not a failure): %s\n' "${soft:0:120}"
elif command -v groff >/dev/null 2>&1; then
    gerr="$(groff -man -Tascii 2>&1 >/dev/null <<< "$MAN")"
    [ -z "$gerr" ] \
        && check "roff passes groff -man -Tascii" true "" \
        || check "roff passes groff -man -Tascii" false "${gerr:0:120}"
else
    # Not assumed good. The repo installs nothing, so this stays unproven here.
    # It is not an unexplored hole either: the page was validated by hand on a
    # machine that had both, 2026-09-17. mandoc -Tlint & groff -man -Tascii both
    # exited 0; the only output was one STYLE note about a text line past 80 bytes
    # in FILES, which v2.26 split. Nothing since then has changed the roff's shape.
    skip "roff formatter check" "neither mandoc nor groff is installed; NOT verified here (hand-checked clean 2026-09-17)"
fi

printf -- '--- 6. mandatory sections, present and in order ---\n'
expected=(NAME SYNOPSIS DESCRIPTION OPTIONS "EXIT STATUS" ENVIRONMENT FILES DIAGNOSTICS EXAMPLES SECURITY "SEE ALSO" BUGS)
actual=(); while IFS= read -r sec; do actual+=("$sec"); done < <(printf '%s\n' "$MAN" | sed -n 's/^\.SH //p')
if [ "${#actual[@]}" -ne "${#expected[@]}" ]; then
    check "man sections present and ordered" false "have ${#actual[@]} sections, want ${#expected[@]}: ${actual[*]}"
else
    order_ok=true; bad=""
    for i in "${!expected[@]}"; do
        if [ "${actual[$i]}" != "${expected[$i]}" ]; then
            order_ok=false; bad="position $((i+1)): got '${actual[$i]}', want '${expected[$i]}'"; break
        fi
    done
    [ "$order_ok" = true ] && check "man sections present and ordered" true "" \
        || check "man sections present and ordered" false "$bad"
fi

printf -- '----\n%d/%d doc-sync checks verified' "$pass" "$total"
[ "$skipped" -gt 0 ] && printf ' (%d skipped, not verified)' "$skipped"
printf '\n'
if [ "$((pass + skipped))" -ne "$total" ]; then
    printf 'failed: %s\n' "${failed[*]}"
    exit 1
fi
exit 0
