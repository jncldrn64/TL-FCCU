#!/usr/bin/env bash
# TLauncher Sandboxed Launcher
# Runs TLauncher under firejail & records what it touches.
#
# What this revision buys (see the inline "WHY" comments for the details):
#   - Every background monitor gets reaped. A stray inotifywait once wrote a
#     single files.log to 51 MB; that doesn't happen anymore.
#   - Logs stay small enough for a person or an LLM to read: the filesystem
#     monitor filters noise & the process monitors log first-seen lines only.
#   - INCIDENT_REPORT.md aggregates the signal into about 5.7 KB per session.
#   - Retention keeps the log directory off the 2 GB it once reached on its own.
#   - Opt-in HTTP(S) capture through mitmproxy, off by default.
#   - A domain regression check against a baseline the user curates.
#
# HARD CONSTRAINT: this script never calls sudo, never asks for a password, &
# never needs a capability beyond what firejail drops on its own. Installing
# mitmproxy or sqlite3 by hand, outside this script, is the user's job; the
# script itself stays unprivileged.
#
# CONVENTIONS: DESIGN.md sits next to this script & holds the style guide. XDG
# paths everywhere, zero sudo, flock in the same scope, background jobs tracked
# by $!, standard CLI grammar, silent by default but never mute. A new feature
# follows those or it doesn't ship.
set -euo pipefail

VERSION="2.16"

# Directory holding this script, used to find helpers like scripts/mitm_report.py.
# Resolved once & survives being called through a symlink.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# ==========================================
# CONFIGURATION
# ==========================================

# User detection ( :-$(id -un) guards against USER being unset under set -u )
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
REAL_UID="${SUDO_UID:-$(id -u)}"
REAL_GID="${SUDO_GID:-$(id -g)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || echo "$HOME")

# XDG directories
XDG_DATA_HOME="${XDG_DATA_HOME:-${REAL_HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${REAL_HOME}/.local/state}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${REAL_UID}}"

# Fallback if XDG_RUNTIME_DIR doesn't exist
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR="/tmp"
fi

# Paths
SANDBOX_DIR="${XDG_DATA_HOME}/tlauncher-sandbox"
LOG_ROOT="${XDG_STATE_HOME}/tlauncher-logs"
LOCKFILE="${XDG_RUNTIME_DIR}/tlauncher-${REAL_USER}.lock"

# firejail's sandbox hostname. Set once here, passed to firejail in
# build_firejail_params & reused by the network monitor to find the sandbox PID
# tree. One source for the datum, so the two never drift apart.
SANDBOX_HOSTNAME="mcbox"

# Path shown in human-facing output only. Real filesystem paths always use the
# absolute XDG paths above; DISPLAY_HOME just keeps $REAL_HOME out of anything the
# script prints to a terminal (usage, summaries, analysis), so /home/<user> never
# leaks into a screenshot, a paste, or a CI log.
DISPLAY_HOME="~"

# Options
VERBOSE=false
OFFLINE_MODE=false
MONITOR_ENABLED=false
AUTO_ANALYZE=false
MOZILLA_CHECK=false
TLAUNCHER_PATH=""
MOZILLA_SEARCH_PATH="${REAL_HOME}/.mozilla"

# New standalone / opt-in modes
KILL_ORPHANS=false       # -K: just reap stray monitors, don't launch
REPORT_SESSION=""        # -R DIR: (re)generate INCIDENT_REPORT.md for a session
CLEANUP_LOGS_FLAG=false   # -c: run log retention, don't launch
CLEANUP_DAYS=7           # default retention window (days)
LOG_SIZE_CAP_MB=500      # delete old compressed sessions once dir exceeds this
PROXY_ENABLED=false      # -P: opt-in mitmproxy HTTP(S) capture
PROXY_PORT=8080          # default mitmproxy listen port
SAVE_BASELINE_SESSION="" # -B DIR: derive baseline files from a clean session, then exit
CHECK_DEPS=false         # --check-deps: report dependency state, then exit

# Baseline files (XDG_DATA_HOME, same pattern as everything else). The IP one is
# pre-existing; the domains one drives the regression check (Round 2 / Task 3).
BASELINE_IPS="${XDG_DATA_HOME}/tlauncher-sandbox-baseline-ips.txt"
BASELINE_DOMAINS="${XDG_DATA_HOME}/tlauncher-sandbox-baseline-domains.txt"

# Dependency state file (same XDG_DATA_HOME convention as the baselines). It
# records, once, whether each dependency was already on the system or would be
# script-installed, so a future uninstall path can tell what the script added from
# what was already there. Plain text, read with grep, no ini parser.
DEPS_FILE="${XDG_DATA_HOME}/tlauncher-sandbox-deps.ini"

# Dependency catalog: cmd|package|section|required|source|feature. check_requirements
# probes these & records them; --check-deps prints all of them. procps ships both
# pgrep & pkill, so pgrep stands in for the pair.
DEPS_CATALOG=(
    "java|default-jre|system|yes|apt|run TLauncher at all"
    "firejail|firejail|system|yes|apt|the sandbox itself"
    "inotifywait|inotify-tools|system|no|apt|filesystem monitor (-M)"
    "ss|iproute2|system|no|apt|network monitor (-M)"
    "pgrep|procps|system|no|apt|orphan-proof cleanup (-M)"
    "mitmdump|mitmproxy|python|no|pip|HTTP(S) capture (-P) fallback"
    "javac|default-jdk|system|no|apt|build the Java HTTP agent (one-time)"
    "wget|wget|system|no|apt|download Byte Buddy for agent build"
)

# Monitoring
SESSION_ID=""
SESSION_DIR=""
MONITOR_PIDS=()

# Protected directories
PROTECTED_DIRS=(
    ".mozilla" ".firefox" ".config/google-chrome" ".config/chromium"
    ".local/share/keyrings" ".gnupg" ".ssh"
    "Documents" "Downloads" "Pictures" "Videos" "Music"
)

# Filesystem noise: extended-regex fragments matched against each inotifywait
# event line. A match is benign engine churn. It still lands in files.log, which
# stays lossless, but it's kept out of signal.log, the small file a person or the
# analysis reads first. Edit the array to fit your environment.
NOISE_PATTERNS=(
    'mesa_shader_cache/'
    '\.sqlite-wal$'
    '\.sqlite-shm$'
    '-journal$'
    'webview/\.test'
    '\.tmp$'
    'GPUCache/'
    'Code Cache/'
    'ShaderCache/'
    '\.lock$'
)
# Pre-joined into a single ERE; exported so the (separate-process) monitors see it.
NOISE_REGEX="$(IFS='|'; printf '%s' "${NOISE_PATTERNS[*]}")"

# Hosts considered benign for the mitmproxy summary (full request bodies are only
# surfaced for hosts NOT in this list, or for non-empty POST/PUT bodies).
MITM_ALLOWLIST=(
    "tlauncher.org" "fastrepo.org" "tl.vg" "mojang.com" "forgecdn.net"
    "curseforge.com" "minecraft.net" "microsoft.com" "live.com" "xboxlive.com"
)

# Known-risky domain substrings for the regression check (Task 3). A domain that
# matches any of these gets flagged hard in INCIDENT_REPORT.md even when it's
# already in the baseline. These are the fallback & telemetry domains the author
# distrusts; advancedrepository probes over plain HTTP. Add new ones by hand.
RISK_DOMAIN_PATTERNS=(
    'advancedrepository'
    'securelogger'
)
RISK_DOMAIN_REGEX="$(IFS='|'; printf '%s' "${RISK_DOMAIN_PATTERNS[*]}")"

# Blocked domains (for reference in logs)
BLOCKED_DOMAINS=(
    "telemetry.tlauncher.org" "stats.tlauncher.org" "analytics.tlauncher.org"
    "tracking.tlauncher.org" "metrics.tlauncher.org" "events.tlauncher.org"
    "ads.tlauncher.org" "promo.tlauncher.org" "offers.tlauncher.org"
    "securelogger.top" "securelogger.net" "res.tlauncher.ru"
    "mps.tlauncher.ru" "ruzone.securelogger.top" "mps.fastrepo.org"
    "mps.tlauncher.org" "page.tlauncher.org" "stat.fastrepo.org"
    "stat.tlauncher.ru" "img.fastrepo.org"
)

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

# ==========================================
# LOGGING
# ==========================================

log_msg() {
    local ts="$(date '+%Y-%m-%d %H:%M:%S.%3N')"
    printf "[%s] %s\n" "$ts" "$*" >&2
    if [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ]; then
        printf "[%s] %s\n" "$ts" "$*" >> "${SESSION_DIR}/master.log" 2>/dev/null || true
    fi
}

log_verbose() {
    # The explicit `return 0` is load-bearing. With VERBOSE=false the `&&` chain
    # returns exit status 1, & under `set -e` a bare `log_verbose ...` call then
    # aborts the whole script. That bug killed every non-verbose run, including
    # the documented `-M -a` pattern, until this line was added.
    [ "$VERBOSE" = true ] && log_msg "$@"
    return 0
}

# Swap the $REAL_HOME prefix for ~ in a path that's about to be printed to a
# terminal. Never build a real filesystem path with this; only display one. Keeps
# /home/<user> out of screenshots, pastes, and CI logs.
disp_path() {
    printf '%s' "${1/#$REAL_HOME/$DISPLAY_HOME}"
}

# Aggregate the agent's per-PID logs into one file, in JVM start order, with a banner
# naming the PID before each block.
#
# WHY not a plain `cat *.log`: the glob sorts lexically by PID, so JVM 1 (a low PID like
# 4) lands after the game JVMs (PID 120+), and the file reads out of order. This orders
# whole files by their first line's timestamp, so a four-line request block is never
# split (2.2) & the reader sees the starter before the launcher. Empty per-PID files
# (a JVM the agent skipped, or one that made no HTTP) are dropped, so an all-empty
# capture aggregates to an empty file & the report can still tell "active, no requests"
# from "active, has data". $1 is the glob of per-PID files; the result goes to stdout.
aggregate_agent_logs() {
    local f ts pid
    for f in $1; do
        [ -e "$f" ] || continue
        [ -s "$f" ] || continue
        ts="$(head -n1 "$f" 2>/dev/null | sed -E 's/^\[([0-9:.]+)\].*/\1/')"
        printf '%s\t%s\n' "${ts:-99}" "$f"
    done | sort | while IFS="$(printf '\t')" read -r ts f; do
        pid="$(basename "$f" | sed -E 's/.*-([0-9]+)\.log$/\1/')"
        printf '# ---- JVM pid=%s ----\n' "$pid"
        cat "$f"
    done
}

# Clear the per-PID agent logs an EARLIER run left in the sandbox tmp, before this run's
# JVMs write theirs.
#
# WHY: firejail --private reuses SANDBOX_DIR across sessions, so http-intercept-<pid>.log
# & agent-diag-<pid>.log from old runs survive there. The aggregate globs by PID, so
# without this a previous session's requests (a stale 01:30 block long after the current
# run) leak into this report. Called at the start of an agent-active run, so the report
# only ever describes the current session. $1 is the sandbox tmp dir.
reset_agent_tmp() {
    local tmp="$1"
    mkdir -p "$tmp"
    rm -f "$tmp"/http-intercept-*.log "$tmp"/agent-diag-*.log 2>/dev/null || true
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2
}

die() {
    log_error "$*"
    cleanup
    exit 1
}

# ==========================================
# PROCESS HELPERS (orphan-proof cleanup)
# ==========================================

