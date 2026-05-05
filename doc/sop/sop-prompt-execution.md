# SOP: Executing a Decomposed Prompt Set

## When to Use
You have a set of `.prompt.md` files (e.g., `m1.2.5-step1-algorithm.prompt.md` through `step4`) and want to execute them to complete a milestone.

## Pre-Flight Checklist
1. **Verify files exist**: `Get-ChildItem .github/prompts/m1.2.5-*.prompt.md`
2. **Verify shared context**: `Get-ChildItem .github/instructions/m1.2.5-*.instructions.md`
3. **Check dependency graph**: Read the `> Depends on:` line in each prompt's header
4. **Confirm test baseline**: `flutter test` — record pass/skip/fail counts BEFORE starting
5. **Confirm analysis clean**: `dart analyze --fatal-infos`
6. **Branch**: `git checkout -b feat/{task-id}-{short-desc}` from latest main

## Execution Flow

### Step 1: Identify Parallelizable Steps
Look at the dependency graph in the prompt headers. Steps with "Depends on: nothing" can run in parallel. Steps with "Depends on: Step N" must wait.

Example for M1.2.5:
```
Step 1 (algorithm) ‖ Step 2 (tests)  →  Step 3 (integration)  →  Step 4 (UI)
```

### Step 2: Start a Chat Session Per Step
1. Open a new Copilot Chat session
2. Type `/` and select the prompt (e.g., `m1.2.5-step1-algorithm`)
3. The prompt loads with its instructions, shared context via the markdown link, and task spec
4. Let the agent execute. It has everything it needs.
5. **Do not add extra context** — the prompt is self-contained

### Step 3: Verify After Each Step
After each step completes, run its verification command (listed at the bottom of each prompt):
- Step 1: `dart analyze lib/features/reading/pacing/`
- Step 2: `flutter test test/features/reading/pacing/word_duration_test.dart`
- Step 3: `dart analyze lib/core/word_timer.dart lib/store/` then `flutter test test/core/`
- Step 4: `dart analyze lib/features/settings/widgets/pacing_panel.dart lib/screens/settings_screen.dart`

**Gate rule**: Do not start a dependent step until its prerequisite's verification passes.

### Step 4: Run Full Suite After All Steps
```powershell
dart analyze --fatal-infos
flutter test
```
Compare pass/skip/fail to your pre-flight baseline. New tests should increase the pass count. No new failures.

### Step 5: Commit
One commit per step is fine. Use conventional commits:
```
feat(pacing): implement word duration algorithm and PacingConfig
test(pacing): port RSVP Nano test suite to Dart
feat(pacing): wire adaptive pacing into WordTimerNotifier
feat(settings): add pacing panel to settings screen
```

## Troubleshooting

| Problem | Action |
|---------|--------|
| Step fails verification | Fix in the same chat session — the agent has context |
| Agent invents algorithm constants | Point it to the test contract — tests are truth |
| Agent touches out-of-scope files | Reject and re-prompt with "Do NOT modify {file}" |
| Dependent step fails because prerequisite is wrong | Go back to the prerequisite step, fix, re-verify, then retry |
| Agent asks for clarification | Answer it — the prompt has a refusal clause for genuine ambiguity |
