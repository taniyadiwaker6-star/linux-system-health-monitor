# Linux System Health & Log Monitor

A Bash utility that produces a text report about a Linux host's load, CPU
count, memory, filesystem usage, top CPU-consuming processes, and available
authentication-failure log entries.

## Features
- Captures hostname, timestamp, uptime, and load averages
- Reports logical CPU count and memory usage
- Lists filesystem usage and top processes
- Scans readable `/var/log/auth.log` or `/var/log/secure` for common
  failed-authentication patterns
- Warns if a filesystem is at least 90% full
- Optionally saves a report to a file
- Handles missing commands/log files without treating them as fatal

## Requirements
- Linux
- Bash
- Standard utilities such as `awk`, `date`, `df`, `free`, `grep`, `head`,
  `hostname`, `mktemp`, `ps`, and `tee`

## Run

### 1. Interactive Web Dashboard (HTML / CSS / JavaScript)
Open `index.html` in any modern web browser:
- **Real-Time KPIs**: Live CPU load, memory utilization, filesystem status, and auth failure logs.
- **Interactive Scenarios**: Test normal operation, high CPU load, disk usage alert (&ge;90%), and failed SSH attempts.
- **Live Report Generator**: Generates and exports `health-report.txt` matching the Bash script output.
- **Process Filter & Log Viewer**: Live filtering of top processes and inspection of `/var/log/auth.log`.

### 2. Bash Command-Line Script
```bash
chmod +x system_health.sh
./system_health.sh
./system_health.sh reports/health-report.txt
```

Create the output directory first if needed:
```bash
mkdir -p reports
./system_health.sh reports/health-report.txt
```

Some authentication logs may require elevated permissions. Run with least
privilege; do not use `sudo` unless needed and permitted by your environment.
The script does not change system settings or delete logs.

## Test ideas
- Run without an output filename.
- Save a report to a writable directory.
- Run as a normal user and confirm missing/unreadable auth logs are handled.
- Compare the reported filesystem usage with `df -h`.
- Review the top-process output against `ps`.

## Limitations
- Log paths and available utilities vary by distribution.
- The script only scans readable traditional auth log files; it does not
  query the systemd journal.
- The disk threshold is a simple 90% usage warning, not a production alerting
  or monitoring service.

## Resume bullet (use after you run it on Linux)
**Linux System Health & Log Monitor | Bash, Linux, awk, grep, df, ps**
- Developed a Bash script to report system load, memory, disk usage, and
  top CPU-consuming processes using standard Linux utilities.
- Added authentication-log pattern scanning, a configurable report output,
  and a filesystem usage warning with graceful handling of unavailable logs.

Only claim Linux experience after running and understanding the script.
