# Speedy Boy v7.0 — Design Specification

**Version**: 7.0.0
**Date**: 2026-04-24
**Status**: Draft
**Type**: Feature release — on-device reading assistant

---

## Design Philosophy

v7 introduces a contextual reading assistant that runs entirely on the user's device. The assistant answers narrow, in-session questions about what the user is reading right now: word definitions in context, sentence-level summaries, comprehension nudges. No internet required. No per-query API cost. No user text leaves the device.

The architectural decision is forced by the business model: Speedy Boy is a one-time purchase and a server-side LLM means every successful user becomes a recurring cost. On-device inference keeps marginal cost at zero so the feature can scale with adoption instead of working against it.

The assistant does not replace the reading engine. It is a sidecar that the user can summon during a pause and dismiss to resume. It must feel instantaneous, honest about its limits, and silent when not invoked.

---

## What's Being Added

| Component | Why |
|-----------|-----|
| On-device LLM runtime (llama.cpp via flutter_rust_bridge) | Native inference on iOS and Android with full model control |
| Quantized 1B–3B reading-assistant model (GGUF) | Fits in mobile RAM, downloaded after install |
| AssistantSheet UI | Bottom sheet invoked by long-press or dedicated gesture during pause |
| Synthetic data generation pipeline (desktop, dev-only) | Fine-tunes the model from Claude-generated training data |
| Model download + version management | First-launch download with progress, integrity check, resumability |
| AssistantConfig (new AppConfig section) | Enable/disable, model variant selection, download status |

## What Stays

| Component | Notes |
|-----------|-------|
| All v3–v6 features | Unchanged |
| Reading engine (RSVP, ContextReveal, parallax, gestures) | The assistant is invoked only when reading is paused |
| Instapaper integration (v6) | The assistant works on Instapaper articles, clipboard documents, and PDFs identically |
| Offline-first principle | The assistant strengthens this — no network is touched at runtime |

---

## New Design Principles (v7 additions)

### P19: On-Device by Default (Grade A)

**Statement**: Any feature that processes user reading content must run on-device. The user's text is private and the app's cost structure must not scale with usage.

**Evidence chain**:
- Privacy expectation in reading apps is high (industry consensus, e.g. Pocket and Instapaper article retention policies — Grade B for user expectation, A for legal exposure under GDPR Art. 5(1)(c) data minimisation)
- Per-query cloud inference creates a runaway-cost failure mode for one-time-purchase apps (operator economics — Grade A)
- Modern mid-range mobile NPUs are sufficient for 1B–3B parameter LLMs at sub-second latency (MediaPipe / llama.cpp benchmarks 2025 — Grade A)

**Grade rationale**: The constraint is engineering-driven and well-evidenced. Composite grade: A.

**Testable prediction (E-13)**: Users who invoke the assistant ≥1× per session will not show a measurable change in app battery cost vs control sessions of equivalent length, beyond the model load time on first invocation.

---

### P20: Narrow-Scope Specialist (Grade B)

**Statement**: A small fine-tuned model on a narrow task can match or exceed a large general model on that task, because the distribution shift between training data and inference data is minimal. The assistant must therefore be scoped narrowly and trained explicitly for that scope.

**Evidence chain**:
- Domain-specific fine-tuning of small models (1B–7B) closes the gap with frontier models on narrow tasks (Hu et al., LoRA 2021 — Grade A; Dettmers et al., QLoRA 2023 — Grade A)
- Distillation from large to small models preserves task quality when the student covers the same input distribution as training (Hinton et al. 2015 — Grade A; ongoing replication 2023–2025 — Grade A)
- Out-of-scope queries to a fine-tuned narrow model degrade gracefully if the model is trained to refuse (instruction-tuning literature — Grade B)

**Grade rationale**: The mechanism is well-evidenced for narrow tasks. The specific scope (in-session reading questions) has not been independently validated in published literature. Composite grade: B.

**Testable prediction (E-14)**: A 1B–3B model fine-tuned on ≥1,000 in-session reading Q&A examples will achieve ≥85% acceptable-answer rate (LLM-as-judge eval) on a held-out test set, vs ~95% for the teacher Claude Sonnet 4.6 baseline.

---

### P21: Silent Until Summoned (Grade C)

**Statement**: The assistant must never interrupt reading. It loads on first invocation, runs only when explicitly summoned, and dismisses without lingering UI. Background prefetch, suggestions, and notifications are forbidden.

**Evidence chain**:
- ADHD and low-WM readers are particularly vulnerable to interruption-driven attention loss (Lanier 2021 — Grade B; Barkley 1997 — Grade A)
- Notification fatigue reduces feature engagement long-term (HCI literature on permission prompts and engagement — Grade B)
- Reading flow disruption has measurable comprehension cost (Rayner 1998 — Grade A as foundational; specific mobile-reading replication — Grade C)

