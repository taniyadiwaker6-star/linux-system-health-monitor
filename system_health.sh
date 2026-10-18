#!/usr/bin/env bash
# ==============================================================================
# Linux System Health & Log Monitor
# ------------------------------------------------------------------------------
# Collects and reports host load, CPU, memory, filesystem utilization, top
# CPU-consuming processes, and authentication failure log entries.
#
# Usage:
#   ./system_health.sh [options] [output-file]
#
# Options:
#   -h, --help       Display this help message and exit
#   -v, --version    Show script version
#
# Exit Codes:
#   0 - Success (report generated successfully)
#   1 - Critical script error (invalid arguments, unwritable output path)
#   2 - Health warning detected (disk >= 90%, high load, or auth failures)
# ==============================================================================

set -u
set -o pipefail

VERSION="2.1.0"
OUTPUT_FILE=""
TMP_REPORT=""
TMP_LOG_MATCHES=""

# Tracking arrays for health evaluation and limitations
declare -a HEALTH_WARNINGS=()
declare -a MONITORING_NOTICES=()

# ------------------------------------------------------------------------------
# Cleanup and Signal Handling
# ------------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  if [[ -n "${TMP_REPORT:-}" && -f "${TMP_REPORT}" ]]; then
    rm -f "${TMP_REPORT}" 2>/dev/null || true
  fi
  if [[ -n "${TMP_LOG_MATCHES:-}" && -f "${TMP_LOG_MATCHES}" ]]; then
    rm -f "${TMP_LOG_MATCHES}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}

trap cleanup EXIT
trap 'echo "Script interrupted by user." >&2; exit 130' INT TERM HUP

# ------------------------------------------------------------------------------
# CLI Argument Parsing & Validation
# ------------------------------------------------------------------------------
show_help() {
  cat <<'EOF'
Linux System Health & Log Monitor

Usage:
  ./system_health.sh [options] [output-file]

Arguments:
  output-file       Optional path where the generated report will be saved.
                    If omitted, the report is printed to standard output.

Options:
  -h, --help        Display this help message and exit
  -v, --version     Display version information and exit

Examples:
  ./system_health.sh
  ./system_health.sh reports/health-report.txt
  ./system_health.sh /var/log/system-health.log

EOF
}

show_version() {
  echo "Linux System Health & Log Monitor version ${VERSION}"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_help
        exit 0
        ;;
      -v|--version)
        show_version
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Error: Unknown option '$1'. Use --help for usage information." >&2
        exit 1
        ;;
      *)
        if [[ -z "${OUTPUT_FILE}" ]]; then
          OUTPUT_FILE="$1"
        else
          echo "Error: Multiple output files specified ('${OUTPUT_FILE}' and '$1')." >&2
          exit 1
        fi
        ;;
    esac
    shift
  done

  # Validate output path upfront before starting inspection
  if [[ -n "${OUTPUT_FILE}" ]]; then
    if [[ -d "${OUTPUT_FILE}" ]]; then
      echo "Error: Specified output path '${OUTPUT_FILE}' is an existing directory, not a file." >&2
      exit 1
    fi

    local target_dir
    target_dir="$(dirname "${OUTPUT_FILE}")"
    if [[ ! -d "${target_dir}" ]]; then
      if ! mkdir -p "${target_dir}" 2>/dev/null; then
        echo "Error: Cannot create output directory '${target_dir}'. Permission denied or invalid path." >&2
        exit 1
      fi
    fi

    if [[ -e "${OUTPUT_FILE}" && ! -w "${OUTPUT_FILE}" ]]; then
      echo "Error: Target output file '${OUTPUT_FILE}' exists but is not writable." >&2
      exit 1
    elif [[ ! -e "${OUTPUT_FILE}" && ! -w "${target_dir}" ]]; then
      echo "Error: Output directory '${target_dir}' is not writable." >&2
      exit 1
    fi
  fi
}

# ------------------------------------------------------------------------------
# Formatting Helpers
# ------------------------------------------------------------------------------
section() {
  printf '\n=== %s ===\n' "$1"
}

# ------------------------------------------------------------------------------
# System Metrics Collectors
# ------------------------------------------------------------------------------

# 1. Header and OS Information
collect_header_and_os() {
  local host_name stamp current_user os_name kernel_ver arch
  host_name="$(hostname 2>/dev/null || printf 'unknown')"
  stamp="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
  current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || printf 'unknown')"

  # Extract OS name from /etc/os-release or uname
  if [[ -r /etc/os-release ]]; then
    os_name="$(awk -F= '$1=="PRETTY_NAME" {gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null)"
  fi
  if [[ -z "${os_name:-}" ]]; then
    os_name="$(uname -s 2>/dev/null || printf 'Linux')"
  fi

  kernel_ver="$(uname -r 2>/dev/null || printf 'unknown')"
  arch="$(uname -m 2>/dev/null || printf 'unknown')"

  echo "================================================================================"
  echo "                         LINUX SYSTEM HEALTH REPORT                             "
  echo "================================================================================"
  printf 'Host:       %s\n' "${host_name}"
  printf 'OS:         %s (%s)\n' "${os_name}" "${arch}"
  printf 'Kernel:     %s\n' "${kernel_ver}"
  printf 'User:       %s\n' "${current_user}"
  printf 'Generated:  %s\n' "${stamp}"
}

