# RunThru — Project Constitution (release mode)

RunThru is an accessibility-first RSVP reading app for neurodivergent readers
(ADHD, dyslexia, ASD, low vision). Flutter, Android + iOS. The repo folder is
historically named `speedy-boyv3`; **the product, package, and every doc say
RunThru.** Never reintroduce "Speedy Boy".

**We are in release mode.** Read `doc/release/RELEASE_PLAN.md` first, then
claim work from `doc/release/TRIAGE.md`. Nothing ships that is not on that
board. No new features, no speculative refactors, no dependency additions.

## Where things are

| Need | File |
|------|------|
| Release critical path, scope cuts, definition of done | `doc/release/RELEASE_PLAN.md` |
| Live work board (claim rows here) | `doc/release/TRIAGE.md` |
| Swarm protocol, lanes, file ownership | `doc/release/SWARM.md` |
| AI integration lane (non-blocking) | `doc/release/AI_INTEGRATION.md` |
| Data layer design | `doc/architecture/data_layer.md` |
| Privacy policy (store requirement) | `doc/legal/privacy_policy.md` |
| Release gate script | `scripts/verify_release_readiness.sh` |
| Subagent definitions | `.claude/agents/` |
| Container | `.devcontainer/` |
| Dated audits, old prompts, old specs | `doc/archive/` (history only, not instructions) |

## Toolchain

- Flutter 3.41.2 stable / Dart 3.11. The devcontainer pins this.
- On the maintainer's Arch host the system Flutter is broken; use
  `~/.flutter-sdk/bin/flutter`. The gate script picks it up automatically.
- Riverpod code-gen: after editing any `@riverpod` provider run
  `dart run build_runner build --delete-conflicting-outputs` and commit the
  `.g.dart`. Never hand-edit generated files.

## Package identity (never changes)

| Platform | ID |
|----------|----|
| Android | `com.runthru.app` |
| iOS | `com.mgmacri.runthru` (Share Extension `.ShareExtension`, App Group `group.com.mgmacri.runthru`) |

## Absolute rules

1. `dart analyze --fatal-infos` → 0 issues, always.
2. `flutter test` → all pass, always. Never delete or weaken a test to get green.
3. No credentials in source or tracked config. Secrets only via
   `String.fromEnvironment` (dart-define) or CI env vars.
   Keys: `INSTAPAPER_CONSUMER_KEY`, `INSTAPAPER_CONSUMER_SECRET`,
   `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`.
4. No `print()` / `debugPrint()`. Use `appLog(tag, message)` from
   `lib/core/logger.dart`. Never log document text, clipboard text, or tokens.
5. No hardcoded design values. Import from `lib/design/`.
6. Every interactive widget has a `Semantics` label; tap targets ≥ 48dp.
7. Every live content region is `Semantics(liveRegion: true)`.
8. Every animation checks `isReducedMotion(context)` with a `Duration.zero` branch.
9. `RepaintBoundary` around `ParallaxRoomPainter` and `CubeViewportPainter`.
10. RSVP word flash ≥ 60 fps. Only the word widget rebuilds per tick.

## Data-layer rules (see `doc/architecture/data_layer.md`)

11. Content hash (`BookIdentity`, sha256 of bytes) is identity. Never dedupe by name or path.
12. Ring 1 is sealed: `WordTimer` and pacing never touch files, network, JSON, or models.
    Text reaches the reader only through Ring 2 `ContentStore`.
13. No document text in `PreprocessingQueue` state. Reading screens call `releaseDocument()` on dispose.
14. One cache budget: all caches consult `ContentCachePolicy`.
15. Integrations follow the Ring 3 queue shape (`InstapaperSyncQueue` is the reference).
    `EdgeAiQueue` is the AI entry point; AI only *annotates* sections, never feeds the timer.
16. Extraction is chunked and durable (25-page commits); page counts come from the manifest.
17. Reading is the host: no extraction while `WordTimer.isPlaying`.
18. Bookmarks and progress live in `BookmarkStore` / `ReadingProgress`, keyed by content hash.
19. Migrations are idempotent with rollback; legacy data is copied, never deleted.

## Reading engine invariants

- ContextReveal v4 has two tiers only: `none`, `sentence`. Do not add tiers.
  Swipe up → sentence view + pause. Swipe down → dismiss + resume from leftmost visible word.
- `WordTimer.play()` after `pause()` auto-rewinds 3 words (clamp 0).
  `resumeFromContextReveal()` does **not** rewind.
- Per-word pacing (`lib/features/reading/pacing/word_duration.dart`) derives from
  RSVP Nano (MIT). Changing constants requires updating `NOTICE` and the pacing tests.
- Default reading font is AtkinsonHyperlegible. Shell font is HankenGrotesk.

## Working rules for agents

- **One TRIAGE row per task.** Set the row to `in-progress` with your agent
  name before editing; set it to `done` with the commit hash after.
- **Stay in your lane.** `doc/release/SWARM.md` maps lanes to file sets.
  Touching another lane's files requires a note on the board, not a silent edit.
- **Gate before done.** Run `scripts/verify_release_readiness.sh`. Paste its
  last lines in your report. A red gate is a blocked row, not a done row.
- **Commit format:** `[R-07] short description` using the row ID. One row per commit.
  Never push, never force, never rewrite history.
- **Ask (stop and report) before:** adding a dependency, changing package IDs,
  changing OAuth flows, deleting from `lib/core/` or `lib/design/`, editing `NOTICE`.
- **Act without asking on:** bug fixes with a clear expected behaviour, a11y
  fixes, test additions, dead-code removal inside your lane.
- Report in plain prose: what was broken, what changed, how it was verified.
