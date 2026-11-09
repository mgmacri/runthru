# RunThru — AI Integration Lane

Status 2026-11-09: **plumbing only, no model, no UI.** This lane does not
block the 2.0 release. It ships dormant and lights up in 2.1.

## What already exists

- `lib/services/edge_ai_queue.dart`: durable, coalescing queue of
  `SectionProcessingRequest(bookId, sectionIndex, task)` drained against a
  `ModelProcessor`. Wired processor is `NoopModelProcessor`.
- `ContentStore.annotateSection()` writes results into
  `SectionMetadata.modelAnnotations`.
- Ring 1 (`WordTimer`, pacing) never reads models. It may read annotations if
  present. This boundary is a constitution rule (CLAUDE.md rule 15) and stays.

## What the first real version does

Two tasks, both per section, both optional, both cached in the manifest:

| Task | Output | Surfaces as |
|------|--------|-------------|
| `summarize` | 1–2 plain sentences, reading level ≤ grade 8 | "What this section is about" card before starting a section; also in ContextReveal header |
| `difficulty` | `{score: 0–1, hardWords: [...]}` | pacing hint: suggest a lower WPM preset; never auto-change speed |

Nothing is generated during playback. Work is enqueued when a section is
extracted and drained only while `WordTimer.isPlaying == false` (rule 17).

## Provider choice

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| On-device (Gemini Nano / Apple Foundation Models via platform channel) | matches privacy policy as written, no cost | device coverage is thin, two native implementations | 2.2 |
| Cloud: Claude API, model `claude-haiku-5-5` | one implementation, good at plain-language summaries, cheap per section | sends document text off-device; privacy policy currently says we never do | **2.1, opt-in only** |
| None | nothing to review | no AI | **2.0** |

Cloud is acceptable only with: explicit opt-in toggle (default off), a
consent sheet on first enable, a privacy policy addendum, and a hard rule
that clipboard and Instapaper content are never sent without the toggle.
Proxy the API through a tiny server (Cloudflare Worker) so the key is never
in the app; dart-define `AI_PROXY_URL`, empty means disabled.

## Lane rows (`TRIAGE.md`)

- **A-01** schema: add `ModelAnnotation` type with `task`, `version`,
  `createdAt`, `payload` to `section_models.dart`; `summarize` and
  `difficulty` task constants; tests for JSON round-trip and coalescing.
- **A-02** processor: `lib/services/ai/proxy_model_processor.dart`
  implementing `ModelProcessor` over `AI_PROXY_URL`; transient vs permanent
  failure mapping; token and size guards per the Ring 3 shape (size guard →
  request → persist annotation); tests with a fake `http.Client`. Keep
  `NoopModelProcessor` as the default when the URL is empty.
- **A-03** consent: settings toggle with `Semantics`, consent sheet with
  `liveRegion`, privacy policy addendum in `doc/legal/`; a11y guideline tests.

## Non-goals

- Chat, Q&A, or anything conversational.
- Changing word timing automatically from model output.
- Any model work on the main isolate during reading.
