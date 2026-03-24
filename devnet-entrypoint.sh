#!/usr/bin/env bash
# shellcheck shell=bash
#
# Entrypoint script for aleo-devnet container (dev/test).
# Starts leo devnet and forwards snarkOS logs to container stdout.
#
# Environment variables (all optional):
#   STORAGE           - Data directory (default: /aleo/data)
#   VERBOSITY         - Log verbosity 0-4 (default: 4)
#   NUM_VALIDATORS    - Number of validators (default: 4)
#   NUM_CLIENTS       - Number of clients (default: 1)
#   CLEAR_STORAGE     - Clear storage on start: yes/no (default: no)
#   SNARKOS_FEATURES  - snarkOS features flag (default: test_network)
#   LOG_WAIT_SECONDS  - Seconds to wait before tailing logs (default: 5)
#   LOG_POLL_INTERVAL - Seconds between log file discovery (default: 3)
#   LOG_FORWARDING    - Forward snarkOS logs to stdout: true/false (default: false)
#
set -euo pipefail

readonly STORAGE="${STORAGE:-/aleo/data}"
readonly VERBOSITY="${VERBOSITY:-4}"
readonly NUM_VALIDATORS="${NUM_VALIDATORS:-4}"
readonly NUM_CLIENTS="${NUM_CLIENTS:-1}"
readonly CLEAR_STORAGE="${CLEAR_STORAGE:-no}"
readonly SNARKOS_FEATURES="${SNARKOS_FEATURES:-test_network}"
readonly LOG_WAIT_SECONDS="${LOG_WAIT_SECONDS:-5}"
readonly LOG_POLL_INTERVAL="${LOG_POLL_INTERVAL:-3}"
readonly LOG_FORWARDING="${LOG_FORWARDING:-false}"

LEO_PID=""
LOG_WATCHER_PID=""
SHUTDOWN_IN_PROGRESS=""

log() { echo "[entrypoint] $*" >&2; }
log_info() { [[ "${LOG_FORWARDING}" == "true" ]] && echo "[entrypoint] $*" >&2 || true; }

cleanup() {
    # Guard against signal re-entry during cleanup
    [[ -n "${SHUTDOWN_IN_PROGRESS:-}" ]] && return
    SHUTDOWN_IN_PROGRESS=1

    local exit_code="${1:-0}"
    log "Shutting down (exit code: ${exit_code})..."

    if [[ -n "${LOG_WATCHER_PID:-}" ]] && kill -0 "${LOG_WATCHER_PID}" 2>/dev/null; then
        kill "${LOG_WATCHER_PID}" 2>/dev/null || true
        wait "${LOG_WATCHER_PID}" 2>/dev/null || true
    fi

    if [[ -n "${LEO_PID:-}" ]] && kill -0 "${LEO_PID}" 2>/dev/null; then
        log "Sending SIGTERM to leo devnet (PID: ${LEO_PID})..."
        kill -TERM "${LEO_PID}" 2>/dev/null || true

        local wait_count=0
        while kill -0 "${LEO_PID}" 2>/dev/null && [[ ${wait_count} -lt 30 ]]; do
            sleep 1
            # Avoid ((wait_count++)) - returns exit code 1 when value is 0, triggering errexit
            wait_count=$((wait_count + 1))
        done

        if kill -0 "${LEO_PID}" 2>/dev/null; then
            log "Force killing leo devnet..."
            kill -KILL "${LEO_PID}" 2>/dev/null || true
            wait "${LEO_PID}" 2>/dev/null || true
            # Escalate: SIGKILL means unclean shutdown even if triggered by a signal
            exit_code=1
        fi
    fi

    log "Shutdown complete."
    exit "${exit_code}"
}

# Start with exit 0 for signal-triggered shutdown (clean stop for Docker/Podman).
# cleanup() escalates to exit 1 if leo has to be force-killed (SIGKILL).
trap 'cleanup 0' INT
trap 'cleanup 0' TERM
trap 'cleanup 0' QUIT

# Use find instead of globs - globs silently fail with errexit in subshells
# and require shopt settings that don't propagate to backgrounded functions
get_log_files() {
    {
        find /tmp -maxdepth 1 -name 'snarkos*.log' -type f 2>/dev/null
        find "${STORAGE}" -name '*.log' -type f 2>/dev/null
    } | sort -u
}

log_watcher() {
    local current_list=""
    local tail_pid=""

    log_info "Log watcher started, polling every ${LOG_POLL_INTERVAL}s..."

    while true; do
        local new_list
        # Fallback to empty string prevents errexit if find returns nothing
        new_list=$(get_log_files) || new_list=""

        if [[ "$new_list" != "$current_list" ]]; then
            if [[ -n "$tail_pid" ]] && kill -0 "$tail_pid" 2>/dev/null; then
                kill "$tail_pid" 2>/dev/null || true
                wait "$tail_pid" 2>/dev/null || true
                tail_pid=""
            fi

            if [[ -n "$new_list" ]]; then
                local -a files=()
                while IFS= read -r file; do
                    [[ -n "$file" ]] && files+=("$file")
                done <<< "$new_list"

                log_info "Tailing ${#files[@]} log file(s)"
                # -F follows through truncation/rename (vs -f which follows the fd)
                tail -F "${files[@]}" 2>/dev/null &
                tail_pid=$!
            fi

            current_list="$new_list"
        fi

        sleep "${LOG_POLL_INTERVAL}"
    done
}

main() {
    # Non-devnet commands: pass through to leo directly.
    # e.g., docker run <image> new my_project → exec leo new my_project
    if [[ $# -gt 0 && "$1" != "devnet" ]]; then
        log "Passing through to leo: $*"
        exec leo "$@"
    fi

    log_info "Starting aleo-devnet..."
    mkdir -p "${STORAGE}"

    local cmd
    if [[ $# -gt 0 ]]; then
        # "devnet" args provided explicitly (from CMD or CLI override).
        # Run through wrapper for log forwarding and graceful shutdown.
        cmd=(leo "$@")
    else
        # No args — build devnet command from environment variables.
        log_info "Config: STORAGE=${STORAGE} VERBOSITY=${VERBOSITY} VALIDATORS=${NUM_VALIDATORS} CLIENTS=${NUM_CLIENTS} CLEAR=${CLEAR_STORAGE}"
        cmd=(
            leo devnet
            --storage "${STORAGE}"
            --verbosity "${VERBOSITY}"
            --snarkos ./snarkos
            --num-validators "${NUM_VALIDATORS}"
            --num-clients "${NUM_CLIENTS}"
            --yes
        )
        [[ "${CLEAR_STORAGE}" == "yes" ]] && cmd+=(--clear-storage)
        [[ -n "${SNARKOS_FEATURES}" ]] && cmd+=(--snarkos-features "${SNARKOS_FEATURES}")
    fi

    log_info "Executing: ${cmd[*]}"

    "${cmd[@]}" &
    LEO_PID=$!
    log_info "Started leo devnet (PID: ${LEO_PID})"

    log_info "Waiting ${LOG_WAIT_SECONDS}s for snarkOS to initialize..."
    sleep "${LOG_WAIT_SECONDS}"

    if [[ "${LOG_FORWARDING}" == "true" ]]; then
        log_watcher &
        LOG_WATCHER_PID=$!
    fi

    local leo_exit_code=0
    wait "${LEO_PID}" || leo_exit_code=$?
    [[ ${leo_exit_code} -ne 0 ]] && log "Leo devnet exited with code: ${leo_exit_code}"

    cleanup "${leo_exit_code}"
}

main "$@"