**Grade rationale**: Composite of well-evidenced harm mechanisms applied to a specific UX rule. Grade: C.

**Testable prediction (E-15)**: Sessions with the assistant enabled but uninvoked will show identical comprehension scores to sessions with the assistant disabled, controlling for session length and content difficulty.

---

## Architecture & Data Flow

The assistant runs as a Rust-bridged native library invoked from Dart. The model is downloaded after install, stored in app support directory, and memory-mapped at first invocation. There is no server component at runtime.

```
┌────────────────────────────────────────────────────────────────┐
│                     Speedy Boy (Flutter)                        │
│                                                                 │
│   [User pauses reading] ──long-press──▶ AssistantSheet         │
│                                              │                  │
│                                              ▼                  │
│                                    AssistantNotifier            │
│                                    (Riverpod, auto-dispose)     │
│                                              │                  │
│                                              ▼                  │
│                                    AssistantService             │
│                                    (Dart facade)                │
│                                              │                  │
│                                              ▼                  │
│                                    flutter_rust_bridge          │
└──────────────────────────────────────────────┼──────────────────┘
                                               │
                                               ▼
┌────────────────────────────────────────────────────────────────┐
│                   Native Library (Rust + llama.cpp)             │
│                                                                 │
│   - Load GGUF model (mmap)                                     │
│   - Run inference (CPU + GPU offload if available)             │
│   - Stream tokens back to Dart                                 │
└────────────────────────────────────────────────────────────────┘

   [Desktop dev pipeline — separate from app, runs once per release]
   ┌────────────────────────────────────────────────────────────┐
   │  Claude Sonnet 4.6 (Batch API)                              │
   │       │                                                     │
   │       ▼                                                     │
   │  Synthetic Q&A dataset (JSONL)                              │
   │       │                                                     │
   │       ▼                                                     │
   │  QLoRA fine-tune on RTX 2060 (Llama 3.2 1B or 3B)          │
   │       │                                                     │
   │       ▼                                                     │
   │  Convert to GGUF Q4_K_M                                     │
   │       │                                                     │
   │       ▼                                                     │
   │  Upload to CDN → app downloads on first launch              │
   └────────────────────────────────────────────────────────────┘
```

### Data Write
- User pauses RSVP → invokes assistant gesture → AssistantSheet appears
- Sheet sends current sentence + user question to AssistantService
- AssistantService formats prompt and calls Rust bridge
- Rust runs llama.cpp inference, streams tokens back
- AssistantNotifier emits tokens to UI as they arrive

### Data Read
- Model weights loaded once per app session (mmap from disk)
- No persistent state across invocations — each Q&A is independent
- No conversation history retained beyond current sheet session

### Model Download
- First launch: AssistantConfig.modelStatus = `notDownloaded`
- User toggles assistant on in Settings → triggers download
- Download progress shown in Settings, resumable
- On completion: SHA-256 verify, set status to `ready`
- Model files stored at `<appSupport>/assistant_model/<variant>/`

---

## Priority 1: Native Runtime Layer

### Files to Create
```
rust/                                      (new top-level directory)
  Cargo.toml
  src/
    lib.rs                                 (flutter_rust_bridge entry points)
    assistant.rs                           (llama.cpp wrapper, prompt formatting)
    model_loader.rs                        (GGUF loading, validation)
ios/Runner.xcodeproj/...                  (link Rust static library)
android/app/build.gradle                   (Rust NDK build integration)
lib/services/assistant_bridge.dart         (auto-generated from rust/)
lib/services/assistant_service.dart        (Dart facade — public API)
```

### Build System Integration
- Rust toolchain managed via `rustup` in CI (Codemagic)
- iOS: cross-compile to `aarch64-apple-ios` and `aarch64-apple-ios-sim`, lipo into universal `.a`
- Android: cross-compile to `aarch64-linux-android` and `armv7-linux-androideabi` via NDK, place in `android/app/src/main/jniLibs/`
- `flutter_rust_bridge_codegen` runs as a pre-build step, generates `assistant_bridge.dart`

### Action
1. Add `rust/` workspace at repo root
2. Add `flutter_rust_bridge` dependency to `pubspec.yaml`
3. Add llama.cpp as Rust dependency (via `llama-cpp-rs` or `llama-cpp-2` crate)
4. Implement minimal `complete(prompt: String) -> Stream<String>` in Rust
5. Wire into Codemagic — separate workflow steps for Rust build, then Flutter build
6. Verify build on both iOS and Android emulators with a stub model

### Do / Don't

