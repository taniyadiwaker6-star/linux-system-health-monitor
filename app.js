/**
 * Linux System Health & Log Monitor - Web Engine
 * Replicates the exact behavior and report generation of system_health.sh:
 * - Uptime & Load Averages (1/5/15 min)
 * - Logical CPU count & Memory usage (free -h)
 * - Filesystem usage (df -h) with 90% threshold check
 * - Top processes by CPU (ps -eo pid,comm,%cpu,%mem --sort=-%cpu)
 * - Authentication log scan (/var/log/auth.log or /var/log/secure)
 * - Status summary and report exporter (.txt)
 */

// State configurations for different test scenarios
const SCENARIOS = {
  normal: {
    hostname: 'prod-srv-01',
    uptime: '14 days, 6 hours, 32 mins, 2 users',
    cores: 8,
    loadAvg: [0.45, 0.62, 0.58],
    cpuPct: 24,
    mem: { total: '15.9G', used: '6.7G', free: '6.1G', shared: '124M', cache: '3.1G', avail: '9.2G', pct: 42 },
    filesystems: [
      { fs: '/dev/nvme0n1p2', size: '240G', used: '139G', avail: '89G', pct: 58, mount: '/' },
      { fs: '/dev/nvme0n1p1', size: '512M', used: '32M', avail: '480M', pct: 7, mount: '/boot/efi' },
      { fs: '/dev/sda1', size: '1.8T', used: '720G', avail: '1.0T', pct: 41, mount: '/mnt/storage' },
      { fs: '/dev/sdb1', size: '500G', used: '110G', avail: '365G', pct: 23, mount: '/var/log' }
    ],
    processes: [
      { pid: 1420, comm: 'dockerd', cpu: 7.8, mem: 4.2 },
      { pid: 2184, comm: 'postgres', cpu: 5.4, mem: 6.8 },
      { pid: 3012, comm: 'node', cpu: 4.1, mem: 3.5 },
      { pid: 982, comm: 'nginx', cpu: 2.3, mem: 1.1 },
      { pid: 745, comm: 'systemd-journal', cpu: 1.2, mem: 0.9 },
      { pid: 1104, comm: 'redis-server', cpu: 0.9, mem: 1.8 },
      { pid: 489, comm: 'sshd', cpu: 0.4, mem: 0.2 },
      { pid: 512, comm: 'prometheus', cpu: 0.3, mem: 1.4 },
      { pid: 1205, comm: 'rsyslogd', cpu: 0.2, mem: 0.1 },
      { pid: 4501, comm: 'system_health.sh', cpu: 0.1, mem: 0.1 }
    ],
    authLogs: [
      { type: 'ok', text: 'Oct 18 13:22:10 prod-srv-01 sshd[14205]: Accepted publickey for ubuntu from 192.168.1.100 port 52314 ssh2' },
      { type: 'ok', text: 'Oct 18 13:45:02 prod-srv-01 CRON[15102]: (root) CMD (/usr/local/bin/backup.sh >/dev/null 2>&1)' },
      { type: 'ok', text: 'Oct 18 14:01:18 prod-srv-01 sudo:   ubuntu : TTY=pts/0 ; PWD=/home/ubuntu ; USER=root ; COMMAND=/bin/df' }
    ],
    authFailCount: 0
  },
  'high-load': {
    hostname: 'prod-srv-01',
    uptime: '14 days, 7 hours, 14 mins, 4 users',
    cores: 8,
    loadAvg: [9.84, 8.12, 6.45],
    cpuPct: 96,
    mem: { total: '15.9G', used: '14.2G', free: '680M', shared: '512M', cache: '1.0G', avail: '1.2G', pct: 89 },
    filesystems: [
      { fs: '/dev/nvme0n1p2', size: '240G', used: '139G', avail: '89G', pct: 58, mount: '/' },
      { fs: '/dev/nvme0n1p1', size: '512M', used: '32M', avail: '480M', pct: 7, mount: '/boot/efi' },
      { fs: '/dev/sda1', size: '1.8T', used: '720G', avail: '1.0T', pct: 41, mount: '/mnt/storage' }
    ],
    processes: [
      { pid: 8812, comm: 'python3_worker', cpu: 48.2, mem: 28.5 },
      { pid: 8813, comm: 'python3_worker', cpu: 32.6, mem: 24.1 },
      { pid: 2184, comm: 'postgres', cpu: 8.9, mem: 14.2 },
      { pid: 1420, comm: 'dockerd', cpu: 4.1, mem: 4.5 },
      { pid: 3012, comm: 'node', cpu: 2.1, mem: 3.8 }
    ],
    authLogs: [
      { type: 'ok', text: 'Oct 18 14:15:30 prod-srv-01 sshd[18201]: Accepted publickey for deployer from 10.0.4.12 port 48922' }
    ],
    authFailCount: 0
  },
  'disk-alert': {
    hostname: 'prod-srv-01',
    uptime: '14 days, 7 hours, 30 mins, 1 user',
    cores: 8,
    loadAvg: [1.12, 0.95, 0.88],
    cpuPct: 35,
    mem: { total: '15.9G', used: '7.8G', free: '5.2G', shared: '180M', cache: '2.9G', avail: '8.1G', pct: 49 },
    filesystems: [
      { fs: '/dev/nvme0n1p2', size: '240G', used: '228G', avail: '12G', pct: 95, mount: '/' },
      { fs: '/dev/nvme0n1p1', size: '512M', used: '32M', avail: '480M', pct: 7, mount: '/boot/efi' },
      { fs: '/dev/sda1', size: '1.8T', used: '1.71T', avail: '90G', pct: 92, mount: '/mnt/storage' },
      { fs: '/dev/sdb1', size: '500G', used: '110G', avail: '365G', pct: 23, mount: '/var/log' }
    ],
    processes: [
      { pid: 5041, comm: 'tar_archiver', cpu: 14.5, mem: 3.2 },
      { pid: 1420, comm: 'dockerd', cpu: 7.2, mem: 4.2 },
      { pid: 2184, comm: 'postgres', cpu: 4.8, mem: 6.8 }
    ],
    authLogs: [
      { type: 'ok', text: 'Oct 18 14:18:22 prod-srv-01 CRON[19044]: (root) CMD (/usr/bin/logrotate /etc/logrotate.conf)' }
    ],
    authFailCount: 0
  },
  'auth-fail': {
    hostname: 'prod-srv-01',
    uptime: '14 days, 7 hours, 45 mins, 2 users',
    cores: 8,
    loadAvg: [1.85, 1.42, 1.10],
    cpuPct: 42,
    mem: { total: '15.9G', used: '7.1G', free: '5.8G', shared: '140M', cache: '3.0G', avail: '8.8G', pct: 45 },
    filesystems: [
      { fs: '/dev/nvme0n1p2', size: '240G', used: '139G', avail: '89G', pct: 58, mount: '/' },
      { fs: '/dev/sda1', size: '1.8T', used: '720G', avail: '1.0T', pct: 41, mount: '/mnt/storage' }
    ],
    processes: [
      { pid: 489, comm: 'sshd', cpu: 12.4, mem: 1.5 },
      { pid: 1420, comm: 'dockerd', cpu: 6.8, mem: 4.2 },
      { pid: 2184, comm: 'postgres', cpu: 4.1, mem: 6.8 }
    ],
    authLogs: [
      { type: 'fail', text: 'Oct 18 14:19:02 prod-srv-01 sshd[21011]: Failed password for invalid user admin from 198.51.100.42 port 49120 ssh2' },
      { type: 'fail', text: 'Oct 18 14:19:05 prod-srv-01 sshd[21015]: Failed password for root from 198.51.100.42 port 49128 ssh2' },
      { type: 'fail', text: 'Oct 18 14:19:08 prod-srv-01 sshd[21019]: authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=198.51.100.42' },
      { type: 'fail', text: 'Oct 18 14:19:12 prod-srv-01 sshd[21023]: Failed password for invalid user oracle from 198.51.100.42 port 49140 ssh2' },
      { type: 'fail', text: 'Oct 18 14:19:15 prod-srv-01 sshd[21027]: Failed password for invalid user test from 198.51.100.42 port 49146 ssh2' }
    ],
    authFailCount: 5
  }
};

