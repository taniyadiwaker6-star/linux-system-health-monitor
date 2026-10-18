#!/usr/bin/env bash
# Linux System Health & Log Monitor
# Usage: ./system_health.sh [output-file]
set -u
set -o pipefail

OUTPUT="${1:-}"
HOST="$(hostname 2>/dev/null || printf 'unknown')"
STAMP="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

section() { printf '\n=== %s ===\n' "$1"; }

{
  echo "LINUX SYSTEM HEALTH REPORT"
  echo "Host: $HOST"
  echo "Generated: $STAMP"

  section "UPTIME AND LOAD"
  uptime 2>&1 || true

  section "CPU"
  if command -v nproc >/dev/null 2>&1; then
    printf 'Logical CPUs: '; nproc
  else
    printf 'Logical CPUs: unavailable\n'
  fi
  if [[ -r /proc/loadavg ]]; then
    printf 'Load averages (1/5/15 min): '
    awk '{print $1, $2, $3}' /proc/loadavg
  else
    echo "Load averages: /proc/loadavg unavailable"
  fi

  section "MEMORY"
  if command -v free >/dev/null 2>&1; then
    free -h
  else
    echo "free command unavailable"
  fi

  section "FILESYSTEM USAGE"
  df -h -x tmpfs -x devtmpfs 2>&1 || df -h 2>&1 || true

  section "TOP PROCESSES BY CPU"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 11 || true

  section "FAILED AUTHENTICATION EVENTS"
  LOG_FILE=""
  for candidate in /var/log/auth.log /var/log/secure; do
    if [[ -r "$candidate" ]]; then LOG_FILE="$candidate"; break; fi
  done
  if [[ -n "$LOG_FILE" ]]; then
    printf 'Source: %s\n' "$LOG_FILE"
    if grep -Eic 'failed password|authentication failure|invalid user' "$LOG_FILE" >/dev/null 2>&1; then
      grep -Ei 'failed password|authentication failure|invalid user' "$LOG_FILE" | tail -n 10
      printf 'Matching lines in available log: '
      grep -Eic 'failed password|authentication failure|invalid user' "$LOG_FILE" || true
    else
      echo "No matching authentication failures found in this log."
    fi
  else
    echo "Auth log not readable or not present; skipping log scan."
    echo "On some systems, elevated permissions or journalctl may be required."
  fi

  section "STATUS SUMMARY"
  # A simple threshold check; this is an informational report, not an alerting daemon.
  if command -v df >/dev/null 2>&1; then
    if df -P -x tmpfs -x devtmpfs 2>/dev/null |
      awk 'NR>1 {gsub(/%/,"",$5); if (($5+0) >= 90) found=1} END {exit !found}'; then
      echo "WARNING: at least one filesystem is at or above 90% usage."
    else
      echo "No filesystem at or above 90% usage was detected."
    fi
  fi
  echo "Report completed."
} | tee "$TMP"

if [[ -n "$OUTPUT" ]]; then
  if cp "$TMP" "$OUTPUT"; then
    printf '\nReport saved to: %s\n' "$OUTPUT"
  else
    printf '\nError: could not save report to %s\n' "$OUTPUT" >&2
    exit 1
  fi
fi
