# RunThru — Agent Entry Point

This file is the cross-tool entry point (Claude Code, Codex, Copilot, Cursor).
The authoritative instructions live in `CLAUDE.md`; read it in full.

Then:

1. `doc/release/RELEASE_PLAN.md` — what we are shipping and what we cut.
2. `doc/release/TRIAGE.md` — claim one row before touching code.
3. `doc/release/SWARM.md` — lanes, file ownership, commit and gate protocol.

Gate: `scripts/verify_release_readiness.sh` must exit 0 before a row is `done`.

The app is **RunThru** (`com.runthru.app` / `com.mgmacri.runthru`). The repo
folder name `speedy-boyv3` is legacy and must not appear in product copy, docs,
or identifiers.