let currentScenario = 'normal';
let currentData = JSON.parse(JSON.stringify(SCENARIOS['normal']));

// Elements
const hostNameEl = document.getElementById('host-name');
const uptimeDisplayEl = document.getElementById('uptime-display');
const serverStatusDot = document.getElementById('server-status-dot');
const lastScanTimeEl = document.getElementById('last-scan-time');

// KPI elements
const valCpuPct = document.getElementById('val-cpu-pct');
const valCpuCores = document.getElementById('val-cpu-cores');
const barCpu = document.getElementById('bar-cpu');
const valLoadAvg = document.getElementById('val-loadavg');
const badgeCpu = document.getElementById('badge-cpu');

const valMemPct = document.getElementById('val-mem-pct');
const valMemUsed = document.getElementById('val-mem-used');
const valMemTotal = document.getElementById('val-mem-total');
const valMemAvail = document.getElementById('val-mem-avail');
const valMemCache = document.getElementById('val-mem-cache');
const barMem = document.getElementById('bar-mem');
const badgeMem = document.getElementById('badge-mem');

const valDiskMax = document.getElementById('val-disk-max');
const barDisk = document.getElementById('bar-disk');
const badgeDisk = document.getElementById('badge-disk');
const diskSummaryText = document.getElementById('disk-summary-text');

