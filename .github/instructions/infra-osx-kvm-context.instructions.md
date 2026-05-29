---
description: "OSX-KVM iOS dev infrastructure: host specs, VM config, SSH aliases, Flutter version, script conventions, and tiered CI design. Load for any infra task."
applyTo: "scripts/infra/**,doc/infra-backlog.json"
---

# Infrastructure Context — OSX-KVM iOS Dev Loop

Source of truth for any session working on the RunThru iOS dev infrastructure.

## Why This Exists

Linux cannot run Xcode natively. OSX-KVM runs macOS Ventura in a KVM/QEMU VM on the Linux
host, giving us a full Xcode toolchain. The CI loop is **tiered** to minimise VM usage:

> ⚠️ **The host is AMD, not Intel.** macOS XNU does not boot on AMD CPUs without the
> AMD_Vanilla kernel patches injected via OpenCore (`~/OSX-KVM/OpenCore/config.plist`).
> Symptom of missing/broken patches: VM hangs immediately after the `HANDOFF TO XNU`
> serial line with one vCPU pinned at 100% forever (frozen at `fletcher64`/APFS init).
> See the **AMD / OpenCore** section below before touching `-cpu`, `-smp`, or OpenCore.

| Tier | Where | Trigger | Time |
|------|-------|---------|------|
| 1 | Linux host | Every save | ~2s |
| 2 | macOS VM | Manual / `--build` flag | ~30s |
| 3 | macOS VM + iPhone | Manual / `--run` flag | ~60s |

Tier 1 (dart analyze + flutter test) never touches the VM. The VM only wakes for a build or device run.

## Host Machine

| Item | Value |
|------|-------|
| OS | Arch Linux |
| Kernel | 7.0.6-arch1-1 |
| CPU | **AMD Ryzen 5 3600** (6 cores / 12 threads, `AuthenticAMD`, `svm`, `kvm_amd`) |
| RAM | 15 GB |
| Free disk | ~288 GB (SSD) |
| VM allocation | 4 cores (no SMT), 4 GB RAM |

## VM Configuration

| Item | Value |
|------|-------|
| macOS version | Ventura (13.x) |
| Disk image | `$HOME/OSX-KVM/mac_hdd_ng.img` (120 GB qcow2) |
| SSH port forward | `localhost:2222 → VM:22` |
| SSH alias | `mac-vm` (defined in `~/.ssh/config`) |
| SSH key | `~/.ssh/mac_vm_key` (ed25519) |
| Project path in VM | `~/runthru` |
| Sleep | Disabled (`sudo systemsetup -setcomputersleep Never`) |

Reference QEMU launch flags:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -smp 4,cores=4,sockets=1 \  # cores MUST equal the cpuid_cores_per_package patch; no SMT on AMD
  -cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,... \  # never -cpu host on AMD
  -machine q35 \
  -device virtio-balloon-pci \
  -drive if=pflash,format=raw,readonly=on,file=$HOME/OSX-KVM/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=$HOME/OSX-KVM/OVMF_VARS-1024x768.fd \
  -drive file=$HOME/OSX-KVM/OpenCore-v21.qcow2,if=virtio,format=qcow2 \
  -drive file=$HOME/OSX-KVM/mac_hdd_ng.img,if=virtio,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0,id=net0 \
  -display none \
  -daemonize \
  -pidfile /tmp/osx-kvm.pid
```

Add for USB iPhone passthrough (VM must start with iPhone already connected):
```bash
  -device usb-ehci,id=ehci \
  -device usb-host,vendorid=0x05ac,productid=<product_id>
```

## Flutter Version

| Item | Value |
|------|-------|
| SDK constraint | `^3.11.0` (from `pubspec.yaml`) |
| Channel | stable |
| Install path in VM | `~/flutter` |
| PATH | Added to `~/.zshrc` and `~/.bash_profile` in VM |

## SSH Conventions

All VM operations go through the `mac-vm` alias. Never hardcode `localhost:2222`.

```bash
# Run a single command
ssh mac-vm 'flutter doctor'

# Stream real-time output (builds)
ssh mac-vm 'cd ~/runthru && flutter build ios --no-codesign'

# Interactive TTY (flutter run with hot reload)
ssh -t mac-vm 'cd ~/runthru && flutter run -d <device_id>'

