# RunThru build orchestrator (prototype)

Automates steps 1–7 + 10 of your manual loop using the **`claude` and `codex`
CLIs on your existing subscriptions** (Claude Pro/Max + ChatGPT Plus). No API
keys, no billing per token. Steps 8 (manual testing) and 9 (PR review) stay
human gates — the loop pings your phone when it reaches them.

## How your 10 steps map

| Your step | Here |
|---|---|
| 1 next unit of work | `pick_next_task` parses `GDI-M2-XX` headers in the goal doc |
| 2 prompt-engineer GPT | `/prompt-engineer` skill (local replacement — see note) |
| 3 author executes | `AUTHOR` CLI (`claude` or `codex`) edits code + runs tests |
| 4 opposite-model review | the OTHER CLI audits the diff per `review_protocol.md` |
| 5 review back through GPT | folded into the protocol's structured `VERDICT:` |
| 6 remediate | findings fed back to the author CLI |
| 7 loop until positive | repeats until `VERDICT: PASS` or `MAX_REVIEW_ROUNDS` |
| 8 manual testing | **you** — phone notification + `MANUAL_TESTS.md` |
| 9 PR review | **you** |
| 10 commit/push | optional gated local commit (`AUTO_COMMIT=1`); **never pushes** |

## One-time setup

1. **CLIs signed in on subscriptions**
   - `claude` — already logged in (Pro/Max).
   - `codex` — run `codex login` and choose "Sign in with ChatGPT" (Plus).
2. **Notifications to your phone**
   - Install the **ntfy** app (Android/iOS) or open https://ntfy.sh in a browser.
   - Subscribe to the topic in `orchestrator.env` → `runthru-98ca698bdbb3`.
   - Test it: `tools/orchestrator/notify.sh "Test" "hello from RunThru"` — you should
     get a push within a second, on LAN or mobile data.
3. **Replace the prompt engineer** (important — see below).

## The one thing you must migrate: the prompt-engineer GPT

Your custom ChatGPT "prompt engineer" GPT **cannot be called programmatically** —
custom GPTs live only in the ChatGPT web UI (no API, no CLI). So this loop uses a
local skill instead: `.agents/skills/prompt-engineer/SKILL.md`. Open it and paste
your GPT's system prompt/instructions into the body (it has a working default until
you do). This is the only manual port required to fully replace your web-UI step.

## Run it

```sh
# Safe first look — picks the next task, shows the backlog state, writes the
# engineering input. No model calls, no edits, no notifications:
tools/orchestrator/run_loop.sh --dry-run

# Real run on the auto-picked next task:
tools/orchestrator/run_loop.sh

# Pin a specific task / flip who authors:
tools/orchestrator/run_loop.sh --task GDI-M2-04A --author codex
```

Artifacts land in `tools/orchestrator/runs/<timestamp>-<task>/`: the engineered
prompt, author logs, every review round, and `MANUAL_TESTS.md`.

## Honest caveats

- **Rate limits.** Two models iterating burns subscription quota (rolling 5-hour +
  weekly caps). A busy day on Pro/Plus may stall mid-loop. Claude **Max** raises the
  ceiling; pacing one task at a time helps.
- **CLI flags may need tuning.** The exact `claude --permission-mode` / `codex exec`
  flags for fully-unattended editing depend on your local config and sandbox. The
  adapters are centralized in `run_loop.sh` (`run_claude`/`run_codex`) — adjust there.
  For true hands-off runs you may want a sandbox + `bypassPermissions` / `--full-auto`.
- **Task-done detection is heuristic.** It reads `<!-- GDI-M2-XX done -->` /
  `<!-- ... completed -->` markers. Use `--task` to be explicit. On PASS with
  `AUTO_COMMIT=1` you should add a `<!-- GDI-M2-XX done -->` marker yourself (or extend
  the script to) so the next run advances.
- **No web-UI automation.** Scraping chatgpt.com would violate ToS and is intentionally
  not done here.
- **The loop never pushes or opens PRs.** That's yours.