# Recursively kill a process & all of its descendants.
#
# WHY: each background monitor is a bash shell that spawns a long-running leaf
# tool (inotifywait -m, ss, ps, mitmdump). Kill only the shell & the leaf gets
# reparented to init, where it keeps writing to the inherited log fd. That's how
# one orphaned inotifywait grew a session's files.log to 51 MB. Killing children
# first, depth-first, closes the reparent race.
kill_tree() {
    local pid="$1" sig="${2:-TERM}" child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child" "$sig"
    done
    kill "-${sig}" "$pid" 2>/dev/null || true
}

# Print PIDs of stray monitor processes left from previous sessions, matched by
# command-line pattern. Used by -K & by the start-of-run orphan warning. Each
# monitor launches as `bash -c <body> tlauncher-mon-<sid>-<name>`, so the argv[0]
# tag is the handle; the known leaf tools are matched too as a deeper backstop.
find_orphan_pids() {
    # Exclude THIS process & its whole ancestor chain, so a fuzzy `pgrep -f` can't
    # flag & kill the shell that launched us. An interactive shell whose command
    # line happens to contain the tag string would otherwise match. A genuine stray
    # from a previous session is never our ancestor.
    local excl="$$" pid="$$"
    while :; do
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
        { [ -z "$pid" ] || [ "$pid" = 0 ] || [ "$pid" = 1 ]; } && break
        excl="${excl}|${pid}"
    done
    {
        pgrep -f "tlauncher-mon-"                          2>/dev/null || true
        pgrep -f "inotifywait -m -r.*tlauncher-sandbox"    2>/dev/null || true
        pgrep -f "mitmdump .*tlauncher-logs"               2>/dev/null || true
    } | sort -un | grep -vE "^(${excl})\$" || true
}

# Non-fatal: warn (stderr + session log) if prior-session monitors are still alive.
warn_orphans() {
    local pids; pids="$(find_orphan_pids)"
    [ -z "$pids" ] && return 0
    log_warn "Detected orphaned monitor process(es) from a previous session:"
    local p
    for p in $pids; do
        printf "    PID %s: %s\n" "$p" "$(ps -o args= -p "$p" 2>/dev/null | head -c 100)" >&2
    done
    log_warn "These are NOT being killed automatically. Run '$0 -K' to terminate them."
}

# -K/--kill-orphans implementation: find and kill stray monitors, loudly.
kill_orphans() {
    local pids; pids="$(find_orphan_pids)"
    if [ -z "$pids" ]; then
        log_msg "No orphaned monitor processes found."
        return 0
    fi
    log_warn "Found orphaned monitor process(es); terminating:"
    local p
    for p in $pids; do
        printf "    PID %s: %s\n" "$p" "$(ps -o args= -p "$p" 2>/dev/null | head -c 120)" >&2
    done
    for p in $pids; do kill_tree "$p" TERM; done
    sleep 1
    # Re-scan and force-kill anything still standing.
    pids="$(find_orphan_pids)"
    for p in $pids; do kill_tree "$p" KILL; done
    log_msg "Orphaned monitors terminated."
}

# Stop the monitors started in THIS run (TERM, then KILL), then a tag-based
# pkill safety net for anything that slipped the PID list.
stop_monitors() {
    if [ "${#MONITOR_PIDS[@]}" -gt 0 ]; then
        local pid
        for pid in "${MONITOR_PIDS[@]}"; do kill_tree "$pid" TERM; done
        sleep 1
        for pid in "${MONITOR_PIDS[@]}"; do kill_tree "$pid" KILL; done
    fi
    [ -n "${SESSION_ID:-}" ] && pkill -f "tlauncher-mon-${SESSION_ID}" 2>/dev/null || true
    MONITOR_PIDS=()
}

# ==========================================
# REQUIREMENTS
# ==========================================

# Create the deps state file with its two sections if it isn't there yet.
deps_ensure_file() {
    [ -f "$DEPS_FILE" ] && return 0
    mkdir -p "$(dirname "$DEPS_FILE")"
    {
        printf '# Generated by run.sh, do not edit by hand.\n'
        printf '# Format: name = state | source | date\n'
        printf '# state: pre-existing (already installed) | absent | script-installed\n\n'
        printf '[system]\n\n'
        printf '[python]\n'
    } > "$DEPS_FILE"
}

# Record a dependency once. The first record wins: if the package already has a
# line, trust it & return. That's what lets a later uninstall path tell what the
# script added from what was already there. Delete the .ini to re-inventory.
deps_record() {
    local section="$1" pkg="$2" state="$3" source="$4"
    deps_ensure_file
    grep -qE "^${pkg} =" "$DEPS_FILE" 2>/dev/null && return 0
    local line="${pkg} = ${state} | ${source} | $(date +%Y-%m-%d)"
    local tmp; tmp="$(mktemp)"
    # Insert the line right under its [section] header.
    awk -v sec="[$section]" -v ins="$line" '
        { print }
        $0 == sec && !done { print ins; done=1 }
    ' "$DEPS_FILE" > "$tmp" && mv "$tmp" "$DEPS_FILE"
}

check_requirements() {
    local missing=()

    command -v java >/dev/null 2>&1 || missing+=("default-jre")
    command -v firejail >/dev/null 2>&1 || missing+=("firejail")

    if [ "$MONITOR_ENABLED" = true ]; then
        command -v ss >/dev/null 2>&1 || missing+=("iproute2")
        command -v inotifywait >/dev/null 2>&1 || missing+=("inotify-tools")
        # pgrep/pkill power the orphan-proof cleanup.
        command -v pgrep >/dev/null 2>&1 || missing+=("procps")
        command -v pkill >/dev/null 2>&1 || missing+=("procps")
    fi

    # Record the state of every dependency this run actually probes: present ones
    # as pre-existing, missing ones as absent. First record wins (deps_record).
    local entry cmd pkg section required source feature
    for entry in "${DEPS_CATALOG[@]}"; do
        IFS='|' read -r cmd pkg section required source feature <<< "$entry"
        # Only record what this run checks: required deps always, optional only with -M/-P.
        if [ "$required" = yes ] || [ "$MONITOR_ENABLED" = true ] || [ "$PROXY_ENABLED" = true ]; then
            if command -v "$cmd" >/dev/null 2>&1; then
                deps_record "$section" "$pkg" "pre-existing" "$source"
            else
                deps_record "$section" "$pkg" "absent" "$source"
            fi
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required packages:"
        printf '  - %s\n' "${missing[@]}" >&2
        # NOTE: this is a printed HINT for the user to run manually. The script
        # itself never invokes sudo (hard constraint).
        printf "\nInstall manually with: sudo apt install %s\n" "${missing[*]}" >&2
        printf "Dependency state recorded in: %s\n" "$(disp_path "$DEPS_FILE")" >&2
        exit 1
    fi
}

# --check-deps: print the state of every known dependency & refresh the .ini.
# Exit 0 when all required deps are present, 1 when any required one is missing.
check_deps() {
    printf "${CYAN}TLauncher Sandbox: dependency check${NC}\n\n"
    local entry cmd pkg section required source feature missing_required=0
    for entry in "${DEPS_CATALOG[@]}"; do
        IFS='|' read -r cmd pkg section required source feature <<< "$entry"
        local live reg tag
        if command -v "$cmd" >/dev/null 2>&1; then
            live="present"
            deps_record "$section" "$pkg" "pre-existing" "$source"
        else
            live="MISSING"
            deps_record "$section" "$pkg" "absent" "$source"
            [ "$required" = yes ] && missing_required=$((missing_required + 1))
        fi
        if [ "$required" = yes ]; then tag="required"; else tag="optional"; fi
        # State line as recorded in the .ini (source & date come from the registry).
        reg="$(grep -E "^${pkg} =" "$DEPS_FILE" 2>/dev/null | head -n1 | sed -E 's/^[^=]+= //')"
        printf "  ${BLUE}%-14s${NC} %-9s %-8s [%s]\n" "$pkg" "$tag" "$live" "$reg"
        printf "                 needs it for: %s\n" "$feature"
    done
    printf "\nState file: %s\n" "$(disp_path "$DEPS_FILE")"
    if [ "$missing_required" -gt 0 ]; then
        printf "${RED}%d required dependency missing.${NC}\n" "$missing_required" >&2
        return 1
    fi
    printf "${GREEN}All required dependencies present.${NC}\n"
    return 0
}

# ==========================================
# TLAUNCHER DETECTION
# ==========================================

find_tlauncher() {
    if [ -n "$TLAUNCHER_PATH" ]; then
        if [ ! -f "$TLAUNCHER_PATH" ]; then
            die "Specified TLauncher not found: $TLAUNCHER_PATH"
        fi
        printf "%s" "$TLAUNCHER_PATH"
        return 0
    fi

    # Search in common locations
    for path in "./TLauncher.jar" "${REAL_HOME}/TLauncher.jar" "${REAL_HOME}/Downloads/TLauncher.jar"; do
        if [ -f "$path" ]; then
            printf "%s" "$(realpath "$path")"
            return 0
        fi
    done

    die "TLauncher.jar not found. Use -f to specify path"
}

# ==========================================
# SANDBOX SETUP
# ==========================================

setup_sandbox() {
    local tlauncher="$1"

    log_verbose "Setting up sandbox: $SANDBOX_DIR"

    mkdir -p "${SANDBOX_DIR}"/{.minecraft,tmp,bin}

    # Copy TLauncher to sandbox
    cp "$tlauncher" "${SANDBOX_DIR}/bin/TLauncher.jar"
    chmod +x "${SANDBOX_DIR}/bin/TLauncher.jar"

    log_verbose "Sandbox ready"
}