const valAuthCount = document.getElementById('val-auth-count');
const barAuth = document.getElementById('bar-auth');
const badgeAuth = document.getElementById('badge-auth');

const tbodyFilesystems = document.getElementById('tbody-filesystems');
const tbodyProcesses = document.getElementById('tbody-processes');
const procFilterInput = document.getElementById('proc-filter');
const authLogContent = document.getElementById('auth-log-content');
const rawReportPre = document.getElementById('raw-report-pre');

const btnRefresh = document.getElementById('btn-refresh');
const btnExportReport = document.getElementById('btn-export-report');
const btnCopyReport = document.getElementById('btn-copy-report');
const simButtons = document.querySelectorAll('.btn-sim');

// Generate exact bash report text (matches system_health.sh character-for-character)
function generateRawBashReport(data) {
  const d = new Date();
  const dateStr = d.toISOString().replace('T', ' ').substring(0, 19) + ' UTC';
  const hasDiskAlert = data.filesystems.some(f => f.pct >= 90);
  const isHighLoad = data.cpuPct >= 80;
  const hasAuthAlert = data.authFailCount > 0;
  const isWarning = hasDiskAlert || isHighLoad || hasAuthAlert;

  let text = '';
  text += '================================================================================\n';
  text += '                         LINUX SYSTEM HEALTH REPORT                             \n';
  text += '================================================================================\n';
  text += `Host:       ${data.hostname}\n`;
  text += 'OS:         Ubuntu 24.04 LTS (x86_64)\n';
  text += 'Kernel:     6.8.0-45-generic\n';
  text += 'User:       ubuntu\n';
  text += `Generated:  ${dateStr}\n\n`;

  text += '=== UPTIME AND LOAD ===\n';
  text += ` ${d.toTimeString().substring(0, 8)} up ${data.uptime},  load average: ${data.loadAvg.map(n => n.toFixed(2)).join(', ')}\n\n`;

  text += '=== CPU ===\n';
  text += `Logical CPUs: ${data.cores}\n`;
  text += `Load averages (1/5/15 min): ${data.loadAvg.map(n => n.toFixed(2)).join(' ')}\n\n`;

  text += '=== MEMORY ===\n';
  text += '               total        used        free      shared  buff/cache   available\n';
  text += `Mem:           ${data.mem.total.padStart(5)}       ${data.mem.used.padStart(5)}       ${data.mem.free.padStart(5)}        ${data.mem.shared.padStart(4)}       ${data.mem.cache.padStart(5)}       ${data.mem.avail.padStart(5)}\n\n`;

  text += '=== FILESYSTEM USAGE ===\n';
  text += 'Filesystem      Size  Used Avail Use% Mounted on\n';
  data.filesystems.forEach(fs => {
    const fsName = fs.fs.padEnd(15, ' ');
    const s = fs.size.padStart(5, ' ');
    const u = fs.used.padStart(5, ' ');
    const a = fs.avail.padStart(5, ' ');
    const p = `${fs.pct}%`.padStart(4, ' ');
    text += `${fsName} ${s} ${u} ${a} ${p} ${fs.mount}\n`;
  });
  text += '\n';

  text += '=== TOP PROCESSES BY CPU ===\n';
  text += '    PID COMMAND         %CPU  %MEM\n';
  data.processes.slice(0, 10).forEach(p => {
    const pidStr = String(p.pid).padStart(7, ' ');
    const commStr = p.comm.padEnd(15, ' ');
    const cpuStr = p.cpu.toFixed(1).padStart(5, ' ');
    const memStr = p.mem.toFixed(1).padStart(5, ' ');
    text += `${pidStr} ${commStr} ${cpuStr} ${memStr}\n`;
  });
  text += '\n';

  text += '=== FAILED AUTHENTICATION EVENTS ===\n';
  text += 'Source: /var/log/auth.log (traditional log file)\n';
  if (data.authFailCount > 0) {
    text += 'Recent authentication failure events (last 10):\n';
    const fails = data.authLogs.filter(l => l.type === 'fail');
    fails.forEach(f => {
      text += `${f.text}\n`;
    });
    text += `Total matching failure events: ${data.authFailCount}\n\n`;
  } else {
    text += 'No matching authentication failures found in this log.\n\n';
  }

  text += '=== STATUS SUMMARY ===\n';
  text += `Overall Health Status: [${isWarning ? 'WARNING' : 'HEALTHY'}]\n`;
  text += '--------------------------------------------------------------------------------\n';
  if (isWarning) {
    text += 'Active Warnings / Critical Issues:\n';
    if (hasDiskAlert) {
      data.filesystems.filter(f => f.pct >= 90).forEach(f => {
        text += `  [!] Disk space critical: ${f.fs} on ${f.mount} (${f.pct}%)\n`;
      });
    }
    if (isHighLoad) {
      text += `  [!] High CPU load: 1-min load average (${data.loadAvg[0]}) exceeds CPU core count (${data.cores})\n`;
    }
    if (hasAuthAlert) {
      text += `  [!] Security alert: ${data.authFailCount} failed authentication event(s) detected in /var/log/auth.log\n`;
    }
  } else {
    text += '  [*] No critical resource thresholds or security alerts triggered.\n';
  }
  text += '--------------------------------------------------------------------------------\n';
  text += 'Report completed.\n';

  return text;
}

