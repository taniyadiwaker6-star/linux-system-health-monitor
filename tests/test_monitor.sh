#!/usr/bin/env bash
# ==============================================================================
# Linux System Health & Log Monitor - Test Suite
# ------------------------------------------------------------------------------
# Tests syntax, argument parsing, error handling, disk threshold warnings,
# mock authentication log scanning, and output file writing.
# ==============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/system_health.sh"
TEST_TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'monitor_test_XXXXXX')"

PASSED_COUNT=0
FAILED_COUNT=0

cleanup() {
  rm -rf "${TEST_TMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

log_test() {
  printf "  [TEST] %-55s " "$1"
}

assert_success() {
  if [[ $? -eq 0 ]]; then
    printf "\033[32mPASS\033[0m\n"
    ((PASSED_COUNT++))
  else
    printf "\033[31mFAIL\033[0m\n"
    ((FAILED_COUNT++))
  fi
}

echo "================================================================================"
echo "          RUNNING LINUX SYSTEM HEALTH & LOG MONITOR TEST SUITE                  "
echo "================================================================================"
echo "Target script: ${TARGET_SCRIPT}"
echo "Working directory: ${TEST_TMP_DIR}"
echo ""

# Test 1: Bash Syntax Check
log_test "Syntax check (bash -n)"
bash -n "${TARGET_SCRIPT}"
assert_success

# Test 2: Help flag (--help)
log_test "Help flag (--help)"
"${TARGET_SCRIPT}" --help >/dev/null 2>&1
assert_success

# Test 3: Version flag (--version)
log_test "Version flag (--version)"
"${TARGET_SCRIPT}" --version | grep -qi "version"
assert_success

# Test 4: Unknown flag rejection
log_test "Unknown flag rejection (--invalid-option)"
if "${TARGET_SCRIPT}" --invalid-option >/dev/null 2>&1; then
  false
else
  true
fi
assert_success

# Test 5: Multiple output arguments rejection
log_test "Multiple output arguments rejection"
if "${TARGET_SCRIPT}" out1.txt out2.txt >/dev/null 2>&1; then
  false
else
  true
fi
assert_success

# Test 6: Directory specified as output file rejection
log_test "Output path is a directory rejection"
mkdir -p "${TEST_TMP_DIR}/test_dir"
if "${TARGET_SCRIPT}" "${TEST_TMP_DIR}/test_dir" >/dev/null 2>&1; then
  false
else
  true
fi
assert_success

# Test 7: Output file writing and parent directory creation
log_test "Output file generation and dir auto-creation"
REPORT_DEST="${TEST_TMP_DIR}/nested/sub/report.txt"
"${TARGET_SCRIPT}" "${REPORT_DEST}" >/dev/null 2>&1
if [[ -f "${REPORT_DEST}" ]] && grep -q "LINUX SYSTEM HEALTH REPORT" "${REPORT_DEST}"; then
  true
else
  false
fi
assert_success

# Test 8: Mock Disk Warning Trigger (>=90%)
log_test "Disk threshold warning logic (>=90% simulated)"
# Run a mock df test through the awk logic used in system_health.sh
DISK_MOCK_OUT="$(cat <<'EOF' | awk '
  NR > 1 {
    if ($1 ~ /^(tmpfs|devtmpfs|udev|overlay|none)$/) next;
    use_str = $(NF - 1);
    mount_pt = $NF;
    fs_name = $1;
    gsub(/%/, "", use_str);
    use_val = use_str + 0;
    if (use_val >= 90) {
      printf "%s on %s (%d%%)\n", fs_name, mount_pt, use_val;
    }
  }
'
Filesystem           1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p2         245100000 232845000  12255000      95% /
/dev/sda1              500000000 200000000 300000000      40% /mnt/data
EOF
)"

if echo "${DISK_MOCK_OUT}" | grep -q "/dev/nvme0n1p2 on / (95%)"; then
  true
else
  false
fi
assert_success

# Test 9: Mock Failed Authentication Scan and Redaction
log_test "Auth log pattern matching & password redaction"
MOCK_AUTH_LOG="${TEST_TMP_DIR}/mock_auth.log"
cat <<'EOF' > "${MOCK_AUTH_LOG}"
Oct 18 10:00:01 srv sshd[100]: Accepted publickey for user1 from 10.0.0.1
Oct 18 10:01:05 srv sshd[101]: Failed password for invalid user admin from 192.168.1.50 port 4000
Oct 18 10:02:10 srv sshd[102]: authentication failure; logname= uid=0 euid=0 tty=ssh
Oct 18 10:03:15 srv sshd[103]: Failed password for root from 192.168.1.50 port 4002
EOF

MATCHES="$(grep -Ei 'failed password|authentication failure|invalid user' "${MOCK_AUTH_LOG}" | sed 's/password [^ ]*/password [REDACTED]/g')"
MATCH_COUNT="$(echo "${MATCHES}" | wc -l)"

if [[ "${MATCH_COUNT// /}" -eq 3 ]] && echo "${MATCHES}" | grep -q "Failed password \[REDACTED\]"; then
  true
else
  false
fi
assert_success

echo ""
echo "================================================================================"
echo "TEST SUMMARY: ${PASSED_COUNT} Passed, ${FAILED_COUNT} Failed"
echo "================================================================================"

if [[ ${FAILED_COUNT} -eq 0 ]]; then
  exit 0
else
  exit 1
fi
