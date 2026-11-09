# RunThru — Agent Swarm Protocol

How several Claude Code agents work on the release at once without
colliding. Applies to subagents launched from a session, to headless
`claude -p` runs started by `scripts/swarm.sh`, and to humans.

## The loop

1. **Claim.** Open `doc/release/TRIAGE.md`, pick a `todo` row in your lane,
   set `Status` to `in-progress` and `Owner` to your agent name. Commit that
   one-line change first: `[R-02] claim`.
2. **Isolate.** Work on branch `swarm/<ID>` in your own worktree
   (`scripts/swarm.sh` does this; manually: `git worktree add ../runthru-wt/<ID> -b swarm/<ID>`).
3. **Read before writing.** Read every file in the row's `Files` column in full.
4. **Change.** Stay inside the row's files. If you must touch another lane's
   file, add a sub-bullet under your row naming the file and why.
5. **Gate.** `scripts/verify_release_readiness.sh` must exit 0.
6. **Commit.** `[<ID>] what changed`, one row per commit. Include regenerated
   `.g.dart` files if you touched a `@riverpod` provider.
7. **Close.** Set the row to `done` and put the short commit hash in `Verify`.
   Report: what was broken, what changed, gate output tail.
8. **Never push.** Merging lanes back to `main` is a human step.

## Lanes and file ownership

| Lane | Owns | Must not touch |
|------|------|----------------|
| `cuts` | `lib/services/purchase_service.dart`, `lib/services/opds_service.dart`, `lib/screens/discover_screen.dart`, `lib/screens/home_shell.dart`, `lib/navigation/app_router.dart`, `android/app/src/main/AndroidManifest.xml`, Drive source panel | reading engine, `lib/design/` |
| `fix` | files named in its `B-xx` row only | anything not in the row |
| `reading` | `lib/features/reading/**`, `lib/screens/parallax_reading_screen.dart`, `lib/three_d/**`, `lib/widgets/` reading overlays | `lib/core/word_timer.dart` pacing constants, `NOTICE` |
| `store` | `doc/release/**`, `doc/legal/**`, `pubspec.yaml` version line only, `lib/screens/settings_screen.dart` (privacy link only) | everything else |
| `ai` | `lib/services/edge_ai_queue.dart`, new `lib/services/ai/**`, `lib/services/content_store/section_models.dart` annotations only | `lib/core/**`, `WordTimer`, reading widgets |
| `gate` | tests and analyzer fallout anywhere | product behaviour |

Shared files that need a board note before editing: `lib/store/config.dart`,
`lib/navigation/app_router.dart`, `lib/screens/home_shell.dart`,
`lib/screens/settings_screen.dart`.

## Subagents available (`.claude/agents/`)

| Agent | Use for | Writes code? |
|-------|---------|--------------|
| `triage-fixer` | one `B-xx` or `R-xx` row end to end | yes |
| `gate-keeper` | make analyze + tests green after merges; no behaviour changes | yes (tests/fallout) |
| `a11y-auditor` | audit a screen against rules 6–8 and WCAG tap targets; files findings as rows | no |
| `ai-integrator` | `A-xx` rows per `AI_INTEGRATION.md` | yes |
| `release-reviewer` | review a lane branch against `CLAUDE.md` before merge | no |

From an interactive session: "use the triage-fixer agent on R-02". Launch
independent rows in the same message so they run in parallel.

## Headless swarm

```bash
# in the devcontainer or any machine with flutter + claude on PATH
scripts/swarm.sh R-01 R-02 R-03          # one worktree + one claude -p run per row
scripts/swarm.sh --dry-run R-05          # print the prompt, launch nothing
SWARM_PERMISSION_FLAGS="--permission-mode acceptEdits" scripts/swarm.sh B-01
```

Each run gets the row text, `CLAUDE.md`, and the gate command in its prompt.
Logs land in `.swarm/<ID>.log` (git-ignored). Inside a throwaway container
you may set `SWARM_PERMISSION_FLAGS="--dangerously-skip-permissions"`; never
do that on a host with credentials mounted.

## Merge order

`cuts` → `fix` → `reading` → `store` → `ai`. After each merge into `main`
run the gate; if red, dispatch `gate-keeper` before merging the next lane.

## Conflict rules

- Two agents on one row: the second one stops and reports.
- Generated files conflict: regenerate with build_runner, never hand-merge `.g.dart`.
- Test fails in a file you did not touch: report it as a new `B-xx` row, do not fix it in your lane.