# 2. Uptime and Load Average
collect_uptime_and_load() {
  section "UPTIME AND LOAD"
  if command -v uptime >/dev/null 2>&1; then
    uptime 2>&1 || true
  elif [[ -r /proc/uptime && -r /proc/loadavg ]]; then
    local up_seconds up_days up_hours up_mins load_info
    up_seconds="$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)"
    up_days=$((up_seconds / 86400))
    up_hours=$(( (up_seconds % 86400) / 3600 ))
    up_mins=$(( (up_seconds % 3600) / 60 ))
    load_info="$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || echo 'unavailable')"
    printf 'Uptime (proc): %d days, %d hours, %d minutes\n' "${up_days}" "${up_hours}" "${up_mins}"
    printf 'Load average:  %s\n' "${load_info}"
  else
    echo "Notice: Neither 'uptime' command nor /proc/uptime is accessible."
    MONITORING_NOTICES+=("Uptime information unavailable")
  fi
}

# 3. CPU Statistics
collect_cpu_info() {
  section "CPU"
  local logical_cpus="unavailable"
  if command -v nproc >/dev/null 2>&1; then
    logical_cpus="$(nproc 2>/dev/null || echo 'unavailable')"
  elif [[ -r /proc/cpuinfo ]]; then
    logical_cpus="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 'unavailable')"
  fi
  printf 'Logical CPUs: %s\n' "${logical_cpus}"

  local l1="" l5="" l15=""
  if [[ -r /proc/loadavg ]]; then
    read -r l1 l5 l15 _ < /proc/loadavg 2>/dev/null || true
    printf 'Load averages (1/5/15 min): %s %s %s\n' "${l1}" "${l5}" "${l15}"

    # Evaluate if 1-minute load exceeds logical CPU count
    if [[ "${logical_cpus}" =~ ^[0-9]+$ && -n "${l1}" ]]; then
      local high_load
      high_load=$(awk -v l="${l1}" -v c="${logical_cpus}" 'BEGIN {if ((l+0) > (c+0)) print 1; else print 0}')
      if [[ "${high_load}" -eq 1 ]]; then
        HEALTH_WARNINGS+=("High CPU load: 1-min load average (${l1}) exceeds CPU core count (${logical_cpus})")
      fi
    fi
  else
    echo "Load averages: /proc/loadavg unavailable"
    MONITORING_NOTICES+=("Load average cannot be read from /proc/loadavg")
  fi
}

# 4. Memory Statistics
collect_memory_info() {
  section "MEMORY"
  if command -v free >/dev/null 2>&1; then
    free -h 2>&1 || true
  elif [[ -r /proc/meminfo ]]; then
    # Portable fallback parsing /proc/meminfo when 'free' is not installed
    echo "Notice: 'free' command unavailable; reading from /proc/meminfo:"
    awk '
      /^MemTotal:/      {total=$2/1024/1024}
      /^MemFree:/       {free=$2/1024/1024}
      /^MemAvailable:/  {avail=$2/1024/1024}
      /^Buffers:/       {buffers=$2/1024/1024}
      /^Cached:/        {cached=$2/1024/1024}
      END {
        used = total - free - buffers - cached;
        printf "Total: %.2f GB | Used: %.2f GB | Free: %.2f GB | Avail: %.2f GB\n", total, used, free, avail;
      }
    ' /proc/meminfo 2>/dev/null || echo "Unable to parse /proc/meminfo"
  else
    echo "Notice: Memory statistics unavailable ('free' and /proc/meminfo not accessible)."
    MONITORING_NOTICES+=("Memory statistics unavailable")
  fi
}

