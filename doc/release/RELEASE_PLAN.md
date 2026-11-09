# RunThru — Release Plan (v2.0 public)

Updated 2026-11-09. Owner: Matt. Executed by the agent swarm (`SWARM.md`).

## Goal

Ship RunThru 2.0 to Play Store production and the App Store as fast as
possible with a **smaller, working** feature set. Everything that is broken
and not on the critical path gets hidden or removed, not fixed.

## Where we are

- Analyzer clean, suite green on 2026-06-11 (984 tests). Re-run the gate
  before trusting this; the working tree has ~190 uncommitted files from the
  data-layer overhaul.
- Pipelines exist: Codemagic (`codemagic.yaml`) builds TestFlight + Play
  internal on push to `main`; Fastlane `:beta` / `:release` lanes in
  `android/` and `ios/`; GitHub Actions runs analyze + test.
- Privacy policy exists (`doc/legal/privacy_policy.md`) but has a contact
  placeholder and no hosted URL.
- AI integration: only plumbing (`EdgeAiQueue` + `NoopModelProcessor`). No model, no UI.
- Several features are broken on device (to be enumerated in `TRIAGE.md`
  during the Step 1 device pass).

## Scope decisions (cherry-picked for impact)

| Decision | Why |
|----------|-----|
| **Ship free. Remove the premium gate and the purchase stub.** | P-4 stub grants premium unconditionally and would fail store review. Real IAP is weeks of work. Monetisation returns in 2.1. |
| **Remove the Discover / OPDS "Free Bookstore" tab.** | Planned M1.6 removal. Less surface, fewer third-party failure modes. |
| **Google Drive ships only if the OAuth dart-defines are wired in Codemagic and the iOS URL scheme is set; otherwise hide the source.** | Code is done and tested but non-functional without runtime config. A visible broken source is worse than no source. |
| **Sentence mode: hide it if it cannot be aligned with the design reference in one lane-day.** | Paragraph and Full Page are rebuilt; Sentence is not. |
| **AI integration does not block release.** | Plumbing is safe to ship dormant. See `AI_INTEGRATION.md`. |
| **Drop the Android `CAMERA` permission.** | Head tracking uses gyro only; the permission invites Play review questions. |
| **Keep `/read-legacy`.** | Deep-link fallback, zero user-facing cost. |
| **P-8 (range picker duplicate word) is deferred.** | Edge case, documented TODO. |

## Critical path

Steps are ordered. Steps 2–5 run as parallel swarm lanes.

### 0. Freeze the baseline (human, 30 min)
- Run `scripts/verify_release_readiness.sh`. Fix nothing yet; record result.
- Commit the uncommitted working tree as `chore: data-layer overhaul + docs retool baseline`.
- Tag `v2.0.0-baseline`.

### 1. Device triage pass (human + `a11y-auditor`, half a day)
- Clean install on one Android and one iOS device.
- Walk every route: onboarding → library → each source → reading (RSVP,
  Paragraph, Full Page, Sentence) → ContextReveal → settings → analytics.
- Each failure becomes a `B-xx` row in `TRIAGE.md` with severity and repro.
- Severity rule: **P0** crashes or blocks reading. **P1** a feature is
  visibly wrong. **P2** polish. Only P0 and P1 are on the release path.

### 2. Scope cuts (lane `cuts`)
- R-01 remove premium gate + `PurchaseService`, delete related settings UI and tests.
- R-02 remove Discover/OPDS tab, `opds_service.dart`, routes, tests.
- R-03 remove `CAMERA` permission from the Android manifest.
- R-04 hide Google Drive source unless `GOOGLE_*_CLIENT_ID` dart-defines are non-empty at runtime.

### 3. Fix P0/P1 broken features (lane `fix`, one agent per row)
- `B-xx` rows from Step 1. Each row names its files; agents do not leave them.

### 4. Reading-screen polish that is already half done (lane `reading`)
- R-05 Sentence mode: align to design reference or hide the mode switch entry.
- R-06 Confirm 60 fps word flash with `lib/debug/fps_probe.dart` on a low-end device.

### 5. Store readiness (lane `store`)
- R-07 Privacy policy: real contact address, host it (GitHub Pages is fine), put the URL in both store consoles.
- R-08 Store listing: short + full description, 5 screenshots per platform from `screenshots/`, feature graphic.
- R-09 Version `2.0.0+16` (or next), Codemagic build number check, release notes.
- R-10 Codemagic env groups verified: `instapaper_credentials`, `google_signin_credentials`, `google_play_credentials`.

### 6. Release candidate gate (human)
- Gate script green on `main`.
- TalkBack + VoiceOver pass on library and reading screens.
- Internal track + TestFlight build installed on both devices, smoke-tested for 15 minutes each.
- Promote: `bundle exec fastlane release` in `android/` and `ios/`.

## Definition of done (release candidate)

- Every `TRIAGE.md` row is `done` or `deferred` with a one-line reason.
- `scripts/verify_release_readiness.sh` exits 0 on `main`.
- No route reachable from the UI shows a stub, placeholder, or "coming soon".
- Privacy policy URL live and linked from settings.
- Store listings complete in both consoles.
- Build installed from the internal track / TestFlight, not from `flutter run`.

## After release (2.1 backlog, not now)

- Real IAP (StoreKit 2 / Play Billing) with server-side receipt validation.
- AI section summaries and difficulty hints (`AI_INTEGRATION.md`).
- P-8 range picker positional selection.
- Remove `/read-legacy` after one release of field data.
