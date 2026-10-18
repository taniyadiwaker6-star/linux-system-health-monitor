# Linux System Health & Log Monitor

A modular, production-ready Bash monitoring utility and interactive web dashboard that inspects a Linux host's uptime, CPU load, memory utilization, filesystem capacity, top resource-consuming processes, and authentication failure log entries.

[![Bash](https://img.shields.io/badge/Language-Bash%204.0+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%7C%20POSIX-FCC624?logo=linux&logoColor=black)](https://kernel.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub Pages](https://img.shields.io/badge/Demo-GitHub%20Pages-brightgreen)](https://taniyadiwaker6-star.github.io/linux-system-health-monitor/)

---

## 📌 Project Overview

This utility provides system administrators and DevOps engineers with a single-command health report of any Linux host. It operates with **least privilege** (no root required for basic health inspection), validates inputs upfront, protects credentials from log leakage, and gracefully falls back to alternative data sources (`/proc` files, `journalctl`) when traditional commands or log files are missing.

> **Important**: This script generates an on-demand, point-in-time health report when executed. It is **not** a continuous background daemon or polling service. For scheduled recurring runs, configure it via a `cron` job or systemd timer.

---

## ✨ Features

- **Host & Environment Telemetry**: Collects hostname, OS distribution (via `/etc/os-release`), Linux kernel release, machine architecture, execution user, and timestamp.
- **Uptime & Load Monitoring**: Captures system uptime and 1/5/15-minute load averages with automatic fallback to `/proc/uptime` and `/proc/loadavg`.
- **CPU Analysis**: Reports logical core count and automatically flags a warning if the 1-minute load average exceeds the total logical cores.
- **Memory Statistics**: Parses `free -h` with a portable `/proc/meminfo` fallback when `free` is not installed (e.g., minimal Docker containers).
- **Filesystem Capacity & Space Warnings**: Displays storage usage via `df -h` (filtering virtual `tmpfs`/`devtmpfs`) and warns if any volume reaches or exceeds **90%** capacity. Uses POSIX field counting `$(NF-1)` to prevent false alarms on mounts containing spaces.
- **Top Process Profiling**: Lists top CPU-consuming processes using `comm` rather than full argument strings to avoid accidental exposure of passwords, tokens, or sensitive CLI parameters.
- **Authentication Security Scanner**: Scans `/var/log/auth.log`, `/var/log/secure`, or `/var/log/messages` in a **single pass** for `failed password`, `authentication failure`, or `invalid user` patterns. Automatically falls back to `journalctl` on modern systemd distributions and redacts sensitive password strings.
- **Robust Error Handling**:
  - Traps `EXIT`, `INT`, `TERM`, and `HUP` signals to guarantee temporary file cleanup.
  - Validates output file destinations *before* executing checks (checks directory existence and writability).
  - Uses `set -u` and `set -o pipefail` safely without accidental pipeline termination.
- **Interactive Web Dashboard**: Full HTML5/CSS/JavaScript graphical dashboard with simulation toggles (Normal, High CPU Load, Disk Alert $\ge 90\%$, SSH Brute Force Attacks).

---

## 🛠️ Prerequisites

- **Operating System**: Any standard Linux distribution (Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky, Alpine, Arch) or POSIX shell environment.
- **Shell**: GNU Bash $\ge 4.0$.
- **Standard Utilities**:
  - Core: `awk`, `date`, `df`, `grep`, `head`, `hostname`, `id`, `mktemp`, `ps`, `sed`, `tail`, `wc`.
  - Optional (with built-in fallbacks): `free`, `nproc`, `uptime`, `journalctl`.

---

## 🚀 Execution & Usage

### 1. Terminal / Command-Line Interface

Make the script executable:
```bash
chmod +x system_health.sh
```

#### Run and Display in Terminal (stdout):
```bash
./system_health.sh
```

#### Save Report to a File:
```bash
./system_health.sh reports/health-report.txt
```
*Note: The script automatically creates the destination directory if it does not already exist.*

#### Command Options:
```bash
./system_health.sh --help       # Display usage guide and exit
./system_health.sh --version    # Display version information
```

### 2. Interactive Web Dashboard

Open [`index.html`](index.html) in any browser or launch with VS Code Live Server:
- **Live Demo**: [https://taniyadiwaker6-star.github.io/linux-system-health-monitor/](https://taniyadiwaker6-star.github.io/linux-system-health-monitor/)
- Test different operational scenarios with one click:
  - **Normal**: All health checks pass (CPU < 50%, Disk < 90%, 0 auth failures).
  - **High CPU / Load**: Simulates 1-min load exceeding CPU cores.
  - **Disk $\ge 90\%$ Warning**: Simulates a nearly full root volume.
  - **Failed SSH Logins**: Simulates brute force attacks recorded in auth logs.
- Export raw text reports directly from the web interface.

---

## 📋 Sample Report Output

```text
================================================================================
                         LINUX SYSTEM HEALTH REPORT                             
================================================================================
Host:       prod-srv-01
OS:         Ubuntu 24.04 LTS (x86_64)
Kernel:     6.8.0-45-generic
User:       ubuntu
Generated:  2026-10-18 14:35:00 UTC

=== UPTIME AND LOAD ===
 14:35:00 up 14 days, 6 hours, 32 mins, 2 users,  load average: 0.45, 0.62, 0.58

=== CPU ===
Logical CPUs: 8
Load averages (1/5/15 min): 0.45 0.62 0.58

=== MEMORY ===
               total        used        free      shared  buff/cache   available
Mem:           15.9G        6.7G        6.1G        124M        3.1G        9.2G

=== FILESYSTEM USAGE ===
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p2  240G  139G   89G  58% /
/dev/nvme0n1p1  512M   32M  480M   7% /boot/efi
/dev/sda1       1.8T  720G  1.0T  41% /mnt/storage

=== TOP PROCESSES BY CPU ===
    PID COMMAND         %CPU  %MEM
   1420 dockerd          7.8   4.2
   2184 postgres         5.4   6.8
   3012 node             4.1   3.5
    982 nginx            2.3   1.1

=== FAILED AUTHENTICATION EVENTS ===
Source: /var/log/auth.log (traditional log file)
No matching authentication failures found in this log.

=== STATUS SUMMARY ===
Overall Health Status: [HEALTHY]
--------------------------------------------------------------------------------
  [*] No critical resource thresholds or security alerts triggered.
--------------------------------------------------------------------------------
Report completed.
```

---

## 🔒 Security & Permissions

1. **Least Privilege by Design**: The script runs entirely unprivileged. Root (`sudo`) is **not** required for collecting host uptime, CPU load, memory, disk, or process listings.
2. **Log File Permissions**: On some Linux distributions (e.g., Debian/Ubuntu), `/var/log/auth.log` is readable only by `root` or users in the `adm` group. If the current user cannot read it, the script informs the user gracefully without crashing, and attempts a fallback via `journalctl`.
3. **Data Protection / Redaction**:
   - The process table displays binary command names (`comm`) instead of full command strings (`args`), preventing database passwords, secret tokens, or API keys passed via CLI flags from being logged in the report.
   - Any password strings captured from log error lines are automatically replaced with `[REDACTED]`.

---

## 🧪 Testing and Validation

An automated test suite is included in [`tests/test_monitor.sh`](tests/test_monitor.sh).

### Running the Test Suite:
```bash
chmod +x tests/test_monitor.sh
./tests/test_monitor.sh
```

### Verified Test Cases:
| Test Case | Description | Result |
|:---|:---|:---:|
| **Syntax Check** | Validates shell script syntax via `bash -n` | `PASS` |
| **Help Flag** | Confirms `--help` displays usage manual | `PASS` |
| **Version Flag** | Confirms `--version` outputs semantic version | `PASS` |
| **Option Rejection** | Rejects invalid flags (`--invalid-option`) with exit code 1 | `PASS` |
| **Argument Validation** | Rejects multiple output destinations | `PASS` |
| **Directory Target** | Prevents overwriting directories specified as files | `PASS` |
| **File Creation** | Generates reports and auto-creates non-existent parent directories | `PASS` |
| **Disk Warning** | Triggers warning on simulated $\ge 90\%$ capacity without false positives on spaces | `PASS` |
| **Log Scanner** | Verifies regex matching for failed logins and redacts passwords | `PASS` |

### Running ShellCheck (Static Analysis):
If ShellCheck is installed in your environment:
```bash
shellcheck system_health.sh
```

---

## ⚙️ Troubleshooting

| Issue | Cause | Solution |
|:---|:---|:---|
| `Auth log not readable` | User lacks read access to `/var/log/auth.log` | Add user to the `adm` group (`usermod -aG adm $USER`), or run with `sudo` if permitted. |
| `'free' command unavailable` | Minimal container image without `procps` | The script automatically falls back to `/proc/meminfo`. Optionally install `procps` (`apt install procps`). |
| `Cannot create output directory` | Insufficient permissions on target path | Ensure the destination directory path is writable by the running user. |

---

## ⚠️ Known Limitations

- **Point-in-Time Scope**: Generates an instantaneous snapshot. It does not monitor historical time-series trends over days or weeks (use Prometheus or Grafana for long-term telemetry).
- **Log Rotation**: Only inspects currently active log files or recent journal entries; archived logs (`.gz`, `.1`) are excluded to preserve execution speed.
- **Virtual Containers**: In lightweight Docker containers or LXC guests, `/proc/meminfo` reflects host memory rather than container cgroup limits unless `cgroupfs` is configured.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
