---
description: "Infra I1.1: Bootstrap OSX-KVM — clone repo, create disk image, write headless QEMU launch script, configure SSH alias. Produces scripts/infra/launch-vm.sh, setup-ssh.sh, snapshot.sh, FIRST-BOOT.md."
mode: agent
---

# Infra Step I1.1 — VM Bootstrap

> **Milestone**: I1.1 | **Backlog**: `doc/infra-backlog.json`
> **Depends on**: nothing
> **Produces**: `scripts/infra/launch-vm.sh`, `setup-ssh.sh`, `snapshot.sh`, `FIRST-BOOT.md`

Load shared context first: [infra-osx-kvm-context](./../instructions/infra-osx-kvm-context.instructions.md)

---

## Task

Create all scripts needed to get a headless macOS Ventura VM running on this Linux host and
accessible via SSH as `mac-vm`.

### TI1.1.1.1 — scripts/infra/fetch-macos.sh

Write a script that:
1. Checks for `git`, `qemu-img`, `dmg2img` and prints install hint if missing
2. Clones `https://github.com/kholia/OSX-KVM.git` to `$HOME/OSX-KVM` (skips if exists)
3. Runs `cd $HOME/OSX-KVM && python3 fetch-macOS-v2.py` — user selects Ventura interactively
4. Converts: `dmg2img $HOME/OSX-KVM/BaseSystem.dmg $HOME/OSX-KVM/BaseSystem.img`
5. Creates disk: `qemu-img create -f qcow2 $HOME/OSX-KVM/mac_hdd_ng.img 120G`

### TI1.1.1.2 — scripts/infra/launch-vm.sh

Write a QEMU launch script with:
- Default mode: headless (`-display none -daemonize -pidfile /tmp/osx-kvm.pid`)
- `--vnc` flag: adds `-display vnc=:1` (port 5901), removes daemonize — for initial setup only
- `--usb-passthrough` flag: detects connected iPhone via `lsusb | grep -i '05ac'`, adds `-device usb-ehci,id=ehci -device usb-host,vendorid=0x05ac,productid=<detected>`
- `--stop` flag: graceful shutdown via `ssh mac-vm 'sudo shutdown -h now'`; fallback kill via PID
- `--dry-run` flag: prints the QEMU command that would run, exits 0 without executing
- Use exact QEMU flags from the context file
- Header comment documents: expected idle host RAM usage (~6GB when VM active)

### TI1.1.2.2 — scripts/infra/setup-ssh.sh

Write a script that:
1. Generates `~/.ssh/mac_vm_key` (ed25519) if it does not exist
2. Appends to `~/.ssh/config` (idempotent — checks for existing `Host mac-vm` block):
   ```
   Host mac-vm
     HostName localhost
     Port 2222
     User <prompt user for VM username>
     IdentityFile ~/.ssh/mac_vm_key
     StrictHostKeyChecking no
   ```
3. Runs `ssh-copy-id -i ~/.ssh/mac_vm_key mac-vm` to install the public key
4. Verifies: `ssh mac-vm 'uname -s'` returns `Darwin`

### TI1.1.2.3 — scripts/infra/snapshot.sh

Write a script with subcommands:
- `snapshot.sh create <name>` — `qemu-img snapshot -c <name> $HOME/OSX-KVM/mac_hdd_ng.img` (VM must be stopped)
- `snapshot.sh restore <name>` — `qemu-img snapshot -a <name> ...` (VM must be stopped)
- `snapshot.sh list` — `qemu-img snapshot -l ...`
- Guards: checks VM is not running (reads /tmp/osx-kvm.pid) before create/restore

### TI1.1.2.1 — scripts/infra/FIRST-BOOT.md

Write a step-by-step guide covering:
1. Prerequisites: `sudo pacman -S qemu-full dmg2img python-requests inotify-tools` (Arch Linux)
2. Run `fetch-macos.sh` to download Ventura
3. Run `launch-vm.sh --vnc` — connect VNC client to `localhost:5901`
4. In macOS installer: Disk Utility → erase `QEMU HARDDISK Media` as APFS → Install macOS
5. Post-install: System Settings → General → Sharing → enable Remote Login (SSH)
6. Terminal: `sudo systemsetup -setcomputersleep Never`
7. Back on Linux: run `setup-ssh.sh`
8. Verify: `ssh mac-vm 'uname -a'` returns Darwin
9. Take baseline snapshot: `snapshot.sh create baseline`
10. Switch to headless: `launch-vm.sh --stop` then `launch-vm.sh`

---

## Verification

Run after all scripts are created:

```bash
bash -n scripts/infra/launch-vm.sh && echo launch-vm OK
bash -n scripts/infra/setup-ssh.sh && echo setup-ssh OK
bash -n scripts/infra/snapshot.sh  && echo snapshot OK
bash scripts/infra/launch-vm.sh --dry-run
```

All must exit 0. The dry-run must print a valid QEMU command containing `-enable-kvm` and
`hostfwd=tcp::2222-:22`.