// Render Dashboard View
function renderDashboard() {
  const d = currentData;
  hostNameEl.textContent = d.hostname;
  uptimeDisplayEl.textContent = d.uptime;
  lastScanTimeEl.textContent = new Date().toLocaleTimeString();

  // Determine overall status
  const hasDiskAlert = d.filesystems.some(f => f.pct >= 90);
  const isHighLoad = d.cpuPct >= 80;
  const hasAuthFails = d.authFailCount > 0;

  if (hasDiskAlert || isHighLoad) {
    serverStatusDot.className = 'server-status-dot pulse-red';
  } else if (hasAuthFails) {
    serverStatusDot.className = 'server-status-dot pulse-yellow';
  } else {
    serverStatusDot.className = 'server-status-dot pulse-green';
  }

  // CPU KPI
  valCpuPct.textContent = `${d.cpuPct}%`;
  valCpuCores.textContent = `${d.cores} Logical Cores`;
  barCpu.style.width = `${Math.min(d.cpuPct, 100)}%`;
  barCpu.className = `progress-bar-fill ${d.cpuPct > 80 ? 'fill-red' : d.cpuPct > 50 ? 'fill-yellow' : 'fill-green'}`;
  valLoadAvg.textContent = d.loadAvg.map(n => n.toFixed(2)).join(' ');
  badgeCpu.textContent = d.cpuPct > 80 ? 'Heavy Load' : 'Normal';
  badgeCpu.className = `kpi-badge ${d.cpuPct > 80 ? 'badge-danger' : 'badge-success'}`;

  // Memory KPI
  valMemPct.textContent = `${d.mem.pct}%`;
  valMemUsed.textContent = d.mem.used;
  valMemTotal.textContent = d.mem.total;
  valMemAvail.textContent = d.mem.avail;
  valMemCache.textContent = d.mem.cache;
  barMem.style.width = `${d.mem.pct}%`;
  barMem.className = `progress-bar-fill ${d.mem.pct > 80 ? 'fill-red' : 'fill-cyan'}`;
  badgeMem.textContent = d.mem.pct > 80 ? 'High' : 'Healthy';
  badgeMem.className = `kpi-badge ${d.mem.pct > 80 ? 'badge-warning' : 'badge-success'}`;

  // Filesystems KPI
  const maxDisk = Math.max(...d.filesystems.map(f => f.pct));
  valDiskMax.textContent = `${maxDisk}%`;
  barDisk.style.width = `${maxDisk}%`;
  barDisk.className = `progress-bar-fill ${hasDiskAlert ? 'fill-red' : 'fill-green'}`;
  if (hasDiskAlert) {
    badgeDisk.textContent = 'Warning \u226590%';
    badgeDisk.className = 'kpi-badge badge-danger';
    diskSummaryText.innerHTML = '<strong style="color:var(--danger)">WARNING: at least one filesystem is at or above 90% usage.</strong>';
  } else {
    badgeDisk.textContent = 'Healthy';
    badgeDisk.className = 'kpi-badge badge-success';
    diskSummaryText.textContent = 'No filesystem \u226590% usage detected.';
  }

  // Auth Failures KPI
  valAuthCount.textContent = d.authFailCount;
  barAuth.style.width = `${Math.min(d.authFailCount * 20, 100)}%`;
  barAuth.className = `progress-bar-fill ${hasAuthFails ? 'fill-red' : 'fill-green'}`;
  badgeAuth.textContent = hasAuthFails ? `${d.authFailCount} Security Alerts` : '0 Failures';
  badgeAuth.className = `kpi-badge ${hasAuthFails ? 'badge-danger' : 'badge-success'}`;

  // Render Filesystems Table
  tbodyFilesystems.innerHTML = '';
  d.filesystems.forEach(fs => {
    const isAlert = fs.pct >= 90;
    const tr = document.createElement('tr');
    if (isAlert) tr.className = 'disk-alert-row';
    tr.innerHTML = `
      <td><strong>${escapeHtml(fs.fs)}</strong></td>
      <td>${fs.size}</td>
      <td>${fs.used}</td>
      <td>${fs.avail}</td>
      <td>
        <div class="usage-cell">
          <span class="${isAlert ? 'disk-alert-text' : ''}">${fs.pct}%</span>
          <div class="mini-bar">
            <div class="mini-bar-fill ${isAlert ? 'fill-red' : 'fill-green'}" style="width: ${fs.pct}%"></div>
          </div>
        </div>
      </td>
      <td><code>${escapeHtml(fs.mount)}</code></td>
    `;
    tbodyFilesystems.appendChild(tr);
  });

  // Render Top Processes Table
  renderProcesses();

  // Render Auth Logs
  authLogContent.innerHTML = '';
  if (d.authLogs.length === 0) {
    authLogContent.innerHTML = '<div class="log-entry ok">No authentication log events found.</div>';
  } else {
    d.authLogs.forEach(entry => {
      const div = document.createElement('div');
      div.className = `log-entry ${entry.type}`;
      div.textContent = entry.text;
      authLogContent.appendChild(div);
    });
  }

  // Render Raw Bash Report
  rawReportPre.textContent = generateRawBashReport(d);
}