build_firejail_params() {
    local params=(
        --noprofile
        --private="${SANDBOX_DIR}"
        --private-dev
        --private-tmp
        --seccomp
        --caps.drop=all
        --noroot
        --nodvd --notv --nou2f --novideo --nogroups
        --hostname="${SANDBOX_HOSTNAME}"
        --nonewprivs
        --dbus-user=none
        --dbus-system=none
    )

    # Network control
    if [ "$OFFLINE_MODE" = true ]; then
        params+=(--net=none)
    fi

    # Proxy capture (-P): expose HTTP(S)_PROXY to the non-JVM helpers inside the
    # sandbox. The JVM ignores these env vars by default, so the JVM side is
    # handled with -Dhttp.proxyHost/-Dhttps.proxyHost on the java command (see
    # run_sandboxed). Without --net the sandbox shares the host network namespace,
    # so 127.0.0.1:PORT reaches the mitmdump running on the host.
    if [ "$PROXY_ENABLED" = true ]; then
        params+=(--env=HTTP_PROXY=http://127.0.0.1:${PROXY_PORT})
        params+=(--env=HTTPS_PROXY=http://127.0.0.1:${PROXY_PORT})
        params+=(--env=http_proxy=http://127.0.0.1:${PROXY_PORT})
        params+=(--env=https_proxy=http://127.0.0.1:${PROXY_PORT})
    fi

    # Blacklist protected directories
    for dir in "${PROTECTED_DIRS[@]}"; do
        [ -d "${REAL_HOME}/${dir}" ] && params+=(--blacklist="${REAL_HOME}/${dir}")
    done

    # Whitelist only necessary paths
    params+=(
        --whitelist="${SANDBOX_DIR}/.minecraft"
        --whitelist="${SANDBOX_DIR}/tmp"
        --whitelist="${SANDBOX_DIR}/bin"
        --read-only="${SANDBOX_DIR}/bin"
    )

    printf '%s\n' "${params[@]}"
}

# True when this run produces a session directory (full monitoring OR proxy capture).
session_logging_active() {
    [ "$MONITOR_ENABLED" = true ] || [ "$PROXY_ENABLED" = true ]
}

# ==========================================
# MONITORING SETUP
# ==========================================

# Shared shell preamble injected into every backgrounded monitor. Each monitor is
# a separate `bash -c` process so its argv[0] can carry the tag, & a separate
# process doesn't inherit this script's functions. So the helpers it needs ship
# here as text & get prepended to every monitor body.
read -r -d '' MONITOR_PREAMBLE <<'PREAMBLE' || true
# first_seen_loop LOGFILE SEENFILE PRODUCER_CMD INTERVAL
# Writes to LOGFILE only when PRODUCER_CMD prints a line it hasn't seen ("NEW:"),
# & once when a line it had seen disappears ("ENDED:").
# WHY: the old monitors dumped a full `ps auxf`/`ss` snapshot every 2 seconds &
# produced a 42 MB java-processes.log per session, nearly all of it identical.
# First-seen catches a new or suspicious process just as fast at a fraction of the
# bytes.
first_seen_loop() {
    local logfile="$1" seen="$2" producer="$3" interval="${4:-2}"
    local ended="${seen}.ended"
    : > "$seen"; : > "$ended"
    local ts cur line
    while true; do
        ts="$(date '+%Y-%m-%d %H:%M:%S.%3N')"
        cur="$(mktemp)"
        eval "$producer" > "$cur" 2>/dev/null || true
        # Newly appeared lines.
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if ! grep -Fxq -- "$line" "$seen" 2>/dev/null; then
                printf '%s\n' "$line" >> "$seen"
                printf '[%s] NEW: %s\n' "$ts" "$line" >> "$logfile"
            fi
        done < "$cur"
        # Lines that were seen before but are gone now (log the termination once).
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if ! grep -Fxq -- "$line" "$cur" 2>/dev/null && ! grep -Fxq -- "$line" "$ended" 2>/dev/null; then
                printf '%s\n' "$line" >> "$ended"
                printf '[%s] ENDED: %s\n' "$ts" "$line" >> "$logfile"
            fi
        done < "$seen"
        rm -f "$cur"
        sleep "$interval"
    done
}

# Print the PID tree of the firejail sandbox: the firejail process (matched by the
# hostname set once in build_firejail_params & exported as SANDBOX_HOSTNAME) plus
# every descendant. firejail runs in the foreground after the monitors start, so
# there's no PID to hand the monitor at launch; it resolves the tree every cycle,
# which also catches the JRE, the Minecraft process, & crash_assistant that
# TLauncher spawns partway through the session.
_descendants() {
    local pid="$1" kid
    printf '%s\n' "$pid"
    for kid in $(pgrep -P "$pid" 2>/dev/null); do
        _descendants "$kid"
    done
}
firejail_tree_pids() {
    local root
    for root in $(pgrep -f "firejail .*--hostname=${SANDBOX_HOSTNAME}" 2>/dev/null); do
        _descendants "$root"
    done | sort -un
}

# Established TCP connections owned by a PID inside the firejail tree, one
# "local -> peer" per line. ss -tnp prints pid=NNNN for same-user sockets with no
# privileges, & TLauncher runs as this user, so its sockets carry a visible PID.
# A connection from the user's browser, Discord, or a system updater has a PID
# outside the tree & gets dropped, so network.log stays TLauncher-only.
firejail_conns() {
    local ids
    ids="$(firejail_tree_pids | paste -sd'|')"
    [ -z "$ids" ] && return 0
    # The [,)] anchor stops pid=123 from matching pid=1234; ss writes pid=NNNN,fd=..
    ss -tnp state established 2>/dev/null | tail -n +2 \
        | grep -E "pid=(${ids})[,)]" \
        | awk '{print $4" -> "$5}'
}
PREAMBLE

# Launch a monitor body as a tagged background process & track its PID.
#
# WHY the tag: argv[0] = "tlauncher-mon-<session>-<name>" lets cleanup() & -K find
# strays by pattern if PID tracking ever slips. There's no setsid here on purpose,
# so $! is the bash PID we can track exactly; kill_tree() reaps the descendants.
spawn_monitor() {
    local name="$1" body="$2"
    bash -c "${MONITOR_PREAMBLE}
${body}" "tlauncher-mon-${SESSION_ID}-${name}" &
    local pid=$!
    MONITOR_PIDS+=("$pid")
    log_verbose "  → ${name} monitor PID: $pid"
}

monitor_filesystem() {
    log_verbose "Starting filesystem monitor..."
    # Every event goes to files.log, which stays lossless. An event that doesn't
    # match the noise regex also gets copied to signal.log, the small file the
    # analysis reads first.
    spawn_monitor "filesystem" '
        sleep 0.3
        inotifywait -m -r \
            -e modify,create,delete,move,close_write \
            --timefmt "%Y-%m-%d %H:%M:%S.%3N" \
            --format "[%T] %e %w%f" \
            "$SANDBOX_DIR" 2>&1 | while IFS= read -r line; do
                printf "%s\n" "$line" >> "$SESSION_DIR/files.log"
                if [ -z "$NOISE_REGEX" ] || ! printf "%s" "$line" | grep -qE "$NOISE_REGEX"; then
                    printf "%s\n" "$line" >> "$SESSION_DIR/signal.log"
                fi
            done
    '
}

monitor_network() {
    log_verbose "Starting network monitor (first-seen, firejail tree only)..."
    # First-seen of established connections, filtered to TLauncher's own PID tree
    # so the user's other network traffic never lands in network.log. Still no
    # privileges: ss -tnp shows the pid for same-user sockets.
    spawn_monitor "network" '
        sleep 0.5
        first_seen_loop "$SESSION_DIR/network.log" "$SESSION_DIR/.seen_net" \
            '\''firejail_conns'\'' 2
    '
}

monitor_processes() {
    log_verbose "Starting process monitor (first-seen sandboxes)..."
    spawn_monitor "processes" '
        sleep 0.5
        first_seen_loop "$SESSION_DIR/processes.log" "$SESSION_DIR/.seen_fj" \
            '\''firejail --list 2>/dev/null'\'' 8
    '
}

monitor_resources() {
    log_verbose "Starting resource monitor..."
    spawn_monitor "resources" '
        sleep 0.5
        while true; do
            ts="$(date "+%Y-%m-%d %H:%M:%S.%3N")"
            resources=$(ps auxww 2>/dev/null | grep "[j]ava" | grep -v "grep" | \
                awk "{printf \"[CPU: %s%% | MEM: %s%% | VSZ: %s KB | RSS: %s KB] %s\n\", \$3, \$4, \$5, \$6, \$11}")
            if [ -n "$resources" ]; then
                printf "[%s] %s\n" "$ts" "$resources" >> "$SESSION_DIR/resources.log"
            fi
            sleep 2
        done
    '
}

monitor_java_processes() {
    log_verbose "Starting Java process monitor (first-seen)..."
    spawn_monitor "java" '
        sleep 0.5
        first_seen_loop "$SESSION_DIR/java-processes.log" "$SESSION_DIR/.seen_java" \
            '\''ps -ww -eo args= 2>/dev/null | grep -E "[j]ava" | grep -v "grep" | grep -v "tlauncher-mon"'\'' 2
    '
}

monitor_suspicious_dirs() {
    log_verbose "Starting suspicious directory monitor..."
    spawn_monitor "suspicious" '
        suspicious=(".mozilla" ".firefox" ".config/google-chrome" ".config/chromium" ".cache" ".gnupg")
        sleep 1
        while true; do
            ts="$(date "+%Y-%m-%d %H:%M:%S.%3N")"
            for dir in "${suspicious[@]}"; do
                if [ -d "${SANDBOX_DIR}/${dir}" ]; then
                    if ! grep -q "DETECTED: ${dir}\$" "${SESSION_DIR}/suspicious.log" 2>/dev/null; then
                        file_count=$(find "${SANDBOX_DIR}/${dir}" -type f 2>/dev/null | wc -l)
                        dir_size=$(du -sh "${SANDBOX_DIR}/${dir}" 2>/dev/null | cut -f1)
                        {
                            printf "[%s] DETECTED: %s\n" "$ts" "$dir"
                            printf "[%s]   Location: %s\n" "$ts" "${SANDBOX_DIR}/${dir}"
                            printf "[%s]   Files: %s\n" "$ts" "$file_count"
                            printf "[%s]   Size: %s\n\n" "$ts" "$dir_size"
                        } >> "${SESSION_DIR}/suspicious.log"
                    fi
                fi
            done
            sleep 3
        done
    '
}

monitor_mitmproxy() {
    # -P/--proxy: opt-in HTTP(S) capture, optional. No mitmdump means the flag
    # turns off for this run & the launch continues. A missing optional dependency
    # never aborts the whole thing.
    if ! command -v mitmdump >/dev/null 2>&1; then
        log_warn "mitmdump not found; -P/--proxy disabled for this run."
        log_warn "Install manually (no sudo for the script itself): pip install mitmproxy --break-system-packages"
        PROXY_ENABLED=false
        return 1
    fi
    if [ "$OFFLINE_MODE" = true ]; then
        log_warn "-P/--proxy with -n/--offline: sandbox has no network, nothing will be captured."
    fi
    log_msg "Starting mitmproxy capture on 127.0.0.1:${PROXY_PORT} (flow → mitm.flow)"
    # exec replaces the tag-bash with mitmdump; $! stays valid for kill_tree, &
    # -K still matches it through the "mitmdump .*tlauncher-logs" pattern.
    spawn_monitor "mitm" '
        exec mitmdump -p "$PROXY_PORT" -w "$SESSION_DIR/mitm.flow" --flow-detail 1 \
            > "$SESSION_DIR/mitm.log" 2>&1
    '
}

# ==========================================
# EXECUTION
# ==========================================

run_sandboxed() {
    local firejail_params
    mapfile -t firejail_params < <(build_firejail_params)

    # Build the in-sandbox java command & pick the -P backend.
    #
    # WHY a Java agent: TLauncher's requests go through Apache HttpClient (4.x in the
    # starter JVMs, 5.x in the launcher JVM), which ignores -Dhttp.proxyHost & the
    # HTTP_PROXY env vars, so mitmproxy captured zero. The agent (scripts/TLHttpAgent.java,
    # built into the gitignored fat JAR) hooks the request methods in-process, after TLS
    # decrypt. It never modifies traffic. Without the JAR we fall back to mitmproxy.
    #
    # WHY JAVA_TOOL_OPTIONS with ABSOLUTE paths (Phase 1): the starter forks two more
    # JVMs (the re-exec & the embedded JRE) from a different cwd, & a -javaagent on the
    # starter command alone misses them. JAVA_TOOL_OPTIONS is inherited by all three.
    # But an inherited RELATIVE path resolves against each JVM's own cwd & silently
    # fails to load, so the paths are absolute inside the sandbox. firejail --private
    # mounts SANDBOX_DIR at the real HOME, so bin/ & tmp/ live at ${REAL_HOME}/bin &
    # ${REAL_HOME}/tmp there. The agent self-disables on the Minecraft JVM & writes one
    # log per PID; run.sh aggregates them after the run.
    local java_opts=""
    local agent_active=false
    local agent_env=()
    # Two jars: the -javaagent jar (Byte Buddy, app loader) & the bootstrap jar (logger
    # only, appended to the bootstrap loader by premain). Both must sit in the same dir
    # inside the sandbox, since premain finds the bootstrap jar next to its own.
    local agent_jar="${SCRIPT_DIR}/scripts/tl-http-agent.jar"
    local boot_jar="${SCRIPT_DIR}/scripts/tl-http-bootstrap.jar"
    if [ "$PROXY_ENABLED" = true ]; then
        if [ -f "$agent_jar" ] && [ -f "$boot_jar" ]; then
            cp "$agent_jar" "${SANDBOX_DIR}/bin/tl-http-agent.jar"
            cp "$boot_jar" "${SANDBOX_DIR}/bin/tl-http-bootstrap.jar"
            # Drop any per-PID logs an earlier run left in the reused sandbox tmp, so this
            # session's aggregate & report describe only this run.
            reset_agent_tmp "${SANDBOX_DIR}/tmp"
            local in_jar="${REAL_HOME}/bin/tl-http-agent.jar"
            local in_dir="${REAL_HOME}/tmp"
            agent_env=(--env="JAVA_TOOL_OPTIONS=-javaagent:${in_jar} -Dtl.intercept.dir=${in_dir}")
            agent_active=true
            log_verbose "  → Java agent active (all JVMs); logs → $(disp_path "${SESSION_DIR}/http-intercept.log")"
        else
            java_opts="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=${PROXY_PORT} -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=${PROXY_PORT}"
            log_warn "Java agent JARs not found. Build them once (works from any cwd):"
            log_warn "  bash $(disp_path "$SCRIPT_DIR")/scripts/build-agent.sh"
            log_warn "Falling back to mitmproxy (env-proxy-aware traffic only; misses HttpClient5)."
        fi
    fi
    local java_cmd="java ${java_opts} -jar bin/TLauncher.jar"

    # The agent env rides on every JVM the sandbox starts (2.1). Each JVM prints
    # "Picked up JAVA_TOOL_OPTIONS: ..." to stderr; we accept that (a few lines that
    # confirm the agent env is set) rather than pipe the launch through a filter that
    # could swallow its exit code (2.4).
    if [ "${#agent_env[@]}" -gt 0 ]; then
        firejail_params+=("${agent_env[@]}")
    fi

    # Record the capture mode as a DATUM the report reads, instead of the report
    # guessing it from a file's absence (which made it claim "-P not used" during an
    # active agent session). One word: agent, mitmproxy, or off. Pure report
    # metadata; it changes nothing about what runs inside the sandbox. The fallback
    # branch only runs when the preflight already confirmed mitmdump, so "mitmproxy"
    # here is accurate.
    if session_logging_active; then
        if [ "$agent_active" = true ]; then
            printf 'agent\n' > "${SESSION_DIR}/capture-mode"
        elif [ "$PROXY_ENABLED" = true ]; then
            printf 'mitmproxy\n' > "${SESSION_DIR}/capture-mode"
        else
            printf 'off\n' > "${SESSION_DIR}/capture-mode"
        fi
    fi

    # Log firejail command
    if session_logging_active; then
        {
            printf "# Firejail Command\n"
            printf "# Timestamp: %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"
            printf "# Note: --private mounts sandbox as new HOME\n"
            printf "firejail"
            printf " %s" "${firejail_params[@]}"
            printf " bash -c '%s'\n" "$java_cmd"
        } > "${SESSION_DIR}/firejail-command.txt"
    fi

    # ----------------------------------------------------------------------
    # WHY (the critical fix): this block used to sit inside a ( ... ) 200>"$LOCKFILE"
    # subshell. MONITOR_PIDS is a global array, but the monitor_* helpers ran inside
    # that subshell, so the PIDs they appended never reached the parent shell. The
    # cleanup loop then iterated an empty array & every background monitor got
    # orphaned. That's what contaminated old logs; a stray inotifywait grew one
    # files.log to 51 MB.
    #
    # The fix: hold the lock on an exec'd fd in the current shell. The monitors,
    # MONITOR_PIDS, & the code that kills them now share one scope.
    # ----------------------------------------------------------------------
    exec 200>"$LOCKFILE"
    flock -n 200 || die "TLauncher already running (lockfile exists)"

    # Export the handful of vars the (separate-process) monitors reference.
    export SANDBOX_DIR SESSION_DIR SESSION_ID NOISE_REGEX PROXY_PORT SANDBOX_HOSTNAME

    if [ "$MONITOR_ENABLED" = true ]; then
        log_msg "Starting all monitors..."

        monitor_filesystem
        monitor_network
        monitor_processes
        monitor_resources
        monitor_java_processes
        monitor_suspicious_dirs

        sleep 1
        log_msg "All monitors active (PIDs: ${MONITOR_PIDS[*]})"
    fi

    # mitmproxy only runs as the fallback: when the agent is handling -P there's
    # nothing for it to do (HttpClient5 ignores the proxy anyway).
    if [ "$PROXY_ENABLED" = true ] && [ "$agent_active" != true ]; then
        monitor_mitmproxy || true
    fi

    # Start line, always printed: log_msg writes to stderr no matter the -v state.
    # The no-flag sandbox-only run is a real mode, not a gap in the defaults, so a
    # bare `./run.sh` never looks dead. It gets its own message.
    if session_logging_active; then
        log_msg "Launching TLauncher in sandbox..."
    else
        log_msg "Launching TLauncher in sandbox (no monitoring, use -M to enable)..."
    fi

    # Run firejail. errexit is disabled around this block so a non-zero TLauncher
    # exit does not skip monitor cleanup / report generation.
    local exit_code=0
    set +e
    if [ "$VERBOSE" = true ]; then
        if session_logging_active; then
            firejail "${firejail_params[@]}" \
                bash -c "$java_cmd" \
                2>&1 | tee "${SESSION_DIR}/tlauncher.log"
            exit_code=${PIPESTATUS[0]}
        else
            firejail "${firejail_params[@]}" \
                bash -c "$java_cmd"
            exit_code=$?
        fi
    else
        if session_logging_active; then
            firejail "${firejail_params[@]}" \
                bash -c "$java_cmd" \
                > "${SESSION_DIR}/tlauncher.log" 2>&1
            exit_code=$?
        else
            firejail "${firejail_params[@]}" \
                bash -c "$java_cmd" \
                >/dev/null 2>&1
            exit_code=$?
        fi
    fi
    set -e

    # End line, always printed, to match the start line. Even the silent
    # sandbox-only mode confirms it finished & shows a non-zero exit code.
    log_msg "TLauncher exited (code: $exit_code)"

    if session_logging_active; then
        log_msg "Stopping monitors..."

        stop_monitors

        log_verbose "All monitors stopped"

        # The agent writes one log per JVM inside the sandbox (firejail --private
        # walls it off from SESSION_DIR). aggregate_agent_logs copies the per-PID logs
        # out in JVM start order with a per-PID banner; each file is internally
        # consistent, so a four-line request block is never split (2.2), & the starter
        # reads before the launcher instead of after the game JVMs. The aggregate stays
        # empty when the agent caught nothing, so the report can tell "agent active, no
        # requests" from "agent not used". agent-diag.log says which HttpClient/
        # HttpService classes each JVM saw.
        if [ "$agent_active" = true ]; then
            aggregate_agent_logs "${SANDBOX_DIR}/tmp/http-intercept-*.log" \
                > "${SESSION_DIR}/http-intercept.log" 2>/dev/null \
                || : > "${SESSION_DIR}/http-intercept.log"
            aggregate_agent_logs "${SANDBOX_DIR}/tmp/agent-diag-*.log" \
                > "${SESSION_DIR}/agent-diag.log" 2>/dev/null || true
        fi

        # Take post-execution snapshot
        {
            printf "# Post-execution snapshot\n"
            printf "# Timestamp: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
            find "$SANDBOX_DIR" -printf "%T@ %M %u %g %s %p\n" 2>/dev/null | sort
        } > "${SESSION_DIR}/snapshot-after.txt"

        # Generate summary, timeline and the aggregated incident report.
        generate_summary
        generate_timeline "$SESSION_DIR"
        generate_incident_report "$SESSION_DIR"

        # Auto-analyze if requested
        if [ "$AUTO_ANALYZE" = true ]; then
            printf "\n"
            analyze_session "$SESSION_DIR"
        else
            printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            printf "${GREEN}✓${NC} Session complete\n"
            printf "${BLUE}Logs:${NC} %s\n" "$(disp_path "$SESSION_DIR")"
            printf "${BLUE}Report:${NC} %s/INCIDENT_REPORT.md\n" "$(disp_path "$SESSION_DIR")"
            printf "${BLUE}Analyze with:${NC} $0 -A\n"
            printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        fi
    fi

    return $exit_code
}

# Return the preferred filesystem-event log for a session: signal.log (noise
# filtered) when present, else files.log (older sessions / lossless fallback).
fs_event_log() {
    local s="$1"
    if [ -s "${s}/signal.log" ]; then
        printf "%s" "${s}/signal.log"
    else
        printf "%s" "${s}/files.log"
    fi
}

# Extract the domains TLauncher probed, from a session's tlauncher.log. The real
# lines read:
#   "... check internet connection https://repo.tlauncher.org/check.bin timeout ..."
# & a ConsoleSubscriber wrapper sometimes nests them, but the URL still shows up,
# so one grep over the whole line catches it. Text only, no network.
extract_session_domains() {
    local log="$1"
    [ -s "$log" ] || return 0
    grep -oE 'check internet connection https?://[^/ ]+' "$log" 2>/dev/null \
        | sed -E 's#.*https?://##' | sort -u
}

# -B/--save-baseline: build the baseline files from a session the user trusts, so
# later runs can diff against them. It writes the same files the user could type by
# hand, under XDG_DATA_HOME.
save_baseline() {
    local session="$1"
    [ -d "$session" ] || die "save-baseline: session directory not found: $session"
    mkdir -p "$(dirname "$BASELINE_DOMAINS")"

    local domains; domains="$(extract_session_domains "${session}/tlauncher.log")"
    if [ -n "$domains" ]; then
        printf '%s\n' "$domains" > "$BASELINE_DOMAINS"
        log_msg "Wrote $(printf '%s\n' "$domains" | grep -c .) domain(s) to $(disp_path "$BASELINE_DOMAINS")"
    else
        log_warn "No 'check internet connection' lines in ${session}/tlauncher.log; domain baseline not written."
        log_warn "(Domain extraction needs a -M or -P session's tlauncher.log.)"
    fi

    if [ -s "${session}/network.log" ]; then
        grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "${session}/network.log" 2>/dev/null | sort -u > "$BASELINE_IPS"
        log_msg "Wrote $(grep -c . "$BASELINE_IPS") IP(s) to $(disp_path "$BASELINE_IPS")"
    else
        log_warn "No network.log in $session; IP baseline left unchanged."
    fi
}

# Helper: summarize a mitmproxy flow via scripts/mitm_report.py, or a distinct note
# at each degrade step. Only report_network_capture's mitmproxy branch calls this,
# where -P WAS used, so there is no "run without -P" guess here anymore. The flow
# parsing lives in its own file so the mitmproxy logic stays out of run.sh.
_report_mitm_flow() {
    local session="$1"
    local flow="${session}/mitm.flow"
    if [ ! -f "$flow" ]; then
        printf "_No \`mitm.flow\` was written; mitmproxy started but recorded nothing._\n\n"
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        printf "_python3 not available to summarize; raw flow saved at \`mitm.flow\`._\n\n"
        return 0
    fi
    local helper="${SCRIPT_DIR}/scripts/mitm_report.py"
    if [ ! -f "$helper" ]; then
        printf "_Helper \`scripts/mitm_report.py\` not found next to run.sh; raw flow at \`mitm.flow\`._\n\n"
        return 0
    fi
    MITM_ALLOW="$(IFS=,; printf '%s' "${MITM_ALLOWLIST[*]}")" \
    MITM_TRUNCATE="2048" \
    python3 "$helper" "$flow" 2>/dev/null \
        || printf "_Could not parse mitm.flow (is the mitmproxy python module installed?). Raw flow at \`mitm.flow\`._\n"
    printf "\n"
}

# Markdown section: domain regression against the curated baseline (Task 3). Text
# comparison only, no extra network & no outbound telemetry. It flags a first-seen
# domain, & harder, any domain matching a known risk pattern even when baselined.
report_regression_check() {
    local session="$1"
    local log="${session}/tlauncher.log"
    printf "## Regression check\n\n"
    if [ ! -s "$log" ]; then
        printf "_No \`tlauncher.log\` for this session (sandbox-only run, or a pre-2.5 session); domain regression check skipped._\n\n"
        return 0
    fi
    local domains; domains="$(extract_session_domains "$log")"
    if [ -z "$domains" ]; then
        printf "_No domain-probe lines found in tlauncher.log; nothing to compare._\n\n"
        return 0
    fi

    # Risk-pattern domains seen this session, flagged whether or not they're in the
    # baseline, because these are the fallback & telemetry hosts the author distrusts.
    if [ -n "$RISK_DOMAIN_REGEX" ]; then
        local risky; risky="$(printf '%s\n' "$domains" | grep -E "$RISK_DOMAIN_REGEX" || true)"
        if [ -n "$risky" ]; then
            printf "**🚨 Known risk-pattern domains contacted this session:**\n\n\`\`\`\n%s\n\`\`\`\n\n" "$risky"
        fi
    fi

    if [ -f "$BASELINE_DOMAINS" ]; then
        printf "_Compared against domain baseline: \`%s\`_\n\n" "$BASELINE_DOMAINS"
        local newdoms; newdoms="$(comm -23 <(printf '%s\n' "$domains" | sort -u) <(sort -u "$BASELINE_DOMAINS") 2>/dev/null)"
        if [ -z "$newdoms" ]; then
            printf "✓ No new domains; every contacted domain is already in the baseline.\n\n"
        else
            local d
            while IFS= read -r d; do
                [ -z "$d" ] && continue
                if [ -n "$RISK_DOMAIN_REGEX" ] && printf '%s' "$d" | grep -qE "$RISK_DOMAIN_REGEX"; then
                    printf "🚨 NEW RISKY DOMAIN: \`%s\`\n" "$d"
                else
                    printf "⚠ NEW DOMAIN: \`%s\`\n" "$d"
                fi
            done <<< "$newdoms"
            printf "\n"
        fi
    else
        printf "_No domain baseline at \`%s\`. Create it from a session you trust with_ \`%s -B SESSION_DIR\` _(or edit by hand). Domains seen this session:_\n\n" "$BASELINE_DOMAINS" "$(basename "$0")"
        printf '```\n%s\n```\n\n' "$domains"
    fi
}

# ==========================================
# SUMMARY GENERATION
# ==========================================

generate_summary() {
    local summary="${SESSION_DIR}/SUMMARY.txt"
    local fslog; fslog="$(fs_event_log "$SESSION_DIR")"

    {
        printf "═══════════════════════════════════════════════════════════════════════════\n"
        printf "TLauncher Session Summary\n"
        printf "═══════════════════════════════════════════════════════════════════════════\n\n"

        printf "Session ID: %s\n" "$SESSION_ID"
        printf "Start Time: %s\n" "$(head -n1 "${SESSION_DIR}/master.log" 2>/dev/null | cut -d']' -f1 | tr -d '[' || echo 'Unknown')"
        printf "End Time: %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"

        # Files summary
        if [ -f "${SESSION_DIR}/snapshot-before.txt" ] && [ -f "${SESSION_DIR}/snapshot-after.txt" ]; then
            local new_count=$(comm -13 \
                <(awk '{print $NF}' "${SESSION_DIR}/snapshot-before.txt" 2>/dev/null | sort) \
                <(awk '{print $NF}' "${SESSION_DIR}/snapshot-after.txt" 2>/dev/null | sort) | wc -l)
            printf "Files Created: %d\n" "$new_count"
        fi

        # Network summary
        if [ -s "${SESSION_DIR}/network.log" ]; then
            local unique_ips=$(grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "${SESSION_DIR}/network.log" 2>/dev/null | sort -u | wc -l)
            printf "Unique IP Connections: %d\n" "$unique_ips"
        fi

        # File system events (from the noise-filtered signal log when available)
        if [ -s "$fslog" ]; then
            # NOTE: `grep -c` already prints 0 on no match & exits 1. The old
            # `|| echo 0` added a second 0, so the value became "0\n0" & printf %d
            # crashed under set -e. signal.log is noise-filtered & often has zero
            # MODIFY events, so this fired on normal runs. `|| true` keeps the one
            # clean 0 & swallows only the exit code.
            local total_events=$(wc -l < "$fslog" 2>/dev/null || true); total_events=${total_events:-0}
            local creates=$(grep -c "CREATE" "$fslog" 2>/dev/null || true); creates=${creates:-0}
            local modifies=$(grep -c "MODIFY" "$fslog" 2>/dev/null || true); modifies=${modifies:-0}
            local deletes=$(grep -c "DELETE" "$fslog" 2>/dev/null || true); deletes=${deletes:-0}
            printf "File System Events [%s]: %d (CREATE: %d, MODIFY: %d, DELETE: %d)\n" \
                "$(basename "$fslog")" "$total_events" "$creates" "$modifies" "$deletes"
        fi

        printf "\n═══════════════════════════════════════════════════════════════════════════\n"

    } > "$summary"

    log_verbose "Summary generated"
}

# Markdown section: the network payload capture (Phase 0). The capture MODE is read
# from a recorded datum (SESSION_DIR/capture-mode, written by run_sandboxed), not
# guessed from a file's absence. The guess was the bug: with the agent active &
# mitmproxy skipped, no mitm.flow existed, so the old report claimed "run without
# -P" one line after saying the agent was active. Four states, each with a phrase
# the other three don't share, so tests/ can assert exclusivity. Rule: no section
# claims anything about an option the user did use; missing data says so, plainly.
report_network_capture() {
    local session="$1"
    local ilog="${session}/http-intercept.log"
    local flow="${session}/mitm.flow"
    local mode; mode="$(head -n1 "${session}/capture-mode" 2>/dev/null || true)"
    printf "## Network payload capture\n\n"

    case "$mode" in
        agent)
            if [ -s "$ilog" ]; then
                # State 1: agent active, log has entries.
                printf "_Mode: Java agent, in-process after TLS decrypt. Every JVM except the game._\n\n"
                printf "| Method | Host | Path |\n|--------|------|------|\n"
                grep -E '^\[[0-9:.]+\] (GET|POST|PUT|HEAD|DELETE|PATCH|OPTIONS) ' "$ilog" \
                    | sed -E 's/^\[[0-9:.]+\] //' \
                    | awk '{m=$1; h=$2; $1=""; $2=""; sub(/^ +/,""); print "| "m" | "h" | "$0" |"}' \
                    | sort -u | head -60
                printf "\n### Flagged: POST/PUT with body\n\n"
                if grep -qE '^\[[0-9:.]+\] (POST|PUT) ' "$ilog"; then
                    awk '
                        /^\[[0-9:.]+\] (POST|PUT) / { blk=1; printf "```\n%s\n", $0; next }
                        blk && /BODY_OUT:/ { print; next }
                        blk && /STATUS:/   { print; printf "```\n\n"; blk=0; next }
                    ' "$ilog"
                else
                    printf "_No POST/PUT with a body observed._\n"
                fi
                printf "\n"
            else
                # State 2: agent active, log empty.
                printf "_Mode: Java agent active, but it logged no HTTP requests._\n"
                printf "_TLauncher may route through an HTTP class the matcher misses, or a hook may have failed to bind, or it made no outbound HTTP. Check_ \`agent-diag.log\` _for each JVM: a_ \`SAW\` _line names a class the agent found, a missing_ \`HOOKED\` _or an_ \`ERROR\` _line says the hook did not take. See_ \`AGENTS.md\` _Known gaps._\n\n"
            fi
            ;;
        mitmproxy)
            # State 4: fallback used, with its limit declared before the data.
            printf "_Mode: mitmproxy fallback (agent JAR not built). It captures env-proxy-aware traffic only & misses HttpClient5, so it can show nothing even when TLauncher sent data._\n\n"
            _report_mitm_flow "$session"
            ;;
        *)
            if [ -n "$mode" ]; then
                # State 3: mode recorded as off; no -P backend ran this session.
                printf "_Mode: no HTTP capture ran this session._\n"
                printf "_To capture, build the agent (\`bash scripts/build-agent.sh\`) then run with \`-P\`._\n\n"
            else
                # No recorded mode (session predates v2.10). State on-disk facts, invent no cause.
                local il="absent" fl="absent"
                [ -f "$ilog" ] && { [ -s "$ilog" ] && il="present, non-empty" || il="present, empty"; }
                [ -f "$flow" ] && fl="present"
                printf "_Capture mode not recorded (session predates v2.10); no cause claimed._\n"
                printf "_On disk: \`http-intercept.log\` %s, \`mitm.flow\` %s._\n\n" "$il" "$fl"
            fi
            ;;
    esac
}

# ==========================================
# INCIDENT REPORT (aggregated, KB-sized)
# ==========================================

generate_incident_report() {
    local session="${1:-${SESSION_DIR:-}}"
    if [ -z "$session" ]; then
        log_error "generate_incident_report: no session directory given"
        return 1
    fi
    if [ ! -d "$session" ]; then
        log_error "generate_incident_report: session not found: $session"
        return 1
    fi

    local report="${session}/INCIDENT_REPORT.md"
    local baseline="$BASELINE_IPS"
    local fslog; fslog="$(fs_event_log "$session")"

    {
        printf "# TLauncher Sandbox: Incident Report\n\n"
        printf -- "- Session: \`%s\`\n" "$(basename "$session")"
        printf -- "- Generated: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        printf -- "- Filesystem source: \`%s\`\n\n" "$(basename "$fslog")"

        # --- New processes (first-seen) ---
        printf "## New processes observed\n\n"
        local any_proc=false
        if [ -f "${session}/java-processes.log" ] && grep -q "NEW:" "${session}/java-processes.log" 2>/dev/null; then
            printf '```\n'
            grep "NEW:" "${session}/java-processes.log" 2>/dev/null | head -40
            printf '```\n'
            any_proc=true
        fi
        if [ -f "${session}/processes.log" ] && grep -q "NEW:" "${session}/processes.log" 2>/dev/null; then
            printf "\n_Sandboxes:_\n\n\`\`\`\n"
            grep "NEW:" "${session}/processes.log" 2>/dev/null | head -20
            printf '```\n'
            any_proc=true
        fi
        [ "$any_proc" = true ] || printf "_None recorded._\n"
        printf "\n"

        # --- Network endpoints vs baseline ---
        printf "## Network endpoints\n\n"
        if [ -s "${session}/network.log" ]; then
            local ips; ips="$(grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "${session}/network.log" 2>/dev/null | sort -u)"
            if [ -f "$baseline" ]; then
                printf "_Compared against baseline: \`%s\`_\n\n" "$baseline"
                local newips; newips="$(comm -23 <(printf '%s\n' "$ips") <(sort -u "$baseline") 2>/dev/null)"
                if [ -n "$newips" ]; then
                    printf "**IPs NOT in baseline (review these):**\n\n\`\`\`\n%s\n\`\`\`\n" "$newips"
                else
                    printf "_All observed IPs are present in the baseline._\n"
                fi
            else
                printf "_No baseline file at \`%s\`; listing every observed IP. Populate that file from a run you consider clean to enable diffing._\n\n" "$baseline"
                printf '```\n%s\n```\n' "${ips:-(none)}"
            fi
        else
            printf "_No network activity logged._\n"
        fi
        printf "\n"

        # --- New files (noise-filtered) ---
        printf "## New files created (noise-filtered)\n\n"
        if [ -s "$fslog" ]; then
            local nf; nf="$(grep -E "CREATE|MOVED_TO" "$fslog" 2>/dev/null | awk '{print $NF}' | sort -u)"
            if [ -n "$nf" ]; then
                local total; total="$(printf '%s\n' "$nf" | grep -c . || true)"; total=${total:-0}
                printf '```\n%s\n```\n' "$(printf '%s\n' "$nf" | head -60)"
                [ "$total" -gt 60 ] && printf "\n_%d more files in signal.log / files.log._\n" "$((total - 60))"
            else
                printf "_None._\n"
            fi
        else
            printf "_No filesystem event log for this session._\n"
        fi
        printf "\n"

        # --- Mozilla / browser data check ---
        printf "## Browser data (.mozilla) check\n\n"
        if [ -d "${SANDBOX_DIR}/.mozilla" ]; then
            local mfiles; mfiles="$(find "${SANDBOX_DIR}/.mozilla" -type f 2>/dev/null | wc -l)"
            if [ "$mfiles" -eq 0 ]; then
                printf "⚠ \`.mozilla\` exists in sandbox but is empty (likely benign).\n"
            else
                printf "🚨 \`.mozilla\` exists in sandbox with **%d files**; inspect it by hand.\n" "$mfiles"
            fi
        else
            printf "✓ No \`.mozilla\` directory in sandbox.\n"
        fi
        printf "\n"

        # --- Network payload summary (Task 2) + domain regression (Task 3) ---
        report_network_capture "$session"
        report_regression_check "$session"

        # --- Sizes (growth sanity check) ---
        printf "## Sizes\n\n"
        printf -- "- Session dir: %s\n" "$(du -sh "$session" 2>/dev/null | cut -f1 || echo '?')"
        printf -- "- Sandbox dir: %s\n" "$(du -sh "$SANDBOX_DIR" 2>/dev/null | cut -f1 || echo '?')"
        printf "\n"

    } > "$report"

    log_verbose "Incident report generated: $report"
}

# ==========================================
# TIMELINE
# ==========================================

generate_timeline() {
    local session="$1"
    local timeline="${session}/TIMELINE.txt"
    local fslog; fslog="$(fs_event_log "$session")"

    {
        printf "═══════════════════════════════════════════════════════════════════════════\n"
        printf "Event Timeline - Session $(basename "$session")\n"
        printf "═══════════════════════════════════════════════════════════════════════════\n\n"

        # Combine all timestamped events
        local temp_timeline=$(mktemp)

        # Files (limit to important events, from the noise-filtered log)
        if [ -f "$fslog" ] && [ -s "$fslog" ]; then
            grep -E "CREATE|DELETE" "$fslog" 2>/dev/null | sed 's/^/[FILE] /' >> "$temp_timeline" || true
        fi

        # Network
        if [ -f "${session}/network.log" ] && [ -s "${session}/network.log" ]; then
            grep '^\[' "${session}/network.log" 2>/dev/null | sed 's/^/[NET]  /' >> "$temp_timeline" || true
        fi

        # Suspicious dirs
        if [ -f "${session}/suspicious.log" ] && [ -s "${session}/suspicious.log" ]; then
            sed 's/^/[SUSP] /' "${session}/suspicious.log" 2>/dev/null >> "$temp_timeline" || true
        fi

        # Java processes (first-seen events)
        if [ -f "${session}/java-processes.log" ] && [ -s "${session}/java-processes.log" ]; then
            grep '^\[' "${session}/java-processes.log" 2>/dev/null | head -20 | sed 's/^/[JAVA] /' >> "$temp_timeline" || true
        fi

        if [ -s "$temp_timeline" ]; then
            sort "$temp_timeline" 2>/dev/null | head -100 || cat "$temp_timeline" | head -100
            local total_events=$(wc -l < "$temp_timeline" 2>/dev/null || echo 0)
            if [ "$total_events" -gt 100 ]; then
                printf "\n(Showing first 100 of %d events - see individual logs for complete data)\n" "$total_events"
            fi
        else
            printf "No timeline events recorded.\n"
        fi

        rm -f "$temp_timeline"

    } > "$timeline" 2>/dev/null || true

    log_verbose "Timeline generated"
}

# ==========================================
# LOG RETENTION
# ==========================================

# cleanup_logs [DAYS] [SILENT]
# - Compress every session older than DAYS into logs.tar.gz, keeping SUMMARY.txt
#   and INCIDENT_REPORT.md uncompressed for quick reading.
# - If the whole log root exceeds LOG_SIZE_CAP_MB, delete already-compressed
#   sessions older than 2*DAYS.
# WHY: prevents the silent multi-GB accumulation that motivated this rewrite.
cleanup_logs() {
    local days="${1:-$CLEANUP_DAYS}" silent="${2:-false}"
    local root="$LOG_ROOT"

    if [ ! -d "$root" ]; then
        [ "$silent" = true ] || log_msg "No log directory to clean: $root"
        return 0
    fi

    # 1) Compress old, not-yet-compressed sessions.
    local d
    while IFS= read -r d; do
        [ -z "$d" ] && continue
        [ -f "${d}/logs.tar.gz" ] && continue   # already compressed
        [ "$silent" = true ] || log_msg "Compressing old session: $(basename "$d")"
        (
            cd "$d" || exit 0
            # Everything EXCEPT the quick-read reports and the archive itself.
            local files=()
            local f
            for f in $(ls -A 2>/dev/null); do
                case "$f" in
                    SUMMARY.txt|INCIDENT_REPORT.md|logs.tar.gz) ;;
                    *) files+=("$f") ;;
                esac
            done
            if [ "${#files[@]}" -gt 0 ]; then
                tar -czf logs.tar.gz --remove-files "${files[@]}" 2>/dev/null || true
            fi
        ) || true
    done < <(find "$root" -maxdepth 1 -type d -name 'session_*' -mtime +"$days" 2>/dev/null)

    # 2) If over the size cap, drop compressed sessions older than 2*DAYS.
    local total_mb
    total_mb="$(du -sm "$root" 2>/dev/null | cut -f1)"
    if [ -n "$total_mb" ] && [ "$total_mb" -gt "$LOG_SIZE_CAP_MB" ]; then
        [ "$silent" = true ] || log_warn "Log dir ${total_mb}MB > ${LOG_SIZE_CAP_MB}MB cap; pruning old compressed sessions."
        while IFS= read -r d; do
            [ -z "$d" ] && continue
            if [ -f "${d}/logs.tar.gz" ]; then
                [ "$silent" = true ] || log_warn "Removing: $(basename "$d")"
                rm -rf "$d"
            fi
        done < <(find "$root" -maxdepth 1 -type d -name 'session_*' -mtime +"$((days * 2))" 2>/dev/null)
    fi
}

