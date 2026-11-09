# iOS Fastlane

## Lanes
- `bundle exec fastlane beta` — archive → TestFlight
- `bundle exec fastlane release` — archive → App Store

## Required environment variables
| Variable | Purpose |
|----------|---------|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from App Store Connect |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64-encoded .p8 content |
| `MATCH_PASSWORD` | Fastlane match encryption password (if used) |

Optional (Appfile overrides):
| Variable | Purpose |
|----------|---------|
| `APP_IDENTIFIER` | Bundle ID override (defaults to `com.mgmacri.runthru`) |
| `APPLE_ID` | Apple ID email for fallback auth |
| `ITC_TEAM_ID` / `TEAM_ID` | App Store Connect / Developer Portal team IDs |

⚠ Never commit these values. CI sources from secret manager. The `.p8` key
file itself must never be added to the repository.
