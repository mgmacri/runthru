# SOP: Decomposing a Backlog Item into Copilot Prompt Files

## When to Use
You have a backlog execution prompt (like `doc/prompts/m1.2.5-pacing-engine.md`) — a large, monolithic spec that's too much for one chat session — and you want to decompose it into focused `.prompt.md` files that produce reliable results.

## Inputs Required
- **Execution prompt**: The monolithic spec (typically in `doc/prompts/`)
- **Source of truth**: External code/specs the prompt references (GitHub repos, design docs)
- **Project context files**: `CLAUDE.md`, `.github/copilot-instructions.md`, existing codebase

## Phase 1: Discovery (~15 min)

### 1.1 Read the Execution Prompt
Identify:
- [ ] Task IDs and dependency graph
- [ ] Files in scope (new + modified)
- [ ] External sources referenced (repos, specs, APIs)
- [ ] Algorithm constants or contracts
- [ ] Verification commands
- [ ] Out-of-scope guardrails

### 1.2 Explore Current Codebase
For every file listed in "files in scope", read the ACTUAL code:
- Class signatures and state shapes
- How config is accessed (ref.watch, ref.read, etc.)
- Existing patterns to replicate (persistence, testing, widget structure)
- What directories exist vs need creation

### 1.3 Fetch External Sources
If the prompt references external code (GitHub repos, APIs):
- Fetch the ACTUAL source files — do not trust the prompt's summary
- Record exact constants, function signatures, test assertions
- **This is the most important step** — prompt summaries often have errors

### 1.4 Cross-Reference: Prompt vs Source
Compare every number/constant/threshold in the prompt against the actual source. Build a discrepancy table:

| Item | Prompt says | Source says | Impact |
|------|------------|-------------|--------|
| ... | ... | ... | ... |

**Any discrepancy must be corrected in the output files.** The source is truth, not the prompt summary.

## Phase 2: Architecture (~10 min)

### 2.1 Identify Natural Session Boundaries
Split on these criteria:
- **One concern per prompt**: Algorithm, tests, integration, UI are separate sessions
- **Pure Dart vs Flutter**: Pure logic can be written without Flutter context; keep it separate
- **Dependency ordering**: Tests can be written against a contract before the implementation exists
- **Parallelizable vs sequential**: Steps with no dependencies can run in parallel

### 2.2 Decide: Shared Context File vs Duplication
**Rule of thumb**: If 3+ prompts need the same context (constants, code signatures, rules), create a shared `.instructions.md` file. If only 1-2 prompts need it, inline it.

**Shared context goes in**: `.github/instructions/{milestone}-context.instructions.md`
- Use `applyTo` to scope it to relevant file paths
- Include: corrected constants, character/data classification, existing code signatures, out-of-scope list, hard rules subset
- Exclude: task-specific instructions (those go in individual prompts)

### 2.3 Map the Prompt Structure

```
.github/
  instructions/
    {milestone}-context.instructions.md    ← shared context
  prompts/
    {milestone}-step1-{name}.prompt.md     ← first session
    {milestone}-step2-{name}.prompt.md     ← second session
    ...
```

Aim for 3-5 prompts per milestone. Fewer than 3 means the original wasn't complex enough to decompose. More than 6 means you're splitting too fine.

## Phase 3: Write the Shared Context File (~15 min)

### Structure Template

```markdown
---
description: "{milestone}: {one-line summary of what context this provides}"
applyTo: "{glob patterns for relevant files}"
---

# {Milestone} — Shared Context

## Constants (verified from source)
[Table of every constant with exact values from the SOURCE, not the prompt]

## Data Classification / Type System
[Character sets, enum values, category definitions — whatever the algorithm needs]

## Existing Code Signatures
[Actual class/function signatures from the codebase, copied verbatim]

## Out of Scope — Do NOT Touch
[File list]

## Hard Rules (subset)
[Only the rules relevant to this milestone]

## Test Baseline
[Current pass/skip/fail counts]
```