# ==========================================
# ANALYSIS
# ==========================================

analyze_session() {
    local session="${1:-}"

    # If no session provided, find latest
    if [ -z "$session" ] || [ ! -d "$session" ]; then
        session=$(find "${LOG_ROOT}" -maxdepth 1 -type d -name "session_*" 2>/dev/null | sort -r | head -n1)
        if [ -z "$session" ]; then
            log_error "No session found to analyze"
            printf "${YELLOW}Tip: Run with -M to enable monitoring${NC}\n" >&2
            return 1
        fi
    fi

    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}Session Analysis${NC}\n"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

    printf "Session: ${BLUE}$(basename "$session")${NC}\n\n"

    # Show summary if exists
    if [ -f "${session}/SUMMARY.txt" ]; then
        cat "${session}/SUMMARY.txt"
        printf "\n"
    fi

    # Prefer the aggregated incident report when present.
    if [ -f "${session}/INCIDENT_REPORT.md" ]; then
        printf "${BLUE}Incident report:${NC} %s/INCIDENT_REPORT.md\n\n" "$(disp_path "$session")"
    fi

    # Filesystem changes
    printf "${YELLOW}┌── Filesystem Changes ──┐${NC}\n\n"
    if [ -f "${session}/snapshot-before.txt" ] && [ -f "${session}/snapshot-after.txt" ]; then
        local new_files
        new_files=$(comm -13 \
            <(awk '{print $NF}' "${session}/snapshot-before.txt" 2>/dev/null | sort) \
            <(awk '{print $NF}' "${session}/snapshot-after.txt" 2>/dev/null | sort) || true)

        local new_count=$(printf "%s" "$new_files" | grep -c . || true); new_count=${new_count:-0}

        if [ "$new_count" -gt 0 ]; then
            printf "${YELLOW}New files: %d${NC}\n\n" "$new_count"

            # Check for suspicious patterns
            if printf "%s" "$new_files" | grep -qE "\.(mozilla|firefox|chrome)"; then
                printf "${RED}⚠ WARNING: Browser directories detected!${NC}\n"
                printf "%s\n" "$new_files" | grep -E "\.(mozilla|firefox|chrome)" | sed 's/^/  /'
                printf "\n"
            fi

            if printf "%s" "$new_files" | grep -qE "\.jar$"; then
                printf "${YELLOW}ℹ New JAR files (updates):${NC}\n"
                printf "%s\n" "$new_files" | grep "\.jar$" | sed 's/^/  /'
                printf "\n"
            fi

            # Show first 20 files
            printf "${BLUE}Recent files (first 20):${NC}\n"
            printf "%s\n" "$new_files" | head -20 | sed 's/^/  /'
            if [ "$new_count" -gt 20 ]; then
                printf "  ... and %d more\n" $((new_count - 20))
            fi
        else
            printf "${GREEN}✓ No new files created${NC}\n"
        fi
    fi

    # Network activity
    printf "\n${YELLOW}┌── Network Activity ──┐${NC}\n\n"
    if [ -s "${session}/network.log" ]; then
        local ips
        ips=$(grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "${session}/network.log" 2>/dev/null | sort -u || true)
        local ip_count=$(printf "%s" "$ips" | grep -c . || true); ip_count=${ip_count:-0}

        if [ "$ip_count" -gt 0 ]; then
            printf "${BLUE}Unique IPs contacted: %d${NC}\n\n" "$ip_count"
            printf "%s\n" "$ips" | sed 's/^/  /' | head -20
            if [ "$ip_count" -gt 20 ]; then
                printf "  ... and %d more\n" $((ip_count - 20))
            fi
        else
            printf "${YELLOW}⚠ No IPs captured (connections may have been too fast)${NC}\n"
            printf "${BLUE}Tip: Check files.log for actual network activity patterns${NC}\n"
        fi
    else
        printf "${GREEN}✓ No network activity logged${NC}\n"
    fi

    # Resource usage
    printf "\n${YELLOW}┌── Resource Usage ──┐${NC}\n\n"
    if [ -s "${session}/resources.log" ]; then
        printf "${BLUE}Peak resource usage:${NC}\n"
        awk -F'[|:]' '
            {
                gsub(/CPU: | |%/, "", $2); gsub(/MEM: | |%/, "", $3);
                cpu = $2 + 0; mem = $3 + 0;
                if (cpu > max_cpu) max_cpu = cpu;
                if (mem > max_mem) max_mem = mem;
            }
            END {
                if (max_cpu > 0 || max_mem > 0) {
                    printf "  CPU: %.1f%%\n  Memory: %.1f%%\n", max_cpu, max_mem
                } else {
                    print "  (no data captured)"
                }
            }
        ' "${session}/resources.log" 2>/dev/null || printf "  (parsing failed)\n"
    else
        printf "${YELLOW}⚠ No resource data captured${NC}\n"
    fi

    # Suspicious directories
    printf "\n${YELLOW}┌── Suspicious Directory Detection ──┐${NC}\n\n"
    if [ -s "${session}/suspicious.log" ]; then
        printf "${RED}⚠ ALERT: Suspicious directories detected!${NC}\n\n"
        cat "${session}/suspicious.log"
        printf "\n${YELLOW}Note: .cache is normal, but .mozilla/.firefox would be suspicious${NC}\n"
    else
        printf "${GREEN}✓ No suspicious directories detected${NC}\n"
    fi

    # Java subprocess activity
    printf "\n${YELLOW}┌── Java Process Activity ──┐${NC}\n\n"
    if [ -s "${session}/java-processes.log" ]; then
        local unique_jars=$(grep -oE '/[^ ]+\.jar' "${session}/java-processes.log" 2>/dev/null | sort -u || true)
        if [ -n "$unique_jars" ]; then
            printf "${BLUE}JAR files executed:${NC}\n"
            printf "%s\n" "$unique_jars" | sed 's/^/  /'
            printf "\n${YELLOW}Note: Multiple JARs may indicate auto-update behavior${NC}\n"
        else
            printf "${YELLOW}⚠ No JAR processes captured${NC}\n"
        fi
    else
        printf "${YELLOW}⚠ No Java process data captured${NC}\n"
    fi

    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n${BLUE}Full logs:${NC} %s\n" "$(disp_path "$session")"
    printf "${BLUE}Available files:${NC}\n"
    ls -1 "$session" 2>/dev/null | sed 's/^/  - /' || printf "  (no files found)\n"

    # Timeline preview
    if [ -f "${session}/TIMELINE.txt" ]; then
        printf "\n${YELLOW}┌── Timeline Preview (first 10 events) ──┐${NC}\n\n"
        head -15 "${session}/TIMELINE.txt" 2>/dev/null | tail -10 || echo "  (empty)"
        printf "\n${BLUE}Full timeline:${NC} %s/TIMELINE.txt\n" "$(disp_path "$session")"
    fi

    # Mozilla check if requested
    if [ "$MOZILLA_CHECK" = true ]; then
        check_mozilla_directory
    fi

    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}Analysis complete!${NC}\n"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

