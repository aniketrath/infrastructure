#!/usr/bin/env bash
set -uo pipefail

# Runs every local check worth doing before pushing, roughly in the
# order CI would hit the equivalent failure (fast/cheap first). Reuses
# scripts/test-vm.sh and scripts/test-disko.sh rather than
# reimplementing their logic — this script is a runner, not a second
# copy of the build steps.
#
# Usage: scripts/test-suite.sh [--debug] [--skip-boot]

DEBUG=0
SKIP_BOOT=0
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    --skip-boot) SKIP_BOOT=1 ;;
  esac
done

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/test-suite-$(date +%Y%m%d-%H%M%S).log"

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

_ts() { date +"%H:%M:%S"; }

declare -a CHECK_NAMES=()
declare -a CHECK_RESULTS=()

run_check() {
  local name="$1"; shift
  echo "" | tee -a "$LOG_FILE"
  echo "${BLUE}[$(_ts)] ==> ${BOLD}${name}${RESET}" | tee -a "$LOG_FILE"
  if "$@" >>"$LOG_FILE" 2>&1; then
    echo "${GREEN}[$(_ts)] OK  ${RESET} ${name}" | tee -a "$LOG_FILE"
    CHECK_NAMES+=("$name"); CHECK_RESULTS+=("PASS")
  else
    echo "${RED}[$(_ts)] FAIL${RESET} ${name} — see $LOG_FILE" | tee -a "$LOG_FILE"
    CHECK_NAMES+=("$name"); CHECK_RESULTS+=("FAIL")
  fi
}

echo "${BOLD}Running local test suite. Full log: $LOG_FILE${RESET}"

run_check "flake check" nix flake check

run_check "flake.lock is committed" bash -c '
  if ! git diff --quiet flake.lock 2>/dev/null || ! git diff --cached --quiet flake.lock 2>/dev/null; then
    echo "flake.lock has uncommitted/unstaged changes"
    exit 1
  fi
'

run_check "hostNames output resolves" bash -c '
  nix eval --json .#hostNames | jq -e "length > 0" >/dev/null
'

HOSTS=$(nix eval --json .#hostNames 2>>"$LOG_FILE" | jq -r '.[]' 2>>"$LOG_FILE")
if [[ -z "$HOSTS" ]]; then
  echo "${YELLOW}[$(_ts)] WARN${RESET} could not read host list — skipping per-host checks" | tee -a "$LOG_FILE"
fi

for host in $HOSTS; do
  run_check "eval nixosConfigurations.${host}" bash -c "
    nix eval '.#nixosConfigurations.${host}.config.system.build.toplevel.drvPath'
  "
done

for host in $HOSTS; do
  run_check "eval ${host}-disko-image derivation" bash -c "
    nix eval '.#nixosConfigurations.${host}-disko-test.config.system.build.diskoImages.drvPath'
  "
done

if [[ "$SKIP_BOOT" == "1" ]]; then
  echo "${YELLOW}[$(_ts)] WARN${RESET} --skip-boot set — skipping vm-test and disko boot tests" | tee -a "$LOG_FILE"
else
  VM_TEST_ARGS=()
  [[ "$DEBUG" == "1" ]] && VM_TEST_ARGS+=(--debug)
  run_check "vm-test build + boot" bash "$REPO_ROOT/scripts/test-vm.sh" "${VM_TEST_ARGS[@]}"

  for host in $HOSTS; do
    DISKO_ARGS=("$host")
    [[ "$DEBUG" == "1" ]] && DISKO_ARGS+=(--debug)
    run_check "${host}: disko build + boot" bash "$REPO_ROOT/scripts/test-disko.sh" "${DISKO_ARGS[@]}"
  done
fi

echo ""
echo "${BOLD}=== Summary ===${RESET}"
FAILED=0
for i in "${!CHECK_NAMES[@]}"; do
  if [[ "${CHECK_RESULTS[$i]}" == "PASS" ]]; then
    echo "${GREEN}PASS${RESET}  ${CHECK_NAMES[$i]}"
  else
    echo "${RED}FAIL${RESET}  ${CHECK_NAMES[$i]}"
    FAILED=1
  fi
done
echo ""
echo "Full log: $LOG_FILE"

if [[ "$FAILED" == "1" ]]; then
  echo "${RED}${BOLD}One or more checks failed — see log for details before pushing.${RESET}"
  exit 1
else
  echo "${GREEN}${BOLD}All checks passed.${RESET}"
  exit 0
fi
