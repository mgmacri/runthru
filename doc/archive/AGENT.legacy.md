# RunThru — Agent Operating Rules
> Drop at repo root as `AGENT.md`. Claude Code reads this alongside `CLAUDE.md`.

## Decision Protocol

Before modifying any file:
1. Read the file completely
2. Run `dart analyze` mentally against your planned change
3. Check the design token system — no magic numbers
4. Check accessibility requirements for this widget type
5. Write the change
6. Run `dart analyze --fatal-infos` after every file save
7. Run `flutter test` after any logic change

## File Ownership Rules

| Path | Rule |
|------|------|
| `lib/design/tokens.dart` | Read when writing any widget. Never add values without a design reason. |
| `lib/core/word_timer.dart` | Core engine — changes require re-running all `test/core/word_timer_*.dart` tests |
| `lib/core/context_reveal_notifier.dart` | Changes require `integration_test/context_reveal_v4_test.dart` to pass |
| `lib/features/reading/pacing/word_duration.dart` | Algorithm constants only change with NOTICE update |
| `lib/three_d/parallax_room_painter.dart` | Always inside `RepaintBoundary`. Never add non-painting logic. |
| `NOTICE` | Update whenever touching `lib/features/reading/pacing/` |
| `pubspec.yaml` | Never add a dependency without checking if existing ones already cover the need |
| `bug-backlog.json` | Update when fixing a bug: mark status `"fixed"`, add `"fixedIn"` field |

## When Tests Fail

1. Read the failing test carefully — understand what it asserts
2. Check if the test is testing the right thing
3. If your code change broke a valid test: **fix your code, not the test**
4. If the test was testing wrong behavior: add a comment explaining the old behavior before updating
5. Never delete a test to make CI pass

## When Analyze Fails

1. Never add `// ignore:` without a comment explaining exactly why the rule doesn't apply
2. Prefer fixing the underlying issue over suppressing
3. Acceptable ignores: `// ignore: avoid_print` only in `lib/core/logger.dart` itself

## Commit Hygiene (if committing)

- One logical change per commit
- Commit message format: `[area]: brief description` e.g. `[a11y]: add liveRegion to CR overlay`
- Never commit with failing tests or analyze errors

## Asking vs. Acting

Act autonomously on:
- Bug fixes where the correct behavior is clear from tests or spec
- Accessibility improvements
- Code style and quality
- Test additions

Ask the user before:
- Changing package IDs
- Removing a feature or behavior
- Adding a new dependency
- Changing the Instapaper or Google Drive OAuth flow
- Deleting any file from `lib/core/` or `lib/design/`

## Output Verbosity

- Report phase completions with a one-line status: `✅ Phase 1 complete — 3 critical, 7 major, 12 minor issues found`
- Show diffs for significant changes
- For small fixes (missing Semantics label, unused import), batch and describe: `Fixed 8 missing Semantics labels across lib/widgets/`
- Always show the final `dart analyze` and `flutter test` output verbatim