| Do | Don't |
|----|-------|
| Cross-compile Rust in Codemagic before Flutter build | Bundle the Rust toolchain in the repo |
| Use mmap for model loading | Read the entire model into RAM as bytes |
| Stream tokens to Dart | Block on full completion before returning |
| Treat model load as expensive (do it once per session) | Reload the model per query |

---

## Priority 2: Assistant Model Pipeline (Dev-Side, Not Shipped)

### Files to Create (new `tools/assistant/` directory, not part of the app)
```
tools/assistant/
  README.md                                (pipeline operator guide)
  generate_dataset.py                      (Claude Batch API client)
  seeds.jsonl                              (~50 hand-written Q&A seeds)
  train.py                                 (Unsloth + QLoRA training script)
  eval.py                                  (held-out test set, LLM-as-judge)
  convert_to_gguf.py                       (Hugging Face → GGUF Q4_K_M)
  upload.py                                (push to CDN, update manifest)
  pyproject.toml                           (Python deps: anthropic, unsloth, etc.)
```

### Action
1. Hand-author 50 diverse seed examples covering: word definitions in context, sentence summaries, pronunciation help, comprehension prompts, off-topic refusals
2. Run `generate_dataset.py` → 1,000–2,000 synthetic examples via Claude Sonnet 4.6 Batch API
3. Manually review 5% sample, discard anything off-tone
4. Run `train.py` on RTX 2060 → produces LoRA adapter (1B model, ~4–6 hours; 3B model, ~10–14 hours)
5. Run `eval.py` → must achieve ≥85% acceptable-answer rate before release (P20)
6. Run `convert_to_gguf.py` → quantize to Q4_K_M
7. Run `upload.py` → push to CDN, update `manifest.json` with version + SHA-256

### Do / Don't

| Do | Don't |
|----|-------|
| Use Claude Sonnet 4.6 (not Opus 4.7) as teacher | Pay the Opus 4.7 tokenizer tax for narrow-task data |
| Use Batch API (50% off) | Use real-time API for non-interactive data gen |
| Manually review a sample before training | Train blindly on raw generated data |
| Version every model release (v1.0.0, v1.0.1) | Hot-swap models without version bumps |
| Keep `tools/assistant/` out of the Flutter build | Bundle Python or training deps with the app |

---

## Priority 3: Model Download & Storage

### Files to Create
```
lib/services/model_downloader.dart         (download, verify, resume)
lib/services/model_manifest.dart           (parse remote manifest.json)
lib/widgets/model_download_card.dart       (Settings UI for download state)
```

### Action
1. On Settings screen toggle "Enable assistant" → check `AssistantConfig.modelStatus`
2. If `notDownloaded`, fetch `https://<cdn>/assistant/manifest.json`
3. Show download size and require user confirmation (200MB–1.2GB depending on variant)
4. Download to `<appSupport>/assistant_model/<variant>/model.gguf`
5. Verify SHA-256 against manifest
6. Set status to `ready`, persist to AppConfig
7. On app upgrade: check manifest version, prompt to update if newer model available

### Variant Strategy

| Variant | Base | Size on disk | Min RAM | Target devices |
|---------|------|--------------|---------|----------------|
| `lite` | Llama 3.2 1B Q4_K_M | ~700 MB | 1.5 GB free | All supported devices |
| `standard` | Llama 3.2 3B Q4_K_M | ~1.8 GB | 2.5 GB free | iPhone 12+, Snapdragon 8-series, Dimensity 9000+ |

Device capability check on first toggle picks the recommended variant. User can override in Settings.

### Do / Don't

| Do | Don't |
|----|-------|
| Require user opt-in before downloading | Auto-download on first launch |
| Resume interrupted downloads | Restart from zero on every retry |
| Verify SHA-256 before marking ready | Trust HTTPS alone for integrity |
| Show download size up-front in MB | Hide the cost behind "Downloading..." |

---

## Priority 4: AssistantSheet UI

### Files to Create
```
lib/core/assistant_state.dart              (sheet state machine)
lib/core/assistant_notifier.dart           (Riverpod, auto-dispose)
lib/widgets/assistant_sheet.dart           (bottom sheet UI)
lib/widgets/assistant_message.dart         (streaming token display)
```

### Invocation
- During paused RSVP or ContextReveal: long-press in the reading viewport → opens AssistantSheet
- Long-press on the WPM dial is reserved for the dial — assistant gesture is in the reading area
- AssistantSheet appears with the current sentence pre-loaded as context
- Text input at bottom for the user's question
- Streaming response appears above, token-by-token

### State Machine
```
[hidden]
   │ long-press in reading area while paused
   ▼
[open, awaiting question]
   │ user types and submits
   ▼
[open, generating response (streaming)]
   │ user dismisses (swipe down or tap outside)
   ▼
[hidden] → reading resumes from same word
```