check_mozilla_directory() {
    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}Mozilla Directory Check${NC}\n"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

    local sandbox_mozilla="${SANDBOX_DIR}/.mozilla"

    if [ ! -d "$sandbox_mozilla" ]; then
        printf "${GREEN}✓ .mozilla does not exist in sandbox${NC}\n"
        printf "${GREEN}  (No browser data access attempted)${NC}\n"
        return 0
    fi

    printf "${YELLOW}⚠ .mozilla directory EXISTS in sandbox${NC}\n\n"

    # Count files
    local file_count=$(find "$sandbox_mozilla" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "$sandbox_mozilla" -type d 2>/dev/null | wc -l)

    printf "Structure: %d directories, %d files\n\n" "$dir_count" "$file_count"

    if [ "$file_count" -eq 0 ]; then
        printf "${BLUE}Status: Empty structure (likely safe)${NC}\n"
    else
        printf "${RED}Status: Contains data - manual inspection recommended${NC}\n"
        printf "\nLargest files:\n"
        find "$sandbox_mozilla" -type f -printf "%s %p\n" 2>/dev/null | \
            sort -rn | head -10 | \
            awk '{printf "  %8d bytes  %s\n", $1, $2}' || echo "  (none found)"
    fi

    # Compare with real mozilla if it exists
    if [ -d "$MOZILLA_SEARCH_PATH" ]; then
        printf "\n${BLUE}Comparing with real Mozilla directory...${NC}\n"
        printf "Real path: %s\n\n" "$MOZILLA_SEARCH_PATH"

        if diff -rq "$MOZILLA_SEARCH_PATH" "$sandbox_mozilla" >/dev/null 2>&1; then
            printf "${RED}⚠⚠⚠ CRITICAL: Exact copy of real Mozilla directory!${NC}\n"
            printf "${RED}     This indicates potential data exfiltration attempt!${NC}\n"
        else
            local common_files=$(comm -12 \
                <(find "$MOZILLA_SEARCH_PATH" -type f -printf "%P\n" 2>/dev/null | sort) \
                <(find "$sandbox_mozilla" -type f -printf "%P\n" 2>/dev/null | sort) | wc -l)

            if [ "$common_files" -gt 0 ]; then
                printf "${YELLOW}Warning: %d files have matching paths${NC}\n" "$common_files"
            else
                printf "${GREEN}Different structure from real home${NC}\n"
            fi
        fi
    fi

    printf "\n"
}

