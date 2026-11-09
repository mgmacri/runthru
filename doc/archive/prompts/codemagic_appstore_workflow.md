# Task: Update Codemagic Workflow for App Store Production Release

## Context
The existing `codemagic.yaml` has an `ios-testflight` workflow triggered on main branch. A new production workflow is needed that builds and submits to the App Store for review, triggered on release branches.

## Prerequisites
1. **READ `digest.txt` FIRST** — May contain build configuration context and environment setup.
2. **READ `codemagic.yaml`** — Existing workflow structure must be preserved.
3. Identify current iOS build configuration (bundle ID, signing, schemes).

## Implementation Specification

### Workflow Requirements

| Requirement | Value |
|-------------|-------|
| Workflow Name | `ios-production` |
| Trigger Branch Pattern | `release/*` |
| Build Type | Release IPA |
| Distribution | App Store review submission |
| Existing Workflow | `ios-testflight` unchanged |

### Workflow Definition
```yaml
workflows:
  # Existing testflight workflow - DO NOT MODIFY
  ios-testflight:
    name: iOS TestFlight
    # ... existing configuration preserved ...

  # NEW: Production App Store workflow
  ios-production:
    name: iOS App Store Production
    max_build_duration: 60
    environment:
      ios_signing:
        distribution_type: app_store
        bundle_identifier: io.speedyboy.app  # Update from existing config
      vars:
        FLUTTER_VERSION: stable
      groups:
        - ios_credentials  # Contains APPLE_APP_SPECIFIC_PASSWORD, etc.
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: release/*
          include: true
          source: false
      cancel_previous_builds: true
    scripts:
      - name: Get dependencies
        script: |
          flutter pub get
      - name: Build iOS release
        script: |
          flutter build ios --release --no-codesign
      - name: Build IPA
        script: |
          xcodebuild -workspace ios/Runner.xcworkspace \
            -scheme Runner \
            -sdk iphoneos \
            -configuration Release \
            -archivePath build/Runner.xcarchive \
            archive
          xcodebuild -exportArchive \
            -archivePath build/Runner.xcarchive \
            -exportOptionsPlist ios/ExportOptions.plist \
            -exportPath build/ipa
    artifacts:
      - build/ipa/*.ipa
      - /tmp/xcodebuild_logs/*.log
    publishing:
      app_store_connect:
        api_key: $APP_STORE_CONNECT_API_KEY  # From environment group
        key_id: $APP_STORE_CONNECT_KEY_ID
        issuer_id: $APP_STORE_CONNECT_ISSUER_ID
        submit_to_app_store: true
        submit_to_testflight: false
        beta_groups: []  # Not needed for production
```

### Key Configuration Details

**ExportOptions.plist Requirements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

**Environment Variables (from group):**
| Variable | Description |
|----------|-------------|
| `APP_STORE_CONNECT_API_KEY` | Base64-encoded P8 key |
| `APP_STORE_CONNECT_KEY_ID` | Key identifier from App Store Connect |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from App Store Connect |

## Output Format
Show the complete updated `codemagic.yaml`:

```
═══════════════════════════════════════════════════════
FILE: codemagic.yaml
═══════════════════════════════════════════════════════
[complete file content with both workflows]
```

## Token Budget Constraints
- Read existing codemagic.yaml once
- Preserve all existing configuration exactly
- Only append new workflow section

## Validation Checklist
- [ ] Existing `ios-testflight` workflow unchanged
- [ ] New `ios-production` workflow has correct trigger pattern
- [ ] `submit_to_app_store: true` is set
- [ ] `submit_to_testflight: false` for production workflow
- [ ] Signing distribution_type is `app_store`
- [ ] Artifacts path captures IPA output
- [ ] Environment group references match existing credentials setup
- [ ] Branch pattern `release/*` correctly matches release branches
