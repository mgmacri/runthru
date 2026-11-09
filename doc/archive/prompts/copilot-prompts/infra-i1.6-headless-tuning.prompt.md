---
description: "Infra I1.6: systemd user unit for VM auto-start, memory balloon + CPU tuning, and optional SSH MCP server setup for Claude Code direct VM access."
mode: agent
---

# Infra Step I1.6 — Headless Hardening

> **Milestone**: I1.6 | **Backlog**: `doc/infra-backlog.json`
> **Depends on**: I1.5 (all scripts working)
> **Produces**: `scripts/infra/osx-kvm.service`, `scripts/infra/install-service.sh`, `scripts/infra/MCP-SSH-SETUP.md`, updated `launch-vm.sh`

Load shared context first: [infra-osx-kvm-context](./../instructions/infra-osx-kvm-context.instructions.md)

---

## Task

### TI1.6.1.1 — systemd user unit

Create `scripts/infra/osx-kvm.service` (systemd **user** unit — no root needed):

```ini
[Unit]
Description=OSX-KVM macOS Ventura VM
After=network.target

[Service]
Type=forking
PIDFile=/tmp/osx-kvm.pid
ExecStart=/bin/bash %h/dev/speedy-boyv3/scripts/infra/launch-vm.sh
ExecStop=/bin/bash -c 'ssh -o ConnectTimeout=5 mac-vm "sudo shutdown -h now" || kill $(cat /tmp/osx-kvm.pid)'
Restart=on-failure
RestartSec=10
TimeoutStopSec=30

[Install]
WantedBy=default.target
```

Note: `%h` expands to $HOME in systemd user units.

Create `scripts/infra/install-service.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cp "$(dirname "$0")/osx-kvm.service" "$UNIT_DIR/osx-kvm.service"
systemctl --user daemon-reload
systemctl --user enable osx-kvm
echo "Installed. Use: systemctl --user start|stop|status osx-kvm"
```

### TI1.6.2.1 — Resource tuning in launch-vm.sh

Add to the QEMU flags:

1. **Memory balloon** (macOS can return unused RAM to host):
   ```bash
   -device virtio-balloon-pci
   ```

2. **CPU mode** (better build perf on Intel host):
   ```bash
   # Detect if KVM host mode is safe (Intel hosts only):
   if grep -q GenuineIntel /proc/cpuinfo; then
     CPU_FLAGS="-cpu host,kvm=on,+invtsc"
   else
     CPU_FLAGS="-cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc"
   fi
   ```

3. **Disk I/O** (faster build times):
   ```bash
   -drive file=...,if=virtio,format=qcow2,cache=writeback,discard=unmap
   ```
   `cache=writeback` is safe for a dev VM (not a database). `discard=unmap` reclaims freed space.

4. Update the header comment in `launch-vm.sh`:
   ```
   # Resource profile (6 cores, 8GB allocated):
   # - Host idle: ~400MB QEMU overhead + macOS usage
   # - During flutter build: ~6-8 cores active, ~7GB RAM in use
   # - Balloon driver returns unused VM RAM to host between builds
   ```

### TI1.6.3.1 — scripts/infra/MCP-SSH-SETUP.md

Document the optional SSH MCP server that lets Claude Code run commands directly in the VM:

```markdown
# SSH MCP Server — Claude Code Direct VM Access (Optional)

This allows Claude Code to run `dart analyze`, `flutter build`, etc. in the VM
directly during a session — no manual terminal switching.

## Option A: mcp-server-shell with SSH wrapper (simplest)

1. Install: npm i -g @anthropic-ai/mcp-server-shell (or equivalent available package)
2. Add to .claude/settings.json:

{
  "mcpServers": {
    "mac-vm": {
      "command": "ssh",
      "args": ["-t", "mac-vm", "bash -l"],
      "description": "macOS VM shell — flutter build, xcodebuild, device commands"
    }
  }
}

## Option B: mcp-server-ssh (dedicated SSH MCP)

Check https://github.com/anthropics/mcp-servers for the current SSH server package.

## Security Note

Scope this MCP server to mac-vm only. Do not configure a general shell MCP that can
reach the Linux host with write access. The VM is a sandboxed environment — it's the
right place to run potentially long build commands.

## Verification

In a Claude Code session, you should be able to run:
  "Run dart analyze in the VM"
And Claude will use the mac-vm MCP tool directly.
```

---

## Verification

```bash
bash -n scripts/infra/install-service.sh && echo service SYNTAX_OK
grep -q 'virtio-balloon' scripts/infra/launch-vm.sh && echo BALLOON_OK
grep -q 'GenuineIntel' scripts/infra/launch-vm.sh && echo CPU_DETECT_OK
test -f scripts/infra/MCP-SSH-SETUP.md && echo MCP_DOC_OK

# After install-service.sh:
systemctl --user status osx-kvm
```
