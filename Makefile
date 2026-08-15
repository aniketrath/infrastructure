SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# ==========================================
# Configuration Variables
# ==========================================
SSH_PORT_VM ?= 2223
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
	@echo "  make vm                 - Build and run the shared vm-test configuration[cite: 3]"
	@echo "  make disko HOST=<name>  - Build and boot a disko test image for a specific host[cite: 1]"
	@echo "  make test               - Run the full test suite (flake checks, evals, and boots)[cite: 2]"
	@echo "  make clean              - Clean up build results, logs, and temp disks"

# ==========================================
# 1. VM Test Target (from test-vm.sh)[cite: 3]
# ==========================================
vm:
	@echo "==> Building .#vm-test[cite: 3]"
	nix build .#vm-test $(NIX_FLAGS)
	@VM_SCRIPT=$$(find result/bin -maxdepth 1 -name 'run-*-vm' | head -n1); \
	if [ ! -x "$$VM_SCRIPT" ]; then echo "Error: No VM script found in result/bin/"; exit 1; fi; \
	echo "==> Booting VM headlessly, forwarding laptop:$(SSH_PORT_VM) -> VM:22"; \
	QEMU_NET_OPTS="hostfwd=tcp::$(SSH_PORT_VM)-:22" "$$VM_SCRIPT" & \
	VM_PID=$$!; \
	echo "VM started (pid $$VM_PID)"; \
	echo ""; \
	echo "Ready. Connect with:"; \
	echo "  ssh -p $(SSH_PORT_VM) $(SSH_USER)@localhost"; \
	echo "Stop it afterward with:"; \
	echo "  kill $$VM_PID"

# ==========================================
# 2. Disko Test Target (from test-disko.sh)[cite: 1]
# ==========================================
disko:
ifndef HOST
	@echo "Error: HOST is required. Usage: make disko HOST=<hostname>"
	@exit 1
endif
	@echo "==> Building .#$(HOST)-disko-image[cite: 1]"
	nix build ".#$(HOST)-disko-image" $(NIX_FLAGS)
	@IMG="result/main.raw"; \
	if [ ! -f "$$IMG" ]; then echo "Error: Expected image at $$IMG" >&2; exit 1; fi; \
	SCRATCH_IMG=$$(mktemp --tmpdir=. --suffix=.raw); \
	trap 'rm -f "$$SCRATCH_IMG"' EXIT; \
	cp -f "$$IMG" "$$SCRATCH_IMG"; \
	chmod +w "$$SCRATCH_IMG"; \
	OVMF_CODE="$$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd)/FV/OVMF.fd"; \
	echo "==> Booting $(HOST) under QEMU (TCG emulation, background)[cite: 1]"; \
	qemu-system-x86_64 \
	  -machine q35,accel=tcg \
	  -m 2048 \
	  -bios "$$OVMF_CODE" \
	  -drive file="$$SCRATCH_IMG",if=virtio,format=raw \
	  -netdev "user,id=n0,hostfwd=tcp::$(SSH_PORT_DISKO)-:22" \
	  -device virtio-net-pci,netdev=n0 \
	  -display sdl & \
	  QEMU_PID=$$!; \
	echo "QEMU started (pid $$QEMU_PID)"; \
	echo "==> Verifying boot via SSH (systemctl is-system-running --wait)[cite: 1]"; \
	SSH_READY=0; \
	ATTEMPTS=$$(( $(BOOT_TIMEOUT) / 5 )); \
	TEST_KEY="modules/disko-test-ssh-key"; \
	chmod 600 "$$TEST_KEY" 2>/dev/null || true; \
	for attempt in $$(seq 1 "$$ATTEMPTS"); do \
	  if ssh -p $(SSH_PORT_DISKO) -i "$$TEST_KEY" \
	    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -o ConnectTimeout=5 -o BatchMode=yes \
	    "$(SSH_USER)@localhost" 'systemctl is-system-running --wait' 2>/dev/null; then \
	    SSH_READY=1; \
	    break; \
	  fi; \
	  echo "   ... attempt $${attempt}/$$ATTEMPTS, not up yet, retrying"; \
	  sleep 15; \
	done; \
	kill "$$QEMU_PID" 2>/dev/null || true; \
	rm -f "$$SCRATCH_IMG"; \
	if [ "$$SSH_READY" == "1" ]; then \
	  echo "OK: $(HOST)'s disko module produced a bootable, fully-running image[cite: 1]"; \
	else \
	  echo "ERROR: $(HOST) never reached a running state via SSH" >&2; \
	  exit 1; \
	fi

# ==========================================
# 3. Full Test Suite (from test-suite.sh)[cite: 2]
# ==========================================
test:
	@echo "==> Running flake check"
	nix flake check
	@echo "==> Verifying flake.lock is committed[cite: 2]"
	git diff --quiet flake.lock 2>/dev/null || (echo "flake.lock has uncommitted changes" && exit 1)
	@echo "==> Verifying hostNames output resolves[cite: 2]"
	nix eval --json .#hostNames | jq -e "length > 0" >/dev/null
	@HOSTS=$$(nix eval --json .#hostNames 2>/dev/null | jq -r '.[]' 2>/dev/null); \
	for host in $$HOSTS; do \
	  echo "==> Evaluating nixosConfigurations.$$host[cite: 2]"; \
	  nix eval ".#nixosConfigurations.$$host.config.system.build.toplevel.drvPath"; \
	  echo "==> Evaluating $$host-disko-image derivation[cite: 2]"; \
	  nix eval ".#nixosConfigurations.$$host-disko-test.config.system.build.diskoImages.drvPath"; \
	done
	@echo "==> Running vm-test build + boot[cite: 2]"
	$(MAKE) vm DEBUG=$(DEBUG)
	@HOSTS=$$(nix eval --json .#hostNames 2>/dev/null | jq -r '.[]' 2>/dev/null); \
	for host in $$HOSTS; do \
	  echo "==> Running disko test for $$host[cite: 2]"; \
	  $(MAKE) disko HOST=$$host DEBUG=$(DEBUG); \
	done
	@echo "All tests passed successfully!"

# ==========================================
# Clean Target
# ==========================================
clean:
	@echo "Cleaning up results, logs, and temporary images..."
	rm -rf result result-* vm_disks logs/*.log *.raw
	@echo "Clean slate achieved!"