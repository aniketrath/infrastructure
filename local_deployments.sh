#!/usr/bin/env bash
set -euo pipefail

# Builds the Docker-test image from the current flake, tags it, runs it,
# and prints the SSH command to hop in. Run this from the repo root.

CONTAINER_NAME="homelab-ssh-test"
IMAGE_TAG="homelab-test:latest"
SSH_PORT=2222
SSH_USER="homelabadmin"

mkdir -p logs
LOG_FILE="logs/test-local-$(date +%Y%m%d-%H%M%S).log"

# Colors (skip if not an interactive terminal, e.g. redirected to a file)
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

_ts() { date +"%H:%M:%S"; }

log_info()    { echo "${BLUE}[$(_ts)] ==>${RESET} $*"       | tee -a "$LOG_FILE"; }
log_success() { echo "${GREEN}[$(_ts)] OK  ${RESET} $*"     | tee -a "$LOG_FILE"; }
log_warn()    { echo "${YELLOW}[$(_ts)] WARN${RESET} $*"    | tee -a "$LOG_FILE"; }
log_error()   { echo "${RED}[$(_ts)] ERROR${RESET} $*" >&2  | tee -a "$LOG_FILE" >&2; }

trap 'log_error "Failed at line $LINENO. See $LOG_FILE for the full run."' ERR

log_info "Building .#homelab-docker-test (this can take a while on first build)"
if nix build .#homelab-docker-test 2>&1 | tee -a "$LOG_FILE"; then
  log_success "Build finished"
else
  log_error "Build failed"
  exit 1
fi

log_info "Locating the built tarball"
IMAGE_TAR=$(find result/tarball -maxdepth 1 \( -name '*.tar.xz' -o -name '*.tar' \) 2>/dev/null | head -n1)
if [[ -z "$IMAGE_TAR" ]]; then
  log_warn "Nothing found under result/tarball/, searching result/ more broadly"
  IMAGE_TAR=$(find result -name '*.tar.xz' -o -name '*.tar' | head -n1)
fi
if [[ -z "$IMAGE_TAR" ]]; then
  log_error "No tarball found under result/"
  exit 1
fi
log_success "Found: $IMAGE_TAR"

log_info "Cleaning up any previous test container ($CONTAINER_NAME)"
if docker rm -f "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1; then
  log_success "Removed previous container"
else
  log_warn "No previous container to remove"
fi

log_info "Importing image as $IMAGE_TAG"
if docker import "$IMAGE_TAR" "$IMAGE_TAG" >>"$LOG_FILE" 2>&1; then
  log_success "Imported as $IMAGE_TAG"
else
  log_error "docker import failed"
  exit 1
fi

log_info "Starting container ($CONTAINER_NAME)"
if docker run -d --privileged \
  --network host \
  --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
  -e container=docker \
  --name "$CONTAINER_NAME" \
  "$IMAGE_TAG" /init >>"$LOG_FILE" 2>&1; then
  log_success "Container started"
else
  log_error "docker run failed"
  exit 1
fi

log_info "Waiting for sshd to come up..."
sleep 5

if docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
  log_success "Container is running"
else
  log_error "Container is not running — check $LOG_FILE and 'docker logs $CONTAINER_NAME'"
  exit 1
fi

echo ""
echo "${BOLD}${GREEN}Ready. Connect with:${RESET}"
echo ""
echo "  ${BOLD}ssh -p ${SSH_PORT} ${SSH_USER}@localhost${RESET}"
echo ""
echo "Stop and remove it afterward with:"
echo ""
echo "  docker rm -f ${CONTAINER_NAME}"
echo ""
echo "Full run log: $LOG_FILE"
