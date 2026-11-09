# RunThru Dev Environment: Android Studio → Waydroid Migration Guide

> Tailored to: EndeavourOS (Arch-based), Wayland/Hyprland, Ryzen 5 3600,
> NVIDIA RTX 2060 (`nvidia-open-dkms` 595.71), Waydroid 1.6.2 (already
> installed + initialized, GAPPS image).
> Preferences: keep GAPPS + sideload only, run **alongside** AVDs,
> prioritize ADB debugging / networking / GPU acceleration
> (camera/sensors/GPS not needed).

**Key fact:** Waydroid is already installed, initialized, and on the GAPPS
image; binder works (Rust binder + binderfs is mounted). This guide is about
*configuring it for dev, wiring it to Android Studio, and surviving the NVIDIA
graphics path* — not a from-scratch install.

---

## 0. What Waydroid is and isn't

Waydroid is **not an emulator** — it's a **container** running full Android
(LineageOS) userspace on your host kernel via the Android `binder` driver + LXC.

- Runs Android **x86_64 natively** — fast, low overhead, instant boot. Main win.
- Runs **one Android version at a time** (current image only). You **cannot**
  spin up API 26/30/34 side-by-side like AVDs. Main loss.
- Shares the **host kernel** — no guest kernel, no snapshots, no per-device
  hardware profiles.

**Replaces well:** day-to-day run/deploy/debug over ADB, networking, fast
iteration. **Can't replace:** multi-API testing, sensor/GPS/camera simulation,
emulator snapshots, telephony, Play Integrity/SafetyNet flows. Keep AVDs for
those.

---

## 1. Emulator vs. Waydroid

| Dimension | Android Studio Emulator (AVD) | Waydroid |
|---|---|---|
| Architecture | Full system VM (QEMU/KVM) | LXC container on host kernel |
| Boot speed | Slow cold boot; snapshot resume | Near-instant once container up |
| Resource cost | Heavy (separate kernel + GPU emu) | Light (shared kernel) |
| Multi-API testing | ✅ Any API 21→latest, side by side | ❌ One image/version at a time |
| Snapshots | ✅ Save/restore device state | ❌ None (re-init = wipe) |
| Sensors/GPS/camera | ✅ Rich emulation + virtual scene | ⚠️ Minimal/none |
| Telephony/SMS | ✅ Simulated | ❌ |
| GPU accel | ✅ Mature | ⚠️ Works, but fragile on **NVIDIA** |
| Play Integrity / SafetyNet | ⚠️ Fails | ❌ Fails (uncertified) |
| ADB / logcat / breakpoints | ✅ | ✅ (over TCP) |
| Display server | Independent window | Needs **Wayland** (Hyprland ✅) |
| Disk footprint | Per-AVD (GBs each) | Single image set (~1.5–2 GB) |

Hyprland (wlroots) is one of the best-supported Waydroid environments. The
NVIDIA GPU is the one liability.

---

## 2. Kernel modules / dependencies — verification