### Do / Don't

| Do | Don't |
|----|-------|
| Pre-load the current sentence as context | Make user paste or re-type |
| Stream tokens as they arrive | Wait for full response before showing |
| Dismiss on swipe-down | Add an explicit close button only |
| Resume reading at the same word on dismiss | Reset to start of sentence |
| Limit response to ~40 words by training | Hardcode a token cutoff in UI |

---

## Priority 5: AssistantConfig & Settings

### AppConfig Additions

```dart
final bool assistantEnabled;                         // default: false
final AssistantModelVariant assistantModelVariant;   // default: AssistantModelVariant.lite
final AssistantModelStatus assistantModelStatus;     // default: AssistantModelStatus.notDownloaded
final String? assistantModelVersion;                 // default: null
```

### New Enums (in `lib/store/models.dart`)

```dart
enum AssistantModelVariant { lite, standard }
enum AssistantModelStatus { notDownloaded, downloading, ready, updateAvailable, failed }
```

### New ConfigNotifier Methods

```dart
Future<void> setAssistantEnabled(bool enabled);
Future<void> setAssistantModelVariant(AssistantModelVariant variant);
Future<void> setAssistantModelStatus(AssistantModelStatus status);
Future<void> setAssistantModelVersion(String? version);
```

### Settings Screen Additions
- "Reading Assistant" section above Instapaper
- Toggle: Enable Reading Assistant
- Variant selector (visible only after toggle on): Lite / Standard with size and device-suitability annotation
- Download progress card (visible only when downloading)
- "Re-download model" action (visible when ready)
- Disk usage display (e.g. "Standard model — 1.8 GB")

---

## Priority 6: Privacy & Telemetry

### Action
- The assistant must not log user questions or model responses anywhere on disk
- The assistant must not transmit user questions or responses anywhere over the network
- Crash reports and analytics must scrub any prompt content (assistant context never enters Sentry / analytics payloads)
- Add a Settings explainer: "Your questions and the assistant's answers stay on this device. Nothing is sent over the internet."

### Do / Don't

| Do | Don't |
|----|-------|
| Log prompt length and latency | Log prompt content |
| Crash on integrity check failure (loud) | Silently fall back to a partially-validated model |
| Scrub prompts from analytics events | Trust the SDK's default redaction |

---

## Priority 7: Verify & Ship

### Action
- `dart analyze lib/` → zero issues
- `cargo clippy` (in `rust/`) → zero warnings
- `flutter test` → all pass (assistant service mocked)
- Integration test: load stub model, send prompt, verify token stream
- Manual on-device test on iPhone (12, 14, 16) and Android (Snapdragon 7-series mid-range, 8-series flagship)
  - Latency: first token < 1.5s on Snapdragon 8 Gen 2, < 3s on iPhone 12
  - Latency: subsequent tokens < 80ms on flagship, < 150ms on mid-range
  - Memory: peak RSS during inference < 2 GB for `standard` variant
- App size delta: Flutter binary growth < 10 MB (Rust runtime adds ~6–8 MB; model is downloaded, not bundled)
- Battery: 30-min session with 5 assistant invocations should not exceed normal session battery cost by more than 5%

---

## Open Questions / Spec Gaps

1. **Model hosting cost.** The model file is ~700 MB to 1.8 GB. CDN bandwidth at scale needs a cheap host — Cloudflare R2 (no egress fees) is the recommended default but requires a hosting decision before TASK-407.

2. **iOS App Store review risk.** Apps that download executable code post-install are scrutinized; model weights are data, not executable, but this should be flagged in App Review notes. No precedent suggests rejection but worth pre-flighting.

3. **Variant fallback on under-specced devices.** If user picks `standard` on a 4GB-RAM Android phone and inference OOMs, what happens? TASK-414 needs a graceful fallback path: detect OOM, suggest `lite`, never auto-downgrade silently.

4. **Model update policy.** When v1.0.1 of the model is released, does it auto-download or require user opt-in? Recommend: notify in Settings, require explicit re-download. TASK-411 implements detection; the consent flow is TBD.

5. **Off-topic refusal training.** The seed dataset must include explicit refusals for off-topic questions (e.g. "what's the weather"). Without these, the model will hallucinate. Document this requirement in `tools/assistant/README.md`.

6. **Long-press conflict with v4 gesture map.** v4 reserves long-press for the WPM dial. The assistant invocation is *also* long-press but in a different region (reading area, not dial). TASK-413 must verify there's no leak: long-press on the dial → WPM dial; long-press on the reading area → assistant. Tested with `gesture_flow_v4_test.dart` extended.
