SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# ==========================================
# Configuration Variables
# ==========================================
SSH_PORT_VM ?= 2222
SSH_PORT_DISKO ?= 2223
SSH_USER ?= homelabadmin
BOOT_TIMEOUT ?= 180
DEBUG ?= 0

NIX_FLAGS =
ifeq ($(DEBUG),1)
NIX_FLAGS = -L --print-build-logs
endif

LOG_DIR ?= logs
$(shell mkdir -p $(LOG_DIR))

.PHONY: help vm disko test clean

# ==========================================
# Help Target
# ==========================================
help:
	@echo "Available Makefile targets:"
	@echo "  make vm                 - Build and run the shared vm-test configuration"
	@echo "  make disko HOST=<name>  - Build and boot a disko test image for a specific host"
	@echo "  make test               - Run the full test suite (flake checks, vm, and all disko images)"
	@echo "  make clean              - Clean up build results, logs, and temp disks"

# ==========================================
# 1. VM Test Target
# ==========================================
vm:
	@echo "==> Building .#vm-test"
	nix build .#vm-test $(NIX_FLAGS)
	@VM_SCRIPT=$$(find result/bin -maxdepth 1 -name 'run-*-vm' | head -n1); \
	if [ ! -x "$$VM_SCRIPT" ]; then echo "Error: No VM script found in result/bin/"; exit 1; fi; \
	if [ -z "$${DISPLAY:-}" ] && [ -z "$${WAYLAND_DISPLAY:-}" ]; then \
	  echo "Error: no DISPLAY/WAYLAND_DISPLAY set - SDL console cannot open" >&2; \
	  exit 1; \
	fi; \
	echo "==> Booting VM in dedicated graphical window..."; \
	QEMU_NET_OPTS="hostfwd=tcp::$(SSH_PORT_VM)-:22" DISPLAY=$(DISPLAY) WAYLAND_DISPLAY=$${WAYLAND_DISPLAY:-} "$$VM_SCRIPT" -device virtio-vga -display sdl & \
	VM_PID=$$!; \
	trap 'kill "$$VM_PID" 2>/dev/null || true' EXIT; \
	sleep 1; \
	if ! kill -0 "$$VM_PID" 2>/dev/null; then \
	  echo "Error: QEMU exited immediately after launch." >&2; \
	  exit 1; \
	fi; \
	echo "VM started (pid $$VM_PID) with standalone graphical window."; \
	echo "Ready. Connect with: ssh -p $(SSH_PORT_VM) $(SSH_USER)@localhost"; \
	trap - EXIT

# ==========================================
# 2. Disko Test Target
# ==========================================
disko:
ifndef HOST
	@echo "Error: HOST is required. Usage: make disko HOST=<hostname>"
	@exit 1
endif
	@echo "==> Building .#$(HOST)-disko-image"
	nix build ".#$(HOST)-disko-image" $(NIX_FLAGS)
	@IMG="result/main.raw"; \
	if [ ! -f "$$IMG" ]; then echo "Error: Expected image at $$IMG" >&2; exit 1; fi; \
	SCRATCH_IMG=$$(mktemp --tmpdir=. --suffix=.raw); \
	trap 'rm -f "$$SCRATCH_IMG"; kill "$$QEMU_PID" 2>/dev/null || true' EXIT; \
	cp -f "$$IMG" "$$SCRATCH_IMG"; \
	chmod +w "$$SCRATCH_IMG"; \
	OVMF_CODE="$$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd)/FV/OVMF.fd"; \
	echo "==> Booting $(HOST) in background (headless testing with SSH verification)..."; \
	qemu-system-x86_64 \
	  -machine q35,accel=tcg \
	  -m 2048 \
	  -name "$(HOST)-disko-test" \
	  -bios "$$OVMF_CODE" \
	  -drive file="$$SCRATCH_IMG",if=virtio,format=raw \
	  -netdev "user,id=n0,hostfwd=tcp::$(SSH_PORT_DISKO)-:22" \
	  -device virtio-net-pci,netdev=n0 \
	  -display none & \
	  QEMU_PID=$$!; \
	sleep 1; \
	if ! kill -0 "$$QEMU_PID" 2>/dev/null; then \
	  echo "Error: QEMU exited immediately after launch." >&2; \
	  exit 1; \
	fi; \
	echo "QEMU started (pid $$QEMU_PID) in background."; \
	echo "==> Verifying boot via SSH (systemctl is-system-running --wait)..."; \
	SSH_READY=0; \
	ATTEMPTS=$$(( $(BOOT_TIMEOUT) / 5 )); \
	TEST_KEY="modules/disko-test-ssh-key"; \
	chmod 600 "$$TEST_KEY" 2>/dev/null || true; \
	for attempt in $$(seq 1 "$$ATTEMPTS"); do \
	  if ! kill -0 "$$QEMU_PID" 2>/dev/null; then \
	    echo "Error: QEMU process died mid-boot (pid $$QEMU_PID no longer running)" >&2; \
	    exit 1; \
	  fi; \
	  if ssh -p $(SSH_PORT_DISKO) -i "$$TEST_KEY" \
	    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -o ConnectTimeout=5 -o BatchMode=yes \
	    "$(SSH_USER)@localhost" 'systemctl is-system-running --wait' 2>/dev/null; then \
	    SSH_READY=1; \
	    break; \
	  fi; \
	  sleep 15; \
	done; \
	kill "$$QEMU_PID" 2>/dev/null || true; \
	rm -f "$$SCRATCH_IMG"; \
	if [ "$$SSH_READY" == "1" ]; then \
	  echo "OK: $(HOST)'s disko module produced a bootable, fully-running image"; \
	else \
	  echo "ERROR: $(HOST) never reached a running state via SSH" >&2; \
	  exit 1; \
	fi; \
	trap - EXIT

# ==========================================
# 3. Full Test Suite
# ==========================================
test:
	@echo "==> Running flake check"
	nix flake check
	@echo "==> Verifying flake.lock is committed"
	git diff --quiet flake.lock 2>/dev/null || (echo "flake.lock has uncommitted changes" && exit 1)
	@echo "==> Verifying hostNames output resolves"
	nix eval --json .#hostNames | jq -e "length > 0" >/dev/null
	@HOSTS=$$(nix eval --json .#hostNames 2>/dev/null | jq -r '.[]' 2>/dev/null); \
	for host in $$HOSTS; do \
	  echo "==> Evaluating nixosConfigurations.$$host"; \
	  nix eval ".#nixosConfigurations.$$host.config.system.build.toplevel.drvPath"; \
	  echo "==> Evaluating $$host-disko-image derivation"; \
	  nix eval ".#nixosConfigurations.$$host-disko-test.config.system.build.diskoImages.drvPath"; \
	done
	@echo "==> Running vm-test build + boot"
	$(MAKE) vm DEBUG=$(DEBUG)
	@echo "==> Running disko tests for all host configurations..."
	@HOSTS=$$(nix eval --json .#hostNames 2>/dev/null | jq -r '.[]' 2>/dev/null); \
	for host in $$HOSTS; do \
	  echo "==> Testing disko image for: $$host"; \
	  $(MAKE) disko HOST=$$host DEBUG=$(DEBUG) || exit 1; \
	done
	@echo "All tests passed successfully!"

# ==========================================
# Clean Target
# ==========================================
clean:
	@echo "Cleaning up results, logs, and temporary images..."
	rm -rf result result-* vm_disks logs/*.log *.raw
	@echo "Clean slate achieved!"