# Run a local script in VM
ssh mac-vm 'bash -s' < scripts/infra/setup-toolchain.sh
```

## Scripts Layout (created by step prompts)

```
scripts/infra/
  launch-vm.sh          # Start/stop headless VM (--vnc flag for setup mode)
  snapshot.sh           # create|restore|list qemu-img snapshots
  setup-ssh.sh          # Generates keypair + ~/.ssh/config entry
  setup-toolchain.sh    # Installs Xcode CLI + Flutter + CocoaPods in VM (runs via SSH)
  sync.sh               # rsync project to VM (excludes build/, .dart_tool/, Pods/)
  watch.sh              # inotifywait loop: Tier 1 on host, Tier 2 in VM on demand
  build-ios.sh          # sync + flutter build ios --no-codesign in VM
  run-device.sh         # sync + flutter run on connected iPhone via VM
  ci.sh                 # Unified entry point (--tier 1|2|3, --watch, --status)
  install-service.sh    # Installs systemd user unit for VM auto-start
  setup-usb-passthrough.sh  # udev rules for Apple USB (vendor 05ac)
  FIRST-BOOT.md         # Step-by-step guide for VNC setup of fresh macOS
  MCP-SSH-SETUP.md      # Optional: SSH MCP server config for Claude Code VM access
```

## rsync Excludes

Always exclude from sync:
```
.dart_tool/
build/
.git/
.fvm/
ios/Pods/
ios/.symlinks/
android/.gradle/
android/build/
```

## iPhone USB Passthrough Notes

- iPhone vendor ID is always `0x05ac`. Product ID varies by model — detect via `lsusb`.
- VM **must be started** with the iPhone already connected (QEMU reads USB bus at launch).
- After "Trust This Computer" prompt on iPhone, run `ssh mac-vm 'flutter devices'` to verify.
- If iPhone disconnects: must restart VM with `--usb-passthrough` to re-attach.

## AMD / OpenCore (CRITICAL — host is AMD Ryzen)

macOS only boots here because `~/OSX-KVM/OpenCore/config.plist` carries the
[AMD_Vanilla](https://github.com/AMD-OSX/AMD_Vanilla) `Kernel > Patch` set. Key facts:

- The patch set is **appended after** the 12 stock OSX-KVM patches (don't delete the
  stock ones; the only enabled stock patch is "Enable TRIM").
- The four `algrey | Force cpuid_cores_per_package to constant` patches are pinned to a
  **constant core count** (byte index 1 of each `Replace`). It is set to **4** and MUST
  equal `-smp` `cores=` in `launch-vm.sh` (`VM_CORES`). Mismatch → boot hang.
- Use `-cpu Penryn,...,vendor=GenuineIntel,...`. **Never `-cpu host`** on AMD.
- `-smp 4,cores=4,sockets=1` — no SMT (`threads=1`); the topology patch is unreliable
  with `threads>1` on AMD.
- The OpenCore drive uses `snapshot=on`, so runtime writes are discarded — config
  changes must be baked into `OpenCore.qcow2`, not made live.

**Re-applying patches after a macOS upgrade** (patches are Darwin-kernel-version gated;
the merged set already includes 10.13→15 variants, but to refresh):

```bash
bash scripts/infra/launch-vm.sh --stop
cd ~/OSX-KVM/OpenCore && cp config.plist config.plist.bak-$(date +%F)
curl -fsSL -o /tmp/amd.plist https://raw.githubusercontent.com/AMD-OSX/AMD_Vanilla/master/patches.plist
# python: load both, set cpuid_cores_per_package Replace[1]=<VM_CORES>,
#         cfg['Kernel']['Patch'] = stock(non-algrey) + amd_patches, dump
# Re-bake into the qcow2 (no guestfish needed — qemu-img + mtools):
qemu-img convert -O raw OpenCore.qcow2 /tmp/oc.raw
mcopy -o -i /tmp/oc.raw@@$((2048*512)) config.plist ::/EFI/OC/config.plist
qemu-img convert -O qcow2 /tmp/oc.raw OpenCore.qcow2 && rm /tmp/oc.raw
```

Backups of the pre-AMD `config.plist`/`OpenCore.qcow2` are kept as
`~/OSX-KVM/OpenCore/*.bak-<timestamp>`.

## Backlog

Source of truth: `doc/infra-backlog.json`
Milestones: I1.1 (VM Bootstrap) → I1.2 (Toolchain) → I1.3 (Sync) → I1.4 (USB) → I1.5 (CI Scripts) → I1.6 (Hardening)

## Hard Rules for Infra Scripts

1. Every script exits non-zero on failure — no silent failures.
2. No secrets hardcoded. SSH key path is `~/.ssh/mac_vm_key` (a constant, not a secret).
3. All scripts idempotent — safe to re-run.
4. Scripts print elapsed time for any operation over 5 seconds.
5. `bash -n script.sh` must pass (valid syntax) as the baseline verification.
