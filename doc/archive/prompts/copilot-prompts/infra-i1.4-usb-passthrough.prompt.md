---
description: "Infra I1.4: udev rules + QEMU USB host passthrough so iPhone appears in macOS VM. Produces scripts/infra/setup-usb-passthrough.sh and updates launch-vm.sh."
mode: agent
---

# Infra Step I1.4 — USB iPhone Passthrough

> **Milestone**: I1.4 | **Backlog**: `doc/infra-backlog.json`
> **Depends on**: I1.1 (launch-vm.sh exists)
> **Produces**: `scripts/infra/setup-usb-passthrough.sh`, updates `launch-vm.sh`

Load shared context first: [infra-osx-kvm-context](./../instructions/infra-osx-kvm-context.instructions.md)

---

## Background

QEMU can pass a physical USB device from the Linux host directly into the VM using
`-device usb-host,vendorid=0x05ac,productid=<id>`. Apple USB devices always use vendor
`0x05ac`. The product ID varies by iPhone model.

The VM must be **started** with the iPhone already plugged in — QEMU attaches the device at
launch, not dynamically. If the phone is disconnected, restart the VM with `--usb-passthrough`
to re-attach.

---

## Task

### TI1.4.1.1 — scripts/infra/setup-usb-passthrough.sh

Write a one-time setup script (run as root or with sudo):

```bash
#!/usr/bin/env bash
# Grants QEMU (running as current user) access to Apple USB devices.
# Must be run once; idempotent.

RULE_FILE="/etc/udev/rules.d/99-qemu-apple-usb.rules"
RULE='SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", GROUP="kvm", MODE="0664"'

if grep -qF "$RULE" "$RULE_FILE" 2>/dev/null; then
  echo "udev rule already installed."
else
  echo "$RULE" | sudo tee "$RULE_FILE"
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  echo "udev rule installed and reloaded."
fi

# Verify current user is in kvm group
if groups | grep -q kvm; then
  echo "User $(whoami) is in kvm group — OK"
else
  echo "WARNING: $(whoami) is not in the kvm group."
  echo "Run: sudo usermod -aG kvm $(whoami)"
  echo "Then log out and back in."
fi
```

### TI1.4.2.1 — Update scripts/infra/launch-vm.sh `--usb-passthrough` flag

The `--usb-passthrough` section of `launch-vm.sh` should:

1. Run `lsusb` and grep for `05ac` (Apple vendor):
   ```bash
   IPHONE_LINE=$(lsusb | grep '05ac' | head -1)
   if [[ -z "$IPHONE_LINE" ]]; then
     echo "WARNING: No Apple USB device detected. Starting VM without passthrough."
   else
     # Parse: Bus 001 Device 005: ID 05ac:12a8 Apple, Inc. iPhone
     PRODUCT_ID=$(echo "$IPHONE_LINE" | grep -oP '05ac:\K[0-9a-f]+')
     USB_FLAGS="-device usb-ehci,id=ehci -device usb-host,vendorid=0x05ac,productid=0x${PRODUCT_ID}"
     echo "Passing through iPhone (product 0x${PRODUCT_ID}) to VM"
   fi
   ```

2. Add `-device usb-ehci,id=ehci` to the base QEMU flags regardless (USB controller needed)

3. Include USB flags in the QEMU command when `--usb-passthrough` is set

---

## Post-Setup: Trust Verification

After first launching VM with `--usb-passthrough` and iPhone connected:

1. iPhone shows "Trust This Computer?" → tap Trust
2. On Linux host verify: `ssh mac-vm 'system_profiler SPUSBDataType 2>/dev/null | grep -A2 iPhone'`
3. Should show iPhone model and serial
4. Then: `ssh mac-vm 'flutter devices'` should list the iPhone as an iOS device

Document these steps in `FIRST-BOOT.md` (append a "USB Device Testing" section).

---

## Verification

```bash
bash scripts/infra/setup-usb-passthrough.sh
cat /etc/udev/rules.d/99-qemu-apple-usb.rules | grep -q '05ac' && echo RULE_OK

# With iPhone connected and VM started with --usb-passthrough:
ssh mac-vm 'system_profiler SPUSBDataType 2>/dev/null | grep -i iphone' | grep -qi iphone && echo IPHONE_VISIBLE
ssh mac-vm 'flutter devices' | grep -i ios && echo DEVICE_LISTED
```