### Quality Gates
- [ ] Every constant verified against actual source (not prompt summary)
- [ ] Every code signature verified against actual codebase (not prompt's description)
- [ ] `applyTo` glob matches exactly the files that need this context
- [ ] No task-specific instructions (those belong in individual prompts)

## Phase 4: Write Individual Prompts (~10 min each)

### Prompt Template

```markdown
---
description: "{milestone} Step N: {one-line task description}"
agent: "agent"
---

# Step N — {Title}

> **Milestone**: {id} | **Task**: {task-id}
> **Depends on**: {Step X + Step Y | nothing}
> **Skills to load**: {skill names, if needed}

Load shared context: [link to instructions file]

---

## Task
{One paragraph: what to do and why}

## Files to Create / Modify
{For each file: exact path, what to add/change, code snippets with signatures}

## Verification
{Exact shell command to run}

## Acceptance Criteria
{Checkboxed list — agent checks these before declaring done}
```

### Writing Guidelines

1. **Be prescriptive, not descriptive**: Say "Create this function with this signature" not "You might want to add a function"
2. **Include code snippets**: Show the exact signature, constructor shape, or replacement pattern
3. **Show the verification command**: The agent runs this to self-check
4. **Include a refusal clause**: "You may refuse if {X, Y, Z} — list the ambiguities instead"
5. **Name the skills to load**: If Riverpod/animation/accessibility skills are needed, list them explicitly
6. **State what NOT to do**: Out-of-scope files, patterns to avoid, existing code not to touch
7. **Put exact test values in the test prompt**: The test contract IS the spec — don't make the agent derive values

### What Makes a Prompt Fail (Anti-Patterns)

| Anti-Pattern | Why It Fails | Fix |
|-------------|--------------|-----|
| Prompt summary ≠ source | Agent implements wrong constants | Verify every number against source |
| "Implement the algorithm" (no specifics) | Agent invents behavior | Provide exact function signatures + flow |
| Multi-file changes without code context | Agent guesses existing patterns | Include actual code signatures from codebase |
| No verification command | No way to confirm correctness | Always include `dart analyze` + `flutter test` commands |
| Tests and implementation in same prompt | Session too large, context overflow | Split: tests against contract, then implementation |
| Shared context duplicated in each prompt | Inconsistency across prompts | Extract to `.instructions.md` with `applyTo` |
| Vague acceptance criteria | Agent declares done prematurely | Use checkboxed, verifiable criteria |

## Phase 5: Validate (~5 min)

### Automated Checks
```powershell
# All files have valid YAML frontmatter
Get-ChildItem .github/instructions/*.instructions.md, .github/prompts/*.prompt.md |
  ForEach-Object {
    $c = Get-Content $_.FullName -Raw
    if ($c -match '^---\r?\n[\s\S]*?\r?\n---') { "OK: $($_.Name)" }
    else { "FAIL: $($_.Name)" }
  }

# Shared context referenced by all prompts
Select-String '{milestone}-context.instructions' .github/prompts/*.prompt.md

# Attribution present (if porting external code)
Select-String '{attribution-keyword}' .github/instructions/, .github/prompts/
```

### Manual Checks
- [ ] Each prompt is completable in one chat session (~30-60 min agent work)
- [ ] Dependency graph has no cycles
- [ ] Every C++ / source assertion appears in the test prompt's contract table
- [ ] Every constant from the source appears (corrected) in the instructions file
- [ ] No prompt references files outside its task scope
- [ ] Prompts are invocable via `/` in VS Code chat

## Phase 6: Execute

Follow the [Prompt Execution SOP](/memories/sop-prompt-execution.md).

---

## Checklist Summary

```
□ Read execution prompt, identify tasks + dependencies
□ Explore codebase: actual signatures, patterns, directory structure
□ Fetch external sources: actual constants, test assertions
□ Build discrepancy table: prompt summary vs actual source
□ Decide session boundaries (3-5 prompts)
□ Create shared .instructions.md with corrected constants + code signatures
□ Create individual .prompt.md files with prescriptive specs
□ Validate: YAML frontmatter, context links, test contract completeness
□ Execute per the execution SOP
```

## Estimated Time

| Phase | Time |
|-------|------|
| Discovery | 15 min |
| Architecture | 10 min |
| Shared context | 15 min |
| Individual prompts (× N) | 10 min each |
| Validation | 5 min |
| **Total (4 prompts)** | **~85 min** |