function renderProcesses() {
  const query = procFilterInput.value.toLowerCase().trim();
  const filtered = query
    ? currentData.processes.filter(p => p.comm.toLowerCase().includes(query) || String(p.pid).includes(query))
    : currentData.processes;

  tbodyProcesses.innerHTML = '';
  filtered.forEach(p => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><code>${p.pid}</code></td>
      <td><strong>${escapeHtml(p.comm)}</strong></td>
      <td><span style="color:${p.cpu > 20 ? 'var(--danger)' : 'var(--text-main)'}">${p.cpu.toFixed(1)}%</span></td>
      <td>${p.mem.toFixed(1)}%</td>
      <td><span class="badge ${p.cpu > 20 ? 'badge-danger' : 'badge-dark'}">${p.cpu > 20 ? 'High CPU' : 'Running'}</span></td>
    `;
    tbodyProcesses.appendChild(tr);
  });
}

// Event Listeners
simButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    simButtons.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const scenarioKey = btn.dataset.scenario;
    currentScenario = scenarioKey;
    currentData = JSON.parse(JSON.stringify(SCENARIOS[scenarioKey]));
    renderDashboard();
    showToast(`Switched scenario to: ${btn.textContent}`, 'info');
  });
});

procFilterInput.addEventListener('input', renderProcesses);

btnRefresh.addEventListener('click', () => {
  // Add small random jitter for live feel
  if (currentScenario === 'normal') {
    currentData.loadAvg[0] = Math.max(0.2, (0.4 + Math.random() * 0.3));
    currentData.cpuPct = Math.round(20 + Math.random() * 10);
  }
  renderDashboard();
  showToast('Live system health check refreshed.', 'success');
});

btnExportReport.addEventListener('click', () => {
  const reportText = generateRawBashReport(currentData);
  const blob = new Blob([reportText], { type: 'text/plain;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'health-report.txt';
  a.click();
  URL.revokeObjectURL(url);
  showToast('health-report.txt downloaded.', 'success');
});

btnCopyReport.addEventListener('click', () => {
  const reportText = generateRawBashReport(currentData);
  navigator.clipboard.writeText(reportText).then(() => {
    showToast('Report copied to clipboard.', 'success');
  }).catch(() => {
    showToast('Failed to copy report.', 'danger');
  });
});

function showToast(msg, type = 'info') {
  const toast = document.getElementById('toast');
  toast.textContent = msg;
  toast.className = `toast show`;
  setTimeout(() => {
    toast.className = 'toast';
  }, 2600);
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Initial Render
renderDashboard();
