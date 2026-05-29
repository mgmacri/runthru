---
description: "Infra I1.2: Install Flutter iOS toolchain in macOS VM — Xcode CLI, CocoaPods, Flutter ^3.11.0. Runs over SSH. Produces scripts/infra/setup-toolchain.sh."
mode: agent
---

# Infra Step I1.2 — Flutter iOS Toolchain in VM

> **Milestone**: I1.2 | **Backlog**: `doc/infra-backlog.json`
> **Depends on**: I1.1 (VM running, SSH alias configured)
> **Produces**: `scripts/infra/setup-toolchain.sh`

Load shared context first: [infra-osx-kvm-context](./../instructions/infra-osx-kvm-context.instructions.md)

---

## Task

Write `scripts/infra/setup-toolchain.sh` — a script that installs the full Flutter iOS toolchain
inside the macOS VM. It runs entirely over SSH:

```bash
ssh mac-vm 'bash -s' < scripts/infra/setup-toolchain.sh
```

The script must be **idempotent** — safe to re-run. Check for each tool before installing.

### Sections of setup-toolchain.sh

**1. Xcode Command Line Tools**
```bash
xcode-select -p || xcode-select --install
# Then wait loop: until xcode-select -p; do sleep 5; done
sudo xcodebuild -license accept
```

**2. Homebrew**
```bash
command -v brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Add brew to PATH for both Intel (/usr/local) and Apple Silicon (/opt/homebrew) — VM is Intel
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/usr/local/bin/brew shellenv)"
```

**3. rbenv + Ruby (for CocoaPods/Fastlane gem isolation)**
```bash
brew install rbenv ruby-build
rbenv install 3.2.0 --skip-existing
rbenv global 3.2.0
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc
```

**4. CocoaPods + Fastlane**
```bash
gem install cocoapods fastlane --no-document
```

**5. Flutter SDK (stable, ^3.11.0)**
```bash
git clone https://github.com/flutter/flutter.git ~/flutter --depth 1 --branch stable
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
~/flutter/bin/flutter --version  # triggers dart SDK download
~/flutter/bin/flutter precache --ios
```

**6. Accept Flutter iOS licenses**
```bash
~/flutter/bin/flutter doctor --android-licenses  # skip Android
# iOS: handled by xcodebuild license accept above
```

**7. Final check**
```bash
~/flutter/bin/flutter doctor -v
```

### Expected flutter doctor output

After this script runs, `flutter doctor` must show:
- ✓ Flutter (channel stable, version 3.x.x)
- ✓ Xcode (version X.X)
- ✓ CocoaPods (version X.X.X)
- ✗ Android toolchain — skip: `flutter config --no-enable-android`

Suppress the Android warning permanently:
```bash
~/flutter/bin/flutter config --no-enable-android
```

---

## After Setup: Smoke Test

Once I1.3 (code sync) is working, run the first iOS build smoke test:

```bash
# From Linux host:
bash scripts/infra/sync.sh
ssh mac-vm 'cd ~/runthru && flutter build ios --no-codesign 2>&1 | tail -10'
```

Expected: `Build complete.` with exit 0.

Take toolchain snapshot after success:
```bash
bash scripts/infra/launch-vm.sh --stop
bash scripts/infra/snapshot.sh create toolchain
bash scripts/infra/launch-vm.sh
```

---

## Verification

```bash
bash -n scripts/infra/setup-toolchain.sh && echo SYNTAX_OK
ssh mac-vm 'bash -s' < scripts/infra/setup-toolchain.sh
ssh mac-vm 'flutter --version' | grep -E '^Flutter 3\.'
ssh mac-vm 'flutter doctor' | grep -E '✓ (Flutter|Xcode|CocoaPods)'
```