# ==========================================
# CLEANUP
# ==========================================

cleanup() {
    # Stop monitors started in this run, reaping their whole process trees so no
    # inotifywait/ss/ps/mitmdump leaf survives to write into old logs. The
    # EXIT/INT/TERM trap calls this too, say when the user hits Ctrl+C mid-session,
    # so it escalates TERM then KILL like stop_monitors instead of a single TERM
    # pass. A lone TERM can lose a leaf to a reparent race & leave the exact orphan
    # this revision exists to prevent.
    if [ "${#MONITOR_PIDS[@]}" -gt 0 ]; then
        local pid
        for pid in "${MONITOR_PIDS[@]}"; do kill_tree "$pid" TERM; done
        sleep 0.3
        for pid in "${MONITOR_PIDS[@]}"; do kill_tree "$pid" KILL; done
    fi
    # Safety net: kill anything still tagged with THIS session id.
    [ -n "${SESSION_ID:-}" ] && pkill -f "tlauncher-mon-${SESSION_ID}" 2>/dev/null || true

    # Remove lockfile
    rm -f "$LOCKFILE"
}

trap cleanup EXIT INT TERM

# ==========================================
# USAGE
# ==========================================

usage() {
    printf "${CYAN}╔═════════════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║       TLauncher Sandboxed Launcher v%-8s                                  ║${NC}\n" "$VERSION"
    printf "${CYAN}╚═════════════════════════════════════════════════════════════════════════════╝${NC}\n\n"

    printf "${GREEN}✓ No root/sudo required - works without special permissions!${NC}\n\n"

    printf "${YELLOW}PURPOSE${NC}\n"
    printf "  Runs TLauncher in a secure Firejail sandbox while capturing complete\n"
    printf "  activity logs including operations that don't appear in normal logs.\n\n"

    printf "${YELLOW}USAGE${NC}\n"
    printf "  %s [OPTIONS]\n" "$0"
    printf "  ${CYAN}With no options: sandbox-only mode. It launches TLauncher in the firejail${NC}\n"
    printf "  ${CYAN}sandbox with no monitoring and no logs, printing only a start and end${NC}\n"
    printf "  ${CYAN}line to stderr. Add -M to record a session, -v to see TLauncher output.${NC}\n\n"

    printf "${YELLOW}BASIC OPTIONS${NC}\n"
    printf "  ${BLUE}-v, --verbose${NC}          Show TLauncher output + config summary + 2s countdown\n"
    printf "  ${BLUE}-n, --offline${NC}          Block ALL network (firejail --net=none)\n"
    printf "  ${BLUE}-f, --file PATH${NC}        Specify TLauncher.jar location\n"
    printf "  ${BLUE}-h, --help${NC}             Show this help and exit 0\n\n"

    printf "${YELLOW}MONITORING OPTIONS${NC}\n"
    printf "  ${BLUE}-M, --monitor${NC}          Enable monitoring + write a session under logs/:\n"
    printf "                           • Filesystem events (inotifywait → files.log, plus a\n"
    printf "                             noise-filtered signal.log)\n"
    printf "                           • Network connections (ss, first-seen → network.log)\n"
    printf "                           • Sandbox/Java processes (first-seen, not full dumps)\n"
    printf "                           • Suspicious directory detection\n"
    printf "                           • SUMMARY.txt, TIMELINE.txt and INCIDENT_REPORT.md\n"
    printf "  ${BLUE}-a, --analyze${NC}          After a -M run, print the full analysis to the\n"
    printf "                           terminal (no-op without -M; a warning is shown)\n"
    printf "  ${BLUE}-A, --analyze-only${NC}     Analyze the latest session and exit (no launch)\n\n"

    printf "${YELLOW}MAINTENANCE / REPORTING${NC}\n"
    printf "  ${BLUE}-K, --kill-orphans${NC}     Find & kill stray monitor processes from old\n"
    printf "                           sessions, then exit (does NOT launch TLauncher)\n"
    printf "  ${BLUE}-R, --report DIR${NC}       (Re)generate INCIDENT_REPORT.md for a session\n"
    printf "                           directory, then exit\n"
    printf "  ${BLUE}-B, --save-baseline DIR${NC} Derive baseline files from a session you trust\n"
    printf "                           (domains from its tlauncher.log, IPs from network.log),\n"
    printf "                           then exit. Used by the regression check below.\n"
    printf "  ${BLUE}-c, --cleanup-logs [N]${NC} Compress sessions older than N days (default %d),\n" "$CLEANUP_DAYS"
    printf "                           prune compressed ones over the %dMB cap, then exit.\n" "$LOG_SIZE_CAP_MB"
    printf "                           ${CYAN}This also runs automatically (silently) at the${NC}\n"
    printf "                           ${CYAN}start of every -M run so logs never balloon.${NC}\n"
    printf "  ${BLUE}--check-deps${NC}           Report each dependency (present/missing, required\n"
    printf "                           vs optional, what it's for) & refresh the state file,\n"
    printf "                           then exit 0 if all required are present, 1 if not.\n"
    printf "  ${CYAN}-K/-R/-c/-B/--check-deps/-A are standalone: they do their job and exit${NC}\n"
    printf "  ${CYAN}without launching TLauncher. If several are given, the first wins.${NC}\n\n"

    printf "${YELLOW}NETWORK CAPTURE (opt-in, no sudo)${NC}\n"
    printf "  ${BLUE}-P, --proxy [PORT]${NC}     Activate HTTP interception. Implies a session dir.\n"
    printf "                           With ${CYAN}scripts/tl-http-agent.jar${NC} present: loads a Java\n"
    printf "                           agent via JAVA_TOOL_OPTIONS into every JVM the sandbox\n"
    printf "                           starts (starter, re-exec, embedded JRE), & captures\n"
    printf "                           HTTP/HTTPS at the application layer where the payload is\n"
    printf "                           plain text. No CA trust needed. It self-disables on the\n"
    printf "                           Minecraft JVM (not the audit target) & hooks the\n"
    printf "                           InternalHttpClient of both HttpClient families (4.x in the\n"
    printf "                           starter, 5.x in the launcher) plus TLauncher's own\n"
    printf "                           HttpServiceImpl; a class the name matcher misses still\n"
    printf "                           slips, so check ${CYAN}agent-diag.log${NC} if empty. Writes one\n"
    printf "                           log per JVM (aggregated to http-intercept.log) & a\n"
    printf "                           'Network payload capture' report section. Each JVM prints a\n"
    printf "                           'Picked up JAVA_TOOL_OPTIONS' line to stderr; that is kept.\n"
    printf "                           Build the agent once, from the repo root (the dir\n"
    printf "                           holding run.sh): ${CYAN}bash scripts/build-agent.sh${NC}\n"
    printf "                           Without the agent JAR: falls back to mitmproxy on\n"
    printf "                           127.0.0.1:PORT (default %d), which captures env-proxy-aware\n" "$PROXY_PORT"
    printf "                           traffic only & is confirmed to miss HttpClient5. The\n"
    printf "                           fallback needs 'mitmdump' & the JVM to trust its CA\n"
    printf "                           (keytool import into a truststore); see DESIGN/AGENTS.\n\n"

    printf "${YELLOW}SECURITY CHECKS${NC}\n"
    printf "  ${BLUE}-m, --mozilla${NC}          Add a .mozilla check to the analysis output\n"
    printf "                           (takes effect with -a or -A; the incident report\n"
    printf "                           always includes a basic .mozilla check regardless)\n"
    printf "  ${BLUE}-ml, --mozilla-path P${NC}  Custom mozilla path (default: ~/.mozilla)\n\n"

    printf "${YELLOW}BASELINES & REGRESSION (text-only, no extra network)${NC}\n"
    printf "  IPs:     %s\n" "$(disp_path "$BASELINE_IPS")"
    printf "  Domains: %s\n" "$(disp_path "$BASELINE_DOMAINS")"
    printf "  ${CYAN}Populate them with '-B SESSION_DIR' from a run you consider clean (or by${NC}\n"
    printf "  ${CYAN}hand). The incident report then flags new IPs and, under 'Regression${NC}\n"
    printf "  ${CYAN}check', any first-seen domain, hard-flagging known risk patterns${NC}\n"
    printf "  ${CYAN}(e.g. advancedrepository) even if already baselined. Delete the files${NC}\n"
    printf "  ${CYAN}to reset; re-run -B to regenerate.${NC}\n\n"

    printf "${YELLOW}COMMON USAGE PATTERNS${NC}\n"
    printf "  ${GREEN}Sandbox-only (no monitoring, just run it safely):${NC}\n"
    printf "    %s\n" "$0"
    printf "    ${CYAN}→ Start/end lines on stderr, no session dir, nothing under logs/${NC}\n\n"

    printf "  ${GREEN}First time / security audit:${NC}\n"
    printf "    %s -v -M -a -m\n" "$0"
    printf "    ${CYAN}→ Full monitoring with immediate analysis${NC}\n\n"

    printf "  ${GREEN}With real HTTP(S) capture + regression:${NC}\n"
    printf "    %s -M -a -P\n" "$0"
    printf "    ${CYAN}→ Adds the network payload summary + regression check to the report${NC}\n\n"

    printf "  ${GREEN}Save a clean baseline, then reap monitors / tidy logs:${NC}\n"
    printf "    %s -B logs/session_XXXX   %s -K   %s -c 7\n\n" "$0" "$0" "$0"

    printf "  ${GREEN}Review previous session:${NC}\n"
    printf "    %s -A\n" "$0"
    printf "    ${CYAN}→ Analyze logs without running TLauncher${NC}\n\n"

    printf "${YELLOW}WHAT'S NEW${NC}\n"
    printf "  See ${BLUE}CHANGELOG.md${NC} for what changed and when. The CHANGELOG is the single\n"
    printf "  source, so this heading no longer pins a version that goes stale on each bump.\n\n"

    printf "${YELLOW}OUTPUT LOCATION${NC}\n"
    printf "  %s/session_YYYYMMDD_HHMMSS/\n\n" "$(disp_path "$LOG_ROOT")"

    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}Uses only standard Linux tools - no special permissions needed!${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

    exit 0
}

