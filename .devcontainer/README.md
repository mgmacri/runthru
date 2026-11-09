# RunThru devcontainer

Pinned Flutter 3.41.2 + Android SDK + Claude Code. iOS builds still need a
Mac (Codemagic does them in CI).

## VS Code / Cursor

Open the folder, "Reopen in Container". `post-create.sh` runs `flutter pub get`.

## Plain Docker

```bash
docker build -f .devcontainer/Dockerfile -t runthru-dev .
docker run -it --rm \
  -v "$PWD":/workspace \
  -v runthru-pub-cache:/root/.pub-cache \
  -v runthru-claude-home:/root/.claude \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  runthru-dev
```

## Authenticating Claude Code inside the container

Pick one:

- `claude setup-token` on the host, then export `CLAUDE_CODE_OAUTH_TOKEN`
  before starting the container (the devcontainer forwards it).
- Or run `claude` once inside the container and log in; the
  `runthru-claude-home` volume keeps the session.
- Or set `ANTHROPIC_API_KEY` for API billing.

## Running the swarm

```bash
scripts/verify_release_readiness.sh        # gate
scripts/swarm.sh R-01 R-02                 # one headless agent per TRIAGE row
```

Inside a throwaway container with no host credentials mounted you may run
`SWARM_PERMISSION_FLAGS="--dangerously-skip-permissions" scripts/swarm.sh ...`.
Do not do that on a host checkout.

## Devices

Android emulators do not run well inside Docker. Build an APK in the
container (`flutter build apk --debug`) and install it on a host-connected
device with `adb install`, or expose the host adb server with
`-e ADB_SERVER_SOCKET=tcp:host.docker.internal:5037`.