# 5. Filesystem Usage and 90% Threshold Warning
collect_filesystem_usage() {
  section "FILESYSTEM USAGE"
  if ! command -v df >/dev/null 2>&1; then
    echo "Notice: 'df' command is not available."
    MONITORING_NOTICES+=("Filesystem usage cannot be inspected ('df' not installed)")
    return
  fi

  # Attempt display without tmpfs / devtmpfs; fallback gracefully
  if ! df -h -x tmpfs -x devtmpfs 2>/dev/null; then
    df -h 2>/dev/null || df 2>&1 || true
  fi

  # Robust threshold parsing using POSIX standard df -P
  # We parse $(NF-1) for capacity percentage to reliably handle filesystem names containing spaces
  local disk_warnings
  disk_warnings="$(
    df -P 2>/dev/null | awk '
      NR > 1 {
        # Exclude virtual / temporary filesystems
        if ($1 ~ /^(tmpfs|devtmpfs|udev|overlay|none)$/) next;

        # Capacity percentage is reliably the second to last field $(NF-1)
        use_str = $(NF - 1);
        mount_pt = $NF;
        fs_name = $1;

        # Remove trailing % sign
        gsub(/%/, "", use_str);
        use_val = use_str + 0;

        if (use_val >= 90) {
          printf "%s on %s (%d%%)\n", fs_name, mount_pt, use_val;
        }
      }
    '
  )"

  if [[ -n "${disk_warnings}" ]]; then
    while IFS= read -r warn_line; do
      [[ -n "${warn_line}" ]] && HEALTH_WARNINGS+=("Disk space critical: ${warn_line}")
    done <<< "${disk_warnings}"
  fi
}

# 6. Top Processes by CPU
collect_top_processes() {
  section "TOP PROCESSES BY CPU"
  if ! command -v ps >/dev/null 2>&1; then
    echo "Notice: 'ps' command is not available."
    MONITORING_NOTICES+=("Process listing unavailable ('ps' not installed)")
    return
  fi

  # 1st preference: GNU ps with custom format and sort
  # Using 'comm' instead of 'args' protects sensitive CLI parameters (passwords, tokens)
  if ps -eo pid,comm,%cpu,%mem --sort=-%cpu >/dev/null 2>&1; then
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 11 || true
  # 2nd preference: BSD / standard ps piped to sort
  elif ps aux >/dev/null 2>&1 && command -v sort >/dev/null 2>&1; then
    printf "%-8s %-20s %-8s %-8s\n" "PID" "COMMAND" "%CPU" "%MEM"
    ps aux 2>/dev/null | awk 'NR>1 {printf "%-8s %-20s %-8s %-8s\n", $2, $11, $3, $4}' | sort -nrk 3 | head -n 10 || true
  else
    # Minimal fallback
    ps 2>&1 | head -n 11 || true
  fi
}

# 7. Authentication Events and Security Log Scanning
collect_auth_events() {
  section "FAILED AUTHENTICATION EVENTS"

  local log_file=""
  local auth_candidates=("/var/log/auth.log" "/var/log/secure" "/var/log/messages")

  # Detect first readable traditional auth log
  for candidate in "${auth_candidates[@]}"; do
    if [[ -r "${candidate}" ]]; then
      log_file="${candidate}"
      break
    fi
  done

  local total_matches=0

  if [[ -n "${log_file}" ]]; then
    printf 'Source: %s (traditional log file)\n' "${log_file}"

    # Single-pass scan: extracts matches to temporary buffer and counts lines
    TMP_LOG_MATCHES="$(mktemp 2>/dev/null || echo "")"
    if [[ -n "${TMP_LOG_MATCHES}" && -w "${TMP_LOG_MATCHES}" ]]; then
      grep -Ei 'failed password|authentication failure|invalid user' "${log_file}" > "${TMP_LOG_MATCHES}" 2>/dev/null || true
      total_matches="$(wc -l < "${TMP_LOG_MATCHES}" 2>/dev/null || echo 0)"
      total_matches="${total_matches// /}"

      if [[ "${total_matches}" -gt 0 ]]; then
        echo "Recent authentication failure events (last 10):"
        # Sanitize sensitive patterns if any
        tail -n 10 "${TMP_LOG_MATCHES}" | sed 's/password [^ ]*/password [REDACTED]/g'
        printf 'Total matching failure events: %s\n' "${total_matches}"
        HEALTH_WARNINGS+=("Security alert: ${total_matches} failed authentication event(s) detected in ${log_file}")
      else
        echo "No matching authentication failures found in this log."
      fi
      rm -f "${TMP_LOG_MATCHES}" 2>/dev/null || true
      TMP_LOG_MATCHES=""
    else
      # Direct pipe fallback if mktemp fails
      local matches
      matches="$(grep -Ei 'failed password|authentication failure|invalid user' "${log_file}" 2>/dev/null || true)"
      if [[ -n "${matches}" ]]; then
        echo "Recent authentication failure events (last 10):"
        echo "${matches}" | tail -n 10 | sed 's/password [^ ]*/password [REDACTED]/g'
        total_matches="$(echo "${matches}" | wc -l)"
        printf 'Total matching failure events: %s\n' "${total_matches}"
        HEALTH_WARNINGS+=("Security alert: ${total_matches} failed authentication event(s) detected in ${log_file}")
      else
        echo "No matching authentication failures found in this log."
      fi
    fi

  # Fallback to journalctl if system log files are unavailable
  elif command -v journalctl >/dev/null 2>&1; then
    printf 'Source: systemd journal (journalctl fallback)\n'
    local journal_matches
    # Query ssh/auth related journal messages with non-blocking limits
    journal_matches="$(journalctl -u ssh -u sshd -n 250 --no-pager 2>/dev/null | grep -Ei 'failed password|authentication failure|invalid user' 2>/dev/null || true)"

    if [[ -n "${journal_matches}" ]]; then
      echo "Recent authentication failure events from journal (last 10):"
      echo "${journal_matches}" | tail -n 10 | sed 's/password [^ ]*/password [REDACTED]/g'
      total_matches="$(echo "${journal_matches}" | wc -l)"
      printf 'Matching lines in journal sample: %s\n' "${total_matches}"
      HEALTH_WARNINGS+=("Security alert: ${total_matches} failed authentication event(s) detected via journalctl")
    else
      echo "No matching authentication failures found in recent systemd journal logs."
    fi

  else
    echo "Notice: Auth logs (/var/log/auth.log, /var/log/secure) are not readable and journalctl is unavailable."
    echo "Tip: Run with elevated permissions or install a system logger if log inspection is required."
    MONITORING_NOTICES+=("Authentication logs unreadable or unavailable")
  fi
}