Re-verify after any kernel update (the #1 silent breakage on rolling distros):

```bash
mount | grep binder    # expect: binder on /dev/binderfs type binder ...
ls /dev/binderfs       # expect: anbox-binder anbox-hwbinder anbox-vndbinder binder-control
```

If `binderfs` is gone after a kernel upgrade:
- **Mainline-binder kernels** (this box, `vendor_type = MAINLINE`): binderfs comes
  from the kernel. If missing, the new kernel dropped binder support → keep a
  kernel that has it. Verify: `zcat /proc/config.gz | grep BINDER`.
- **anbox-modules path** (older): `binder_linux` + `ashmem_linux` DKMS modules.
  Not needed here — kernel provides binder natively.

> ⚠️ EndeavourOS/Arch: every `linux` bump can change binder availability.
> If Waydroid won't start after an update, **check binderfs first**.

---

## 3. Start / stop / reset / update

Two layers: a root **container service** (systemd) + a per-user **session**.

```bash
# Start backend (root); enable to auto-start on boot:
sudo systemctl start waydroid-container
sudo systemctl enable --now waydroid-container

# Start Android session + UI:
waydroid session start        # boots Android in background
waydroid show-full-ui         # full Android desktop in a Wayland window

# State + container IP (needed for ADB):
waydroid status               # Session: RUNNING, IP Address: 192.168.250.x

# Stop:
waydroid session stop                     # stop Android, keep container
sudo systemctl stop waydroid-container    # stop backend entirely

# Update system + vendor images (OTA from waydro.id):
sudo waydroid upgrade         # keeps GAPPS per waydroid.cfg

# Reset / re-provision (DESTROYS Android data, like wiping an AVD):
sudo waydroid init -f         # add -s VANILLA to switch off GAPPS
```

`waydroid upgrade` respects channels in `waydroid.cfg`
(`system_ota = .../GAPPS.json`) — upgrades stay on GAPPS. Don't hand-edit that
file unless switching image type.

---

## 4. Connect Android Studio via ADB

No USB — `adbd` is exposed over TCP on the container IP, port 5555.

```bash
# 1. Session running + grab IP:
waydroid status                       # note IP, e.g. 192.168.250.112

# 2. Use the SAME adb Android Studio uses (avoid server/version splits):
~/Android/Sdk/platform-tools/adb kill-server
~/Android/Sdk/platform-tools/adb connect 192.168.250.112:5555

# 3. Verify:
~/Android/Sdk/platform-tools/adb devices   # expect: 192.168.250.112:5555  device
```

> Android Studio talks to one adb *server*. A different `adb` binary can start a
> second server and not see the device. Put `~/Android/Sdk/platform-tools` first
> on `PATH` to fix permanently.

**Deploy target:** once `adb connect` succeeds, Android Studio auto-discovers the
device in its dropdown. Flutter: `flutter devices` lists it;
`flutter run -d 192.168.250.112:5555` deploys. No plugin needed.

Convenience alias (`~/.bashrc`):
```bash
alias wadb='adb connect $(waydroid status | awk "/IP/{print \$3}"):5555'
```

> `auto_adb = False` in `waydroid.cfg` just means Waydroid won't auto-connect.
> Set `auto_adb = True` to connect automatically on session start.

---

## 5. Install APKs manually

```bash
# A. Waydroid installer:
waydroid app install /path/to/app-release.apk

# B. Standard adb (what Studio/Flutter use):
adb -s 192.168.250.112:5555 install -r build/app/outputs/flutter-apk/app-debug.apk

# C. List / launch / remove:
waydroid app list
waydroid app launch com.runthru.app
adb -s 192.168.250.112:5555 uninstall com.runthru.app
```

For RunThru debug builds just use `flutter run` — it installs + attaches.

---

## 6. Debugging: logcat, breakpoints, Studio

- **Logcat:** `adb -s <ip>:5555 logcat`, Studio's Logcat panel, or `waydroid logcat`.
- **Breakpoints:** full JDWP over network adb. Studio: select Waydroid device →
  **Debug**. Breakpoints/inspection work normally.
- **Flutter hot reload:** works — Waydroid is a normal device to the Flutter tool.

Gotcha: if the container reboots or IP changes, JDWP drops. Re-`adb connect`
(or `wadb`) and reselect the device.

---

## 7. Networking host ↔ Waydroid

NAT bridge `waydroid0` on host (gateway `192.168.250.1`); container is
`192.168.250.112`.

```bash
waydroid shell ping -c2 1.1.1.1     # internet check

# DNS fails but ping-by-IP works:
waydroid shell
  setprop net.dns1 1.1.1.1
```

No connectivity at all (common Arch causes):
1. **IP forwarding off:** `sudo sysctl net.ipv4.ip_forward=1` (persist in `/etc/sysctl.d/`).
2. **Host firewall** (firewalld/ufw/nftables) blocking `waydroid0` — allow forwarding.
3. **`waydroid-net` not running** — started by the container service.

**Host → app server:** from Android, reach the host at gateway `192.168.250.1`
(NOT `10.0.2.2` — that's the *emulator's* magic IP, not Waydroid). A backend on
host `:8080` is `http://192.168.250.1:8080`.

---

## 8. GAPPS — keep + sideload only

Already on GAPPS; sideloading your own app needs nothing further.

Caveat: a fresh GAPPS Waydroid is **uncertified** → Play Store shows "not Play
Protect certified" and Google sign-in may be refused. Irrelevant for sideload.
If you ever need Play sign-in:

```bash
sudo waydroid shell
  ANDROID_RUNTIME_ROOT=/apex/com.android.runtime \
  sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
  "select * from main where name = 'android_id';"
# Register that ID at https://www.google.com/android/uncertified, wait ~10–20 min, reboot session.
```

**Hard limits regardless of certification:**
- **Play Integrity / SafetyNet fail** (all levels). Billing attestation, Widevine
  L1, DRM → must test on a real device.
- FCM/push reliable only with certified signed-in GAPPS; sideload-only may be flaky.

---

## 9. NVIDIA RTX 2060 graphics — highest-risk area

Most common failure: **black screen** on NVIDIA + Wayland. `nvidia-open-dkms`
595.71 has solid GBM/Wayland support, so HW rendering may work — but keep the
fallback ready.

**Try HW GPU first:** `waydroid session start && waydroid show-full-ui`.
Normal render = done, you have HW accel.

**Black screen / hang at boot logo → force SwiftShader (software):**
```bash
sudo nano /var/lib/waydroid/waydroid_base.prop
```
Add:
```
ro.hardware.gralloc=default
ro.hardware.egl=swiftshader
```
Restart:
```bash
waydroid session stop && sudo systemctl restart waydroid-container && waydroid session start
```
Tradeoff: CPU rendering, no GPU accel, but reliable. Ryzen 3600 handles
RunThru's UI fine in software; only felt in GPU-heavy games. Recommendation: try
HW first, keep SwiftShader as a one-edit fallback.

Other knobs if it renders but tears/wrong colors:
- `cat /sys/module/nvidia_drm/parameters/modeset` should be `Y`; else add
  `nvidia_drm.modeset=1` to kernel cmdline (likely already set for Hyprland).
- Multi-window mode (each app its own Wayland window; sometimes more stable):
  ```bash
  waydroid prop set persist.waydroid.multi_windows true
  # restart session; launch apps directly instead of show-full-ui
  ```

---

## 10. Troubleshooting

**Won't start**
- `sudo systemctl status waydroid-container`
- `mount | grep binder` (prime suspect after a kernel update — §2)
- `dmesg | grep -i binder`
- `waydroid log` + `sudo journalctl -u waydroid-container -b`

**ADB doesn't detect it**
- `waydroid status` must say RUNNING with an IP.
- Wrong adb → `adb kill-server`, reconnect with the SDK's adb.
- IP changed after restart → reconnect (`wadb`).

**Studio doesn't show device**
- `adb devices` must list it first.
- adb version skew → kill-server, ensure one adb on PATH.

**Black screen / graphics** → §9. Confirm you ran `show-full-ui` *after* boot
completed (`waydroid status` = RUNNING).

**Permissions**
- Container service needs root; session runs as your user — don't sudo the session.
- `/dev/binderfs` perms off after a kernel change → restart container service.

**Clipboard / file sharing**
- Host↔Android clipboard is not seamless (partial on wlroots). For files use
  `adb push localfile /sdcard/` / `adb pull /sdcard/file .`. No drag-and-drop.

**ARM translation on x86**
- Standard image is x86_64 with **no ARM translation** by default. ARM-only
  native libs crash. RunThru builds for the device ABI via Flutter → x86_64
  automatically, no issue. Avoid running ARM-only third-party APKs.

**SELinux / AppArmor / containers**
- EndeavourOS ships neither by default — unlikely here. If AppArmor was added,
  it can block LXC/binder: `sudo dmesg | grep -i apparmor`, add exception or set
  complain mode.
- Docker/Podman nftables policies can clobber `waydroid0` routing — if
  networking dies after starting Docker, re-apply forwarding + restart
  `waydroid-container`.

---

## A. Minimal path — fast loop
```bash
sudo systemctl start waydroid-container
waydroid session start
waydroid show-full-ui                       # black screen → §9 SwiftShader, restart
waydroid status                             # note IP
~/Android/Sdk/platform-tools/adb connect 192.168.250.112:5555
adb devices                                 # Studio now shows it
flutter run -d 192.168.250.112:5555         # deploy RunThru
```

## B. Production-quality path — daily driver
1. `sudo systemctl enable --now waydroid-container` (auto-start backend).
2. `auto_adb = True` in `/var/lib/waydroid/waydroid.cfg` (auto-reconnect).
3. `~/Android/Sdk/platform-tools` first on `PATH` (one shared adb).
4. `wadb` alias (§4) for one-command reconnect.
5. Decide graphics mode once: test HW; if unstable, commit SwiftShader (§9).
6. `persist.waydroid.multi_windows true` for best Hyprland ergonomics.
7. Keep AVDs for the gaps: one per critical API level + one with sensors/GPS;
   Waydroid for the 90% inner loop, AVD for matrix/sensor/Play-Integrity tests.
8. Persist IP forwarding:
   `echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-waydroid.conf`.
9. Test Waydroid after each `linux` kernel bump before relying on it.

## C. Troubleshooting checklist (top to bottom)
1. `waydroid status` → RUNNING with IP? else → 2.
2. `sudo systemctl status waydroid-container` → active? else start / check journal.
3. `mount | grep binder` → binderfs mounted? else kernel/binder problem (§2).
4. Black screen? → SwiftShader fallback (§9).
5. `adb devices` empty? → kill-server, reconnect with SDK's adb.
6. Studio missing device? → confirm `adb devices` first; fix adb version skew.
7. No internet? → `ip_forward=1`, firewall on `waydroid0`, `waydroid-net` running.
8. App crashes on launch? → check ABI (ARM-only lib on x86, §10) via `adb logcat`.
9. Still stuck? → `waydroid log` + `journalctl -u waydroid-container -b`.

## D. Rollback to the official emulator
Running alongside, so AVDs are untouched:
```bash
waydroid session stop
sudo systemctl disable --now waydroid-container   # stop auto-start

emulator -list-avds
emulator -avd <your_avd_name>                     # or pick it in Studio's dropdown
```
Full removal + disk reclaim:
```bash
sudo systemctl disable --now waydroid-container
sudo waydroid session stop 2>/dev/null
sudo pacman -R waydroid
sudo rm -rf /var/lib/waydroid ~/.local/share/waydroid   # images (~2GB) + user data
```
None of this touches AVDs, the SDK, or Android Studio config.

---

## Caveats
Command details (`waydroid upgrade` flags, prop names, default IP) are stable
across recent 1.x but can shift — verify with `waydroid --help` / `man waydroid`
on 1.6.2. The shipped Android version changes over time:
`waydroid shell getprop ro.build.version.release` for your API level. The NVIDIA
HW-accel outcome (§9) is genuinely uncertain on this driver — it must be tested.
