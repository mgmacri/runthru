# Task: Add Google Play Store Release Workflow to Codemagic

## Context
Speedy Boy needs Android builds published to Google Play Store's internal testing track via Codemagic CI/CD. This workflow should trigger on pushes to the main branch and produce signed Android App Bundles (AAB).

## Prerequisites
1. **READ `digest.txt` FIRST** — May contain Android build configuration and signing details.
2. **READ `codemagic.yaml`** — Existing workflow structure must be preserved.
3. Identify Android package name and signing configuration.

## Implementation Specification

### Workflow Requirements

| Requirement | Value |
|-------------|-------|
| Workflow Name | `android-play-store` |
| Trigger | Push to `main` branch |
| Build Output | Signed AAB (Android App Bundle) |
| Distribution | Google Play Internal Testing track |
| Build Duration | Max 60 minutes |

### Workflow Definition
```yaml
workflows:
  # ... existing iOS workflows ...

  # NEW: Google Play Store workflow
  android-play-store:
    name: Android Play Store Internal
    max_build_duration: 60
    environment:
      android_signing:
        keystore_reference: GOOGLE_PLAY_KEYSTORE  # Encoded keystore
        keystore_password_reference: KEYSTORE_PASSWORD
        key_alias_reference: KEY_ALIAS
        key_password_reference: KEY_PASSWORD
      vars:
        FLUTTER_VERSION: stable
        PACKAGE_NAME: io.speedyboy.app  # Update from existing config
      groups:
        - google_play_credentials
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: main
          include: true
          source: true
      cancel_previous_builds: true
    scripts:
      - name: Get dependencies
        script: |
          flutter pub get
      - name: Build AAB
        script: |
          flutter build appbundle --release
    artifacts:
      - build/app/outputs/bundle/release/app-release.aab
      - build/app/outputs/logs/*.log
    publishing:
      google_play:
        credentials: $GOOGLE_PLAY_SERVICE_ACCOUNT_KEY
        track: internal
        submit_to_review: false
        rollout_fraction: 1.0
```

### Environment Variables Required

**Google Play Credentials Group (`google_play_credentials`):**

| Variable | Description | How to Obtain |
|----------|-------------|---------------|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` | Base64-encoded JSON service account key | Google Cloud Console → IAM → Service Accounts |
| `GOOGLE_PLAY_KEYSTORE` | Base64-encoded upload keystore file | Generated via keytool |
| `KEYSTORE_PASSWORD` | Password for keystore | Set during keystore creation |
| `KEY_ALIAS` | Key alias within keystore | Set during keystore creation |
| `KEY_PASSWORD` | Password for the key | Set during keystore creation |

### Service Account Setup

**Required Permissions:**
- Role: "Release Manager" or custom role with:
  - `androidpublisher.releases.update`
  - `androidpublisher.tracks.update`
  - `androidpublisher.uploads.commit`

**Key Generation Steps:**
```
1. Google Cloud Console → IAM & Admin → Service Accounts
2. Create service account with Release Manager role
3. Create JSON key
4. Base64 encode: base64 -i key.json -o encoded_key.txt
5. Add to Codemagic environment variables
```

### Keystore Generation (First-time setup)
```bash
keytool -genkey -v -keystore speedyboy-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias speedyboy-upload

# Base64 encode for Codemagic
base64 -i speedyboy-upload.jks -o keystore-encoded.txt
```

### Key Signing Configuration

**android/key.properties (generated at build time):**
```properties
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=../speedyboy-upload.jks
```

**android/app/build.gradle signing config:**
```gradle
android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## Output Format
Show the complete workflow addition:

```
═══════════════════════════════════════════════════════
FILE: codemagic.yaml (WORKFLOW ADDITION)
═══════════════════════════════════════════════════════
# Add this workflow to existing codemagic.yaml

android-play-store:
  name: Android Play Store Internal
  max_build_duration: 60
  environment:
    # ... [complete workflow definition]
```

If existing file has other workflows, show context:
```yaml
workflows:
  ios-testflight:
    # ... existing ...
  
  ios-production:
    # ... existing ...

  # ADD BELOW THIS LINE
  android-play-store:
    # ... new workflow ...
```

## Token Budget Constraints
- Read codemagic.yaml once to understand structure
- No need to read Android build files (assume standard Flutter structure)

## Validation Checklist
- [ ] AAB build output path is correct (`build/app/outputs/bundle/release/`)
- [ ] Signing configuration references all four keystore variables
- [ ] `track: internal` targets internal testing
- [ ] Service account key variable name matches publishing section
- [ ] Branch trigger matches `main` (verify branch name casing)
- [ ] Max build duration appropriate for Flutter Android builds
- [ ] Artifacts include both AAB and build logs
