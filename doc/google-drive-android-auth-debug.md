# Google Drive Android Auth Debugging

Use this checklist when Android Google Drive sign-in or Drive authorization does
not complete cleanly.

## Reset State

Clear local RunThru app state:

```bash
adb shell pm clear com.runthru.app
```

If Google Play Services or the account chooser appears stale during debugging,
reset the emulator account/session state through Android Settings or recreate
the emulator.

## Verify Configuration

Android Drive auth uses `google_sign_in` and Google Identity authorization. It
does not use a custom URI OAuth redirect for Drive access.

When a selected Drive picker adapter is available in the build, RunThru uses
`https://www.googleapis.com/auth/drive.file` for the default selected-file path.
Users choose one or more Drive files explicitly through that Drive-aware picker,
and RunThru imports only those selected Drive file IDs. This selected-file path
is the recommended default for business/Workspace trust.

If the build does not include a native Drive picker adapter, RunThru shows that
the Google Drive file picker is not available yet. It does not label the OS file
picker as Google Drive import, and local OS file import remains separate from
Google Drive OAuth.

The optional full Drive browser uses
`https://www.googleapis.com/auth/drive.readonly`, requires the user to enable
"Use full Drive browser", and may be blocked by Workspace admins. It may also
require additional Google OAuth verification/compliance before broad public
release. Full Drive browser access is not required for selected-file import
when the picker adapter is available.

Do not debug Drive scope behavior by inferring account type from email domains
or by calling tokeninfo to inspect `hd`; scope selection is based only on the
explicit local access-mode preference.

Run the app with a Web OAuth client ID as the Android `serverClientId`:

```bash
./scripts/run_runthru_android.sh
```

The required Dart define is:

```text
GOOGLE_WEB_CLIENT_ID=<web-oauth-client-id>.apps.googleusercontent.com
```

If the Android app is configured through `google-services.json`, set
`GOOGLE_ANDROID_USES_GOOGLE_SERVICES_JSON=true` and ensure the file contains the
web client configuration. In either case, Google Cloud Console must also contain
the Android package/SHA configuration for `com.runthru.app`.

## Capture Safe Logs

Clear logs, reproduce the connect flow, then collect only relevant RunThru
lines:

```bash
adb logcat -c
./scripts/run_runthru_android.sh
adb logcat -d | grep -Ei "google-drive-auth|runthru|GoogleSignIn|Identity"
```

Useful safe RunThru log events include:

```text
config GOOGLE_WEB_CLIENT_ID=present
config GOOGLE_WEB_CLIENT_ID=missing
event=oauth_config_invalid
reason=web_client_id_missing
reason=web_client_id_placeholder
operation=drive_auth_headers
```

## Safe To Share

- Config presence/absence.
- Failure reason names such as `web_client_id_missing`.
- Platform and operation names.

## Never Share

- Raw OAuth client IDs.
- Access tokens.
- Refresh tokens.
- ID tokens.
- Authorization codes.
- `Authorization` headers.
- Raw platform exception messages or details if they contain OAuth payloads.
- Personal Google account email addresses unless intentionally shown in UI.
