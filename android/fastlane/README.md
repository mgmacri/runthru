# Android Fastlane

## Lanes
- `bundle exec fastlane beta` — signed AAB → Play Store internal track
- `bundle exec fastlane release` — promotes the internal build to production

## Required environment variables
| Variable | Purpose |
|----------|---------|
| `GOOGLE_PLAY_JSON_KEY_DATA` | Inline JSON of Play Store service account key |
| `KEYSTORE_PATH` | Path to upload keystore file |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Upload key alias |
| `KEY_PASSWORD` | Upload key password |

Signing: `android/app/build.gradle` reads `key.properties` at the project
root (not committed). CI writes it from `KEYSTORE_*` / `KEY_*` secrets before
building; without it the build falls back to debug signing.

⚠ Never commit these values. CI sources from secret manager.