# 8. Overall Status and Health Summary
collect_status_summary() {
  section "STATUS SUMMARY"

  local status_code="HEALTHY"
  if [[ "${#HEALTH_WARNINGS[@]}" -gt 0 ]]; then
    status_code="WARNING"
  fi

  printf 'Overall Health Status: [%s]\n' "${status_code}"
  echo "--------------------------------------------------------------------------------"

  if [[ "${#HEALTH_WARNINGS[@]}" -gt 0 ]]; then
    echo "Active Warnings / Critical Issues:"
    for warn in "${HEALTH_WARNINGS[@]}"; do
      printf '  [!] %s\n' "${warn}"
    done
  else
    echo "  [*] No critical resource thresholds or security alerts triggered."
  fi

  if [[ "${#MONITORING_NOTICES[@]}" -gt 0 ]]; then
    echo ""
    echo "Monitoring Limitations / Notices:"
    for note in "${MONITORING_NOTICES[@]}"; do
      printf '  [-] %s\n' "${note}"
    done
  fi

  echo "--------------------------------------------------------------------------------"
  echo "Report completed."
}

# ------------------------------------------------------------------------------
# Main Execution Flow
# ------------------------------------------------------------------------------
main() {
  parse_arguments "$@"

  # Safely create temporary report file
  TMP_REPORT="$(mktemp 2>/dev/null || echo "")"
  if [[ -z "${TMP_REPORT}" || ! -w "${TMP_REPORT}" ]]; then
    # Fallback to current directory or TMPDIR
    TMP_REPORT="${TMPDIR:-/tmp}/health_report_$$.tmp"
    if ! touch "${TMP_REPORT}" 2>/dev/null; then
      # If temp file cannot be created at all, stream directly to stdout/target
      echo "Warning: Unable to create temporary file; streaming report directly." >&2
      TMP_REPORT=""
    fi
  fi

  # Generate the report into function or buffer
  generate_all() {
    collect_header_and_os
    collect_uptime_and_load
    collect_cpu_info
    collect_memory_info
    collect_filesystem_usage
    collect_top_processes
    collect_auth_events
    collect_status_summary
  }

  if [[ -n "${TMP_REPORT}" ]]; then
    # Write report through temporary file
    generate_all > "${TMP_REPORT}"

    # If no output file was specified, print to stdout
    if [[ -z "${OUTPUT_FILE}" ]]; then
      cat "${TMP_REPORT}"
    else
      # Save to requested destination
      if cp "${TMP_REPORT}" "${OUTPUT_FILE}" 2>/dev/null; then
        cat "${TMP_REPORT}"
        printf '\n==> Report successfully saved to: %s\n' "${OUTPUT_FILE}"
      else
        echo "Error: Failed to copy generated report to '${OUTPUT_FILE}'." >&2
        cat "${TMP_REPORT}"
        exit 1
      fi
    fi
  else
    # Direct streaming fallback
    if [[ -z "${OUTPUT_FILE}" ]]; then
      generate_all
    else
      generate_all | tee "${OUTPUT_FILE}"
      printf '\n==> Report successfully saved to: %s\n' "${OUTPUT_FILE}"
    fi
  fi

  # Return appropriate exit code based on health warnings
  if [[ "${#HEALTH_WARNINGS[@]}" -gt 0 ]]; then
    exit 2
  else
    exit 0
  fi
}

main "$@"