# ==========================================
# MAIN
# ==========================================

main() {
    local analyze_only=false

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -v|--verbose) VERBOSE=true; shift ;;
            -n|--offline) OFFLINE_MODE=true; shift ;;
            -M|--monitor) MONITOR_ENABLED=true; shift ;;
            -a|--analyze) AUTO_ANALYZE=true; shift ;;
            -A|--analyze-only) analyze_only=true; shift ;;
            -m|--mozilla) MOZILLA_CHECK=true; shift ;;
            -K|--kill-orphans) KILL_ORPHANS=true; shift ;;
            -R|--report)
                if [ -z "${2:-}" ]; then
                    die "--report requires a session directory argument"
                fi
                REPORT_SESSION="$2"
                shift 2
                ;;
            -c|--cleanup-logs)
                CLEANUP_LOGS_FLAG=true
                # Optional numeric [DAYS] argument.
                if [ -n "${2:-}" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    CLEANUP_DAYS="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -P|--proxy)
                PROXY_ENABLED=true
                # Optional numeric [PORT] argument.
                if [ -n "${2:-}" ] && [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    PROXY_PORT="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -B|--save-baseline)
                if [ -z "${2:-}" ]; then
                    die "--save-baseline requires a session directory argument"
                fi
                SAVE_BASELINE_SESSION="$2"
                shift 2
                ;;
            --check-deps) CHECK_DEPS=true; shift ;;
            -ml|--mozilla-path)
                if [ -z "${2:-}" ]; then
                    die "--mozilla-path requires a path argument"
                fi
                MOZILLA_SEARCH_PATH="$2"
                shift 2
                ;;
            -f|--file)
                if [ -z "${2:-}" ]; then
                    die "--file requires a path argument"
                fi
                TLAUNCHER_PATH="$2"
                shift 2
                ;;
            -h|--help) usage ;;
            -*)
                printf "${RED}Error: Unknown option '%s'${NC}\n\n" "$1" >&2
                printf "Run '${BLUE}%s --help${NC}' for usage information\n" "$0" >&2
                exit 1
                ;;
            *)
                printf "${RED}Error: Unexpected argument '%s'${NC}\n\n" "$1" >&2
                printf "If specifying TLauncher file, use: ${BLUE}-f %s${NC}\n" "$1" >&2
                printf "Run '${BLUE}%s --help${NC}' for usage\n" "$1" >&2
                exit 1
                ;;
        esac
    done

    # ---- Standalone modes that never launch TLauncher ----
    if [ "$KILL_ORPHANS" = true ]; then
        kill_orphans
        exit 0
    fi

    if [ -n "$REPORT_SESSION" ]; then
        generate_incident_report "$REPORT_SESSION"
        printf "${GREEN}✓${NC} Report: %s/INCIDENT_REPORT.md\n" "$(disp_path "$REPORT_SESSION")" >&2
        exit 0
    fi

    if [ "$CLEANUP_LOGS_FLAG" = true ]; then
        cleanup_logs "$CLEANUP_DAYS" false
        exit 0
    fi

    if [ -n "$SAVE_BASELINE_SESSION" ]; then
        save_baseline "$SAVE_BASELINE_SESSION"
        exit 0
    fi

    if [ "$CHECK_DEPS" = true ]; then
        check_deps
        exit $?
    fi

    # Proxy preflight: -P needs one of two backends. The Java agent (its built JAR)
    # is the real one; mitmproxy is the fallback. Only disable -P when NEITHER is
    # present, otherwise the fallback would inject proxy settings pointing at a dead
    # port & break TLauncher's networking. With the agent JAR, mitmdump isn't needed.
    if [ "$PROXY_ENABLED" = true ] \
       && [ ! -f "${SCRIPT_DIR}/scripts/tl-http-agent.jar" ] \
       && ! command -v mitmdump >/dev/null 2>&1; then
        log_warn "-P/--proxy needs the Java agent JAR or mitmdump; neither is present."
        log_warn "Build the agent: bash scripts/build-agent.sh   (or: pip install mitmproxy --break-system-packages)"
        PROXY_ENABLED=false
    fi

    # Validate flag combinations
    if [ "$AUTO_ANALYZE" = true ] && [ "$MONITOR_ENABLED" = false ] && [ "$analyze_only" = false ]; then
        log_warn "Flag -a (auto-analyze) requires -M (monitor) to generate logs"
        printf "${YELLOW}Tip: Use '%s -M -a' to enable both${NC}\n" "$0" >&2
        AUTO_ANALYZE=false
    fi

    # Analyze-only mode
    if [ "$analyze_only" = true ]; then
        analyze_session
        exit 0
    fi

    # Warn (do not fail) if monitors from a previous session are still alive.
    warn_orphans

    # Normal execution
    check_requirements

    # Auto-retention: keep the log dir from silently growing into the GBs.
    if [ "$MONITOR_ENABLED" = true ]; then
        cleanup_logs "$CLEANUP_DAYS" true
    fi

    local tlauncher
    tlauncher=$(find_tlauncher)

    # Setup sandbox first (always needed)
    setup_sandbox "$tlauncher"

    # Show configuration summary if verbose or session logging is active
    if [ "$VERBOSE" = true ] || session_logging_active; then
        printf "\n${CYAN}╔═════════════════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${CYAN}║                    Configuration Summary                                    ║${NC}\n"
        printf "${CYAN}╚═════════════════════════════════════════════════════════════════════════════╝${NC}\n\n"

        printf "${BLUE}Mode:${NC}            "
        if [ "$MONITOR_ENABLED" = true ]; then
            printf "${GREEN}Full Monitoring${NC}"
        else
            printf "${YELLOW}Basic Sandbox${NC}"
        fi
        printf "\n"

        printf "${BLUE}Output:${NC}          "
        if [ "$VERBOSE" = true ]; then
            printf "${GREEN}Verbose${NC}"
        else
            printf "${YELLOW}Silent${NC}"
        fi
        printf "\n"

        printf "${BLUE}Network:${NC}         "
        if [ "$OFFLINE_MODE" = true ]; then
            printf "${RED}Blocked${NC}"
        else
            printf "${GREEN}Allowed${NC}"
        fi
        printf "\n"

        printf "${BLUE}Proxy:${NC}           "
        if [ "$PROXY_ENABLED" = true ]; then
            printf "${GREEN}mitmproxy 127.0.0.1:%s${NC}" "$PROXY_PORT"
        else
            printf "${YELLOW}Off${NC}"
        fi
        printf "\n"

        printf "${BLUE}TLauncher:${NC}       %s\n" "$(disp_path "$tlauncher")"
        printf "${BLUE}Sandbox:${NC}         %s\n" "$(disp_path "$SANDBOX_DIR")"

        if session_logging_active; then
            SESSION_ID=$(date +%Y%m%d_%H%M%S)
            SESSION_DIR="${LOG_ROOT}/session_${SESSION_ID}"
            mkdir -p "$SESSION_DIR"
            printf "${BLUE}Logs:${NC}            %s\n" "$(disp_path "$SESSION_DIR")"
        fi

        printf "\n${CYAN}────────────────────────────────────────────────────────────────────────────────${NC}\n"
        printf "${YELLOW}Starting in 2 seconds... (Ctrl+C to cancel)${NC}\n"
        sleep 2
        printf "\n"
    fi

    if session_logging_active; then
        # Ensure session directory exists
        if [ -z "$SESSION_DIR" ]; then
            SESSION_ID=$(date +%Y%m%d_%H%M%S)
            SESSION_DIR="${LOG_ROOT}/session_${SESSION_ID}"
        fi
        mkdir -p "$SESSION_DIR"

        # Pre-execution snapshot (filesystem diffing) is only meaningful with -M.
        if [ "$MONITOR_ENABLED" = true ]; then
            {
                printf "# Pre-execution snapshot\n"
                printf "# Timestamp: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
                find "$SANDBOX_DIR" -printf "%T@ %M %u %g %s %p\n" 2>/dev/null | sort
            } > "${SESSION_DIR}/snapshot-before.txt"
        fi

        # Log system info
        {
            printf "# System Information\n"
            printf "# Timestamp: %s\n\n" "$(date '+%Y-%m-%d %H:%M:%S')"
            printf "User: %s (UID: %s)\n" "$REAL_USER" "$REAL_UID"
            printf "Home: %s\n" "$REAL_HOME"
            printf "Sandbox: %s\n" "$SANDBOX_DIR"
            printf "Java: %s\n" "$(java -version 2>&1 | head -n1)"
            printf "Firejail: %s\n" "$(firejail --version 2>&1 | head -n1)"
            printf "\nConfiguration:\n"
            printf "  Verbose: %s\n" "$VERBOSE"
            printf "  Offline: %s\n" "$OFFLINE_MODE"
            printf "  Monitor: %s\n" "$MONITOR_ENABLED"
            printf "  Proxy: %s (port %s)\n" "$PROXY_ENABLED" "$PROXY_PORT"
            printf "  Auto-Analyze: %s\n" "$AUTO_ANALYZE"
        } > "${SESSION_DIR}/system-info.txt"
    fi

    run_sandboxed
}

main "$@"
