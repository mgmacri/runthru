# Speedy Boy v7.0 — Task Backlog

**Generated**: 2026-04-24
**Spec version**: 7.0.0 (On-Device Reading Assistant)
**Codebase scanned**: c:\Users\Matthew\speedy-boyv3

## Scan Summary

- **Implemented**: 0 / 7 v7 priorities
- **Partial**: 0 / 7 v7 priorities
- **Not started**: 7 / 7 v7 priorities
- **Total tasks generated**: 31

## Blockers & Ambiguities

1. **CDN host for model files undecided.** Model is 700 MB to 1.8 GB; bandwidth at scale needs a no-egress-fee host. Cloudflare R2 is the recommended default but the account, bucket, and DNS configuration must be set up before TASK-407 can be tested end-to-end. Mock-served local manifest is fine for development.

2. **Rust toolchain in Codemagic CI.** Codemagic has no first-class Rust support. The build will install rustup in a script step, which adds ~2–3 minutes per build and increases the risk of CI flakes. Pin the toolchain version. TASK-401 must verify cold-start build time stays under 15 minutes total.

3. **iOS App Store review risk.** Apps that download large data files post-install are scrutinized. Model weights are data, not executable code, so this is allowed under Apple's guidelines, but App Review notes should explicitly call out: "Reading assistant model is downloaded after install for offline AI inference. No code is downloaded — only data files." TASK-431 covers this in the release checklist.

4. **`flutter_rust_bridge` major version pin.** The crate has had breaking changes between minor versions. Pin to a single version in `Cargo.toml` and `pubspec.yaml`. TASK-400 documents the chosen version.

5. **RTX 2060 6GB training constraints.** Per the v7 spec, the dev box can comfortably train Llama 3.2 1B and tightly train 3B with QLoRA + gradient checkpointing + batch size 1. If the eval target (P20: ≥85%) is not met by 1B, training 3B is the fallback. TASK-422 measures this.

6. **Long-press gesture conflict with WPM dial (Rule 24, 38).** Long-press in the reading area triggers WPM dial during active RSVP, but should trigger the AssistantSheet *only when reading is paused*. TASK-413 must add a state guard in `gesture_classifier.dart` and verify with extended `gesture_flow_v4_test.dart`.

7. **AppConfig migration from v6 to v7.** v6 users upgrading must default to `assistantEnabled = false` so no behavior change occurs without consent. TASK-403 covers backward compatibility tests.

---

## Sprint 1: Foundation — Rust Workspace, Bridge, Config

### TASK-400: Add Rust workspace and flutter_rust_bridge scaffolding
- **Priority**: 0 (prerequisite)
- **Files**: `CREATE: rust/Cargo.toml`, `CREATE: rust/src/lib.rs`, `MODIFY: pubspec.yaml`, `MODIFY: .gitignore`
- **Action**: Create `rust/` workspace at repo root. Add `flutter_rust_bridge` with pinned version (latest stable as of release date, document version in `rust/README.md`). Add minimal `hello_world() -> String` Rust function exported via the bridge. Add `flutter_rust_bridge` to `pubspec.yaml` dependencies. Run `flutter_rust_bridge_codegen generate`. Verify generated `lib/services/assistant_bridge.dart` compiles. Add `target/` and generated bridge files to `.gitignore` per Rust + frb conventions.
- **Acceptance criteria**:
  - [ ] `rust/Cargo.toml` exists with pinned `flutter_rust_bridge` version
  - [ ] `cargo build --release` succeeds in `rust/`
  - [ ] Generated `lib/services/assistant_bridge.dart` compiles
  - [ ] Calling `hello_world()` from a Dart unit test returns `"hello"`
  - [ ] `dart analyze lib/` reports 0 issues
- **Principles**: None (infrastructure)
- **Effort**: M (~2 hr)
- **Depends on**: Nothing

### TASK-401: Codemagic CI integration for Rust build
- **Priority**: 0 (prerequisite)
- **Files**: `MODIFY: codemagic.yaml`
- **Action**: Add Rust toolchain install + cross-compile + library copy steps to both iOS and Android workflows. iOS: `aarch64-apple-ios`, `aarch64-apple-ios-sim`, lipo into universal `.a`, copy to `ios/Runner/Frameworks`. Android: `aarch64-linux-android`, `armv7-linux-androideabi`, copy `.so` files to `android/app/src/main/jniLibs/<abi>/`. Pin Rust toolchain version. Verify cold-start full build < 15 minutes.
- **Acceptance criteria**:
  - [ ] iOS workflow installs Rust toolchain, builds Rust library, copies to Frameworks dir
  - [ ] Android workflow installs Rust toolchain, builds Rust library, copies to jniLibs dir
  - [ ] Both workflows build successfully end-to-end on CI
  - [ ] Cold-start full build time documented in `codemagic.yaml` comment, < 15 min
  - [ ] Rust toolchain version pinned (no `stable` or `latest`)
- **Principles**: None (infrastructure)
- **Effort**: L (~3 hr)
- **Depends on**: TASK-400

### TASK-402: Add llama.cpp Rust dependency and stub model load
- **Priority**: 1
- **Files**: `MODIFY: rust/Cargo.toml`, `CREATE: rust/src/model_loader.rs`, `MODIFY: rust/src/lib.rs`
- **Action**: Add `llama-cpp-2` (or equivalent maintained crate) as a Rust dependency. Implement `load_model(path: String) -> Result<ModelHandle>` and `unload_model()`. Use mmap for loading (Rule 39). Expose via flutter_rust_bridge. Add a placeholder GGUF file (very small test model, e.g. TinyLlama Q4_K_M ~600KB if available, or a stub) for integration testing.
- **Acceptance criteria**:
  - [ ] `llama-cpp-2` (or equivalent) added to `rust/Cargo.toml` with pinned version
  - [ ] `load_model` mmaps the file (verify with `mincore` on Linux dev box)
  - [ ] `load_model` returns error on invalid GGUF, malformed file, missing file
  - [ ] `unload_model` releases mmap
  - [ ] Integration test loads stub GGUF and verifies handle is non-null
  - [ ] `cargo clippy` reports 0 warnings
- **Principles**: P19, P20
- **Effort**: M (~2.5 hr)
- **Depends on**: TASK-400

### TASK-403: AppConfig additions for assistant
- **Priority**: 0 (prerequisite)
- **Files**: `MODIFY: lib/store/models.dart`, `MODIFY: lib/store/config.dart`
- **Action**: Add `assistantEnabled` (bool, default false), `assistantModelVariant` (`AssistantModelVariant`, default `lite`), `assistantModelStatus` (`AssistantModelStatus`, default `notDownloaded`), `assistantModelVersion` (String?, default null). Add new enums `AssistantModelVariant { lite, standard }` and `AssistantModelStatus { notDownloaded, downloading, ready, updateAvailable, failed }`. Add `copyWith` support. Add 4 setter methods to `ConfigNotifier` following `_synchronized` pattern. Ensure JSON backward compatibility (missing keys → defaults — v6 users upgrade with assistant disabled).
- **Acceptance criteria**:
  - [ ] Two new enums declared in `lib/store/models.dart`
  - [ ] Four new fields in AppConfig with correct defaults
  - [ ] `copyWith` supports all four new fields
  - [ ] `toJson`/`fromJson` round-trips correctly
  - [ ] v6-format JSON (without v7 keys) → v7 AppConfig with all defaults
  - [ ] Four new setter methods in ConfigNotifier follow `_synchronized` pattern
  - [ ] `dart analyze lib/` reports 0 issues
- **Principles**: None (foundation)
- **Effort**: S (~30 min)
- **Depends on**: Nothing

---

## Sprint 2: Native Inference Path

### TASK-404: Implement Rust inference with token streaming
- **Priority**: 1
- **Files**: `CREATE: rust/src/assistant.rs`, `MODIFY: rust/src/lib.rs`
- **Action**: Implement `complete(prompt: String) -> Stream<String>` exposed via flutter_rust_bridge. Use llama.cpp's streaming API. Each token is sent as a separate event over the bridge. Handle: max token limit (200), stop sequences, generation timeout (15s, per `assistantInferenceTimeoutMs`), interrupted streams (caller drops the stream → cancel generation).
- **Acceptance criteria**:
  - [ ] `complete()` streams tokens to Dart as they are generated
  - [ ] Stream terminates on stop sequence, max tokens, or timeout
  - [ ] Dropping the Dart stream cancels generation in Rust
  - [ ] Concurrent calls are serialized (model is single-threaded)
  - [ ] Memory does not leak across 100 sequential invocations (verified with valgrind / heaptrack)
  - [ ] `cargo clippy` reports 0 warnings
- **Principles**: P19, P20
- **Effort**: L (~3 hr)
- **Depends on**: TASK-402

### TASK-405: Create AssistantService Dart facade
- **Priority**: 1
- **Files**: `CREATE: lib/services/assistant_service.dart`
- **Action**: Public API: `Future<void> ensureModelLoaded()`, `Stream<String> complete({required String sentence, required String question})`, `Future<void> unloadModel()`. Internally calls `assistant_bridge.dart` (Rule 38). Constructs the prompt: system prompt + sentence + question (Rule 40). Lazy model load on first `complete()` call (Rule 39). Background unload after 5 min idle (Rule 39). No prompt logging (Rule 36).
- **Acceptance criteria**:
  - [ ] `complete()` constructs the correct prompt format
  - [ ] First call triggers model load, subsequent calls reuse loaded model
  - [ ] Idle for `assistantBackgroundUnloadMs` → model unloaded
  - [ ] No prompt or response text written to any logger
  - [ ] No persistent state across `complete()` calls
  - [ ] Stream propagates from Rust bridge to caller
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P19, P20, P21
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-404, TASK-403

### TASK-406: Mock AssistantService for tests
- **Priority**: 2
- **Files**: `CREATE: test/services/assistant_service_mock.dart`
- **Action**: Mock implementation that returns a predetermined stream of tokens. Used in widget and integration tests instead of the real Rust bridge. Configurable: response text, per-token delay, optional error after N tokens.
- **Acceptance criteria**:
  - [ ] Mock conforms to same interface as `AssistantService`
  - [ ] Configurable response, delay, and error injection
  - [ ] Used via Riverpod override in tests
  - [ ] All existing tests still pass with mock available
- **Principles**: None
- **Effort**: S (~30 min)
- **Depends on**: TASK-405

---

## Sprint 3: Model Distribution

### TASK-407: Create ModelManifest service
- **Priority**: 2
- **Files**: `CREATE: lib/services/model_manifest.dart`
- **Action**: `fetchManifest()` → fetch `https://<cdn>/assistant/manifest.json`, parse into `ModelManifest` record with: `version`, `variants` (map of `AssistantModelVariant` → `{url, sizeBytes, sha256, minRamMb}`). Handle network errors (return null). Cache parsed manifest in memory for the session. Verify URL host matches expected CDN (defense-in-depth).
- **Acceptance criteria**:
  - [ ] Fetches and parses well-formed manifest
  - [ ] Returns null on network error, malformed JSON, or unexpected host
  - [ ] In-memory cache hit on second call within session
  - [ ] No model files downloaded by this service (manifest only)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: None
- **Effort**: S (~30 min)
- **Depends on**: TASK-403

### TASK-408: Create ModelDownloader service
- **Priority**: 2
- **Files**: `CREATE: lib/services/model_downloader.dart`
- **Action**: `downloadModel(variant)` → fetch model file from manifest URL, stream to `<appSupport>/assistant_model/<variant>/model.gguf.partial`. Resumable via HTTP `Range` header on retry. On completion, verify SHA-256, atomic-rename to `model.gguf`. Emit progress as `Stream<DownloadProgress>` (bytes downloaded, total bytes, ETA). Handle: network failure (resumable), corrupted file (delete + retry), out of disk space (clear partial, error to user).
- **Acceptance criteria**:
  - [ ] Streams to `.partial` file (never overwrites existing model)
  - [ ] Resumes via `Range` header on retry
  - [ ] SHA-256 verified before atomic rename
  - [ ] Atomic rename only after successful verification
  - [ ] Progress stream emits at least every 1 second during active download
  - [ ] Network error → resumable, not restart from zero
  - [ ] Disk full → graceful error, partial file cleaned up
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P19
- **Effort**: L (~2.5 hr)
- **Depends on**: TASK-407

### TASK-409: Create ModelDownloadCard widget
- **Priority**: 3
- **Files**: `CREATE: lib/widgets/model_download_card.dart`
- **Action**: Settings-screen card showing current model status. States: not downloaded (button: "Download model — XXX MB"), downloading (progress bar, MB downloaded / total, cancel button), ready (variant name, size on disk, "Re-download" action), update available (button: "Update model — XXX MB"), failed (error message, "Retry"). Variant selector visible in not-downloaded and ready states.
- **Acceptance criteria**:
  - [ ] All 5 states render correctly
  - [ ] Progress bar updates from `DownloadProgress` stream
  - [ ] Cancel during download deletes `.partial` file
  - [ ] Variant selector disabled during download
  - [ ] Semantics labels for all interactive elements
  - [ ] Surface world compliance (Rule 7, design tokens only)
  - [ ] `dart analyze` reports 0 issues
- **Principles**: None
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-408

### TASK-410: Device capability detection for variant suggestion
- **Priority**: 3
- **Files**: `MODIFY: lib/services/device_capability.dart`
- **Action**: Extend existing `DeviceCapability` service. Add `recommendedAssistantVariant()` → returns `lite` or `standard` based on device RAM, CPU, and (if available) NPU presence. iOS: A13 and earlier → `lite`; A14+ → `standard`. Android: < 6 GB RAM → `lite`; ≥ 6 GB and Snapdragon 8-series or Dimensity 9000+ → `standard`. Otherwise → `lite`.
- **Acceptance criteria**:
  - [ ] Returns `lite` on iPhone 11 (A13)
  - [ ] Returns `standard` on iPhone 12 (A14)
  - [ ] Returns `lite` on Android device with < 6 GB RAM (any chipset)
  - [ ] Returns `standard` on Pixel 8 (Tensor G3, 8 GB RAM)
  - [ ] Returns `lite` on unknown/older Android (safe default)
  - [ ] Unit-testable via injectable device-info provider
  - [ ] `dart analyze` reports 0 issues
- **Principles**: None
- **Effort**: M (~1 hr)
- **Depends on**: TASK-403

### TASK-411: Model update detection
- **Priority**: 4
- **Files**: `MODIFY: lib/services/model_manifest.dart`, `MODIFY: lib/widgets/model_download_card.dart`
- **Action**: On app launch (if assistant enabled), fetch manifest in background. Compare manifest version to `assistantModelVersion` in AppConfig. If newer, set `AssistantModelStatus.updateAvailable`. ModelDownloadCard renders update prompt. User must explicitly confirm to download (no auto-download).
- **Acceptance criteria**:
  - [ ] Background manifest fetch on app launch (if assistant enabled)
  - [ ] Version comparison sets `updateAvailable` correctly
  - [ ] Old model continues to work until user updates
  - [ ] No automatic re-download
  - [ ] Manifest fetch failure does not block app or assistant use
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P21
- **Effort**: S (~45 min)
- **Depends on**: TASK-407, TASK-408

---

## Sprint 4: AssistantSheet UI & Gesture Wiring

### TASK-412: Create AssistantState and AssistantNotifier
- **Priority**: 2
- **Files**: `CREATE: lib/core/assistant_state.dart`, `CREATE: lib/core/assistant_notifier.dart`
- **Action**: `AssistantState` immutable class: `sheetState` (enum), `currentSentence` (String), `userQuestion` (String), `responseTokens` (List<String>), `error` (String?). `AssistantNotifier` (Riverpod, **auto-dispose** per Rule 41): `openSheet(sentence)`, `submitQuestion(question)`, `dismissSheet()`. `submitQuestion` calls `AssistantService.complete()` and appends each streamed token to `responseTokens`.
- **Acceptance criteria**:
  - [ ] `AssistantState` immutable with `copyWith`
  - [ ] Notifier is `AutoDisposeNotifier` (Rule 41)
  - [ ] `openSheet` transitions to `awaitingQuestion`, sets sentence
  - [ ] `submitQuestion` transitions to `generating`, streams tokens
  - [ ] `dismissSheet` transitions to `hidden`, clears all fields
  - [ ] Auto-disposed when sheet closed (verified with provider lifecycle test)
  - [ ] No state persists across sheet sessions
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P21
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-405

### TASK-413: Wire long-press gesture to AssistantSheet (paused-only)
- **Priority**: 2
- **Files**: `MODIFY: lib/core/gesture_classifier.dart`, `MODIFY: lib/screens/parallax_reading_screen.dart`, `MODIFY: lib/screens/reading_screen.dart`
- **Action**: Long-press in reading area: if RSVP active → show WPM dial (existing v4 behavior, Rule 26). If RSVP paused → open AssistantSheet (new). Long-press on WPM dial widget itself → unchanged (still WPM dial behavior). Add state guard in `gesture_classifier.dart` to dispatch correctly. Pre-load current sentence into AssistantSheet via `AssistantNotifier.openSheet()`.
- **Acceptance criteria**:
  - [ ] Long-press during active RSVP → WPM dial shown (regression check)
  - [ ] Long-press while paused → AssistantSheet shown
  - [ ] Long-press on WPM dial widget → WPM dial behavior preserved
  - [ ] Current sentence pre-loaded into sheet
  - [ ] No leak — gesture classifier state isolated
  - [ ] Extended `gesture_flow_v4_test.dart` passes
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P21
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-412

### TASK-414: Create AssistantSheet widget
- **Priority**: 3
- **Files**: `CREATE: lib/widgets/assistant_sheet.dart`, `CREATE: lib/widgets/assistant_message.dart`
- **Action**: Modal bottom sheet shown via `showModalBottomSheet`. Layout: dismiss handle at top, current sentence display (read-only), streaming response area, text input at bottom. `AssistantMessage` widget renders the streaming token list with cursor-style typing indicator while `generating`. Swipe-down dismisses (velocity ≥ `assistantSheetDismissVelocity`). On dismiss, reading resumes from same word (existing pause-resume behavior). Handles `failed` state with retry. Handles `notDownloaded` and `downloading` states by showing "Model not ready — go to Settings to download".
- **Acceptance criteria**:
  - [ ] Sheet enters with `assistantSheetEnterMs` animation
  - [ ] Current sentence pre-populated and read-only
  - [ ] Text input submits question on send button or enter
  - [ ] Streaming tokens render incrementally
  - [ ] Swipe-down dismisses, reading resumes from same word
  - [ ] `notDownloaded` / `downloading` shows fallback message + Settings link
  - [ ] `failed` shows error + retry button
  - [ ] Surface world compliance (Rule 7)
  - [ ] Reduced motion respected (Rule 5)
  - [ ] Semantics labels for screen readers
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P21
- **Effort**: L (~2.5 hr)
- **Depends on**: TASK-412, TASK-413

### TASK-415: OOM fallback for under-specced devices
- **Priority**: 3
- **Files**: `MODIFY: lib/services/assistant_service.dart`, `MODIFY: lib/widgets/assistant_sheet.dart`
- **Action**: If model load fails with OOM on `standard` variant, surface error to user: "This device may not have enough memory for the standard model. Switch to lite?" with one-tap action. Never silently downgrade — user always confirms. Per spec gap #3.
- **Acceptance criteria**:
  - [ ] OOM during model load is caught (not unhandled exception)
  - [ ] User shown actionable prompt with variant switch option
  - [ ] No automatic variant change without user consent
  - [ ] After variant switch, user re-downloads new variant via Settings
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P19, P21
- **Effort**: M (~1 hr)
- **Depends on**: TASK-405, TASK-414

---

## Sprint 5: Settings Integration

### TASK-416: Add assistant section to Settings screen
- **Priority**: 4
- **Files**: `MODIFY: lib/screens/settings_screen.dart`
- **Action**: Add "Reading Assistant" section above the Instapaper section. Toggle: "Enable Reading Assistant" (binds to `AppConfig.assistantEnabled`). When enabled and model not downloaded, show variant selector + ModelDownloadCard. When enabled and ready, show variant + disk usage + "Re-download model" action. Add explainer text per Rule 36: "Your questions and the assistant's answers stay on this device. Nothing is sent over the internet."
- **Acceptance criteria**:
  - [ ] New section appears above Instapaper section
  - [ ] Toggle binds to `assistantEnabled`
  - [ ] Variant selector visible only when enabled
  - [ ] ModelDownloadCard visible only when enabled
  - [ ] Privacy explainer text always visible when enabled
  - [ ] `dart analyze` reports 0 issues
- **Principles**: P19
- **Effort**: M (~1 hr)
- **Depends on**: TASK-409, TASK-410

---

## Sprint 6: Tests

### TASK-417: Unit tests — AssistantState and AssistantNotifier
- **Priority**: 3
- **Files**: `CREATE: test/core/assistant_notifier_test.dart`
- **Action**: Test state transitions: hidden → awaitingQuestion → generating → hidden. Test auto-dispose lifecycle. Test that `submitQuestion` accumulates tokens correctly. Test error handling. Test `dismissSheet` clears all state.
- **Acceptance criteria**:
  - [ ] All state transitions covered
  - [ ] Auto-dispose verified (provider re-initialized after sheet close)
  - [ ] Token accumulation tested via mock service
  - [ ] Error path tested
  - [ ] All tests pass
- **Principles**: None
- **Effort**: M (~1 hr)
- **Depends on**: TASK-412, TASK-406

### TASK-418: Unit tests — ModelDownloader
- **Priority**: 3
- **Files**: `CREATE: test/services/model_downloader_test.dart`
- **Action**: Test successful download with SHA-256 verification. Test resumption via Range header (mock HTTP). Test SHA-256 mismatch → file deleted, error returned. Test disk full → partial cleaned up. Test cancellation → partial preserved for resume.
- **Acceptance criteria**:
  - [ ] Successful download + verify path tested
  - [ ] Range header resumption tested
  - [ ] SHA-256 mismatch handling tested
  - [ ] Disk full handling tested
  - [ ] Cancellation tested
  - [ ] All tests pass
- **Principles**: None
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-408

### TASK-419: Widget test — AssistantSheet
- **Priority**: 3
- **Files**: `CREATE: test/widgets/assistant_sheet_test.dart`
- **Action**: Render sheet with mock service. Test sentence pre-population. Test question submission. Test streaming token rendering. Test swipe-down dismissal. Test error state rendering. Test notDownloaded / downloading fallback states.
- **Acceptance criteria**:
  - [ ] Sheet renders with pre-populated sentence
  - [ ] Submit triggers AssistantNotifier.submitQuestion
  - [ ] Streaming tokens appear in DOM as they arrive
  - [ ] Swipe-down dismisses
  - [ ] All non-ready states render correctly
  - [ ] All tests pass
- **Principles**: None
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-414, TASK-406

### TASK-420: Integration test — gesture wiring (paused-only assistant)
- **Priority**: 3
- **Files**: `MODIFY: integration_test/gesture_flow_v4_test.dart`
- **Action**: Extend existing v4 gesture flow test. Add: long-press during active RSVP → WPM dial appears (regression). Long-press while paused → AssistantSheet appears. Long-press on WPM dial widget → WPM dial behavior preserved.
- **Acceptance criteria**:
  - [ ] WPM dial regression test still passes
  - [ ] Paused long-press → AssistantSheet appears
  - [ ] WPM dial widget long-press unchanged
  - [ ] All v4 gesture tests still pass
- **Principles**: None
- **Effort**: M (~1 hr)
- **Depends on**: TASK-413, TASK-414

### TASK-421: Integration test — model load → inference → display
- **Priority**: 3
- **Files**: `CREATE: integration_test/assistant_inference_test.dart`
- **Action**: Use real Rust bridge with stub GGUF model. Trigger sheet open, submit a question, verify tokens stream to UI. Verify second invocation reuses loaded model (no re-load latency). Verify model unload after `assistantBackgroundUnloadMs`.
- **Acceptance criteria**:
  - [ ] First invocation: model loads, response streams
  - [ ] Second invocation: model not reloaded (latency < 100ms to first token)
  - [ ] After 5 min idle, model unloaded (verified via memory check or service state)
  - [ ] No prompt or response text in any log output
  - [ ] All tests pass
- **Principles**: P19, P36 (no logs)
- **Effort**: L (~2 hr)
- **Depends on**: TASK-405, TASK-414

---

## Sprint 7: Synthetic Data Pipeline (Dev-Only)

### TASK-422: Create tools/assistant directory and seed dataset
- **Priority**: 1 (parallelizable with Sprints 1–6)
- **Files**: `CREATE: tools/assistant/README.md`, `CREATE: tools/assistant/seeds.jsonl`, `CREATE: tools/assistant/pyproject.toml`
- **Action**: Create dev-only directory (Rule 42 — never imported by app). Hand-author 50 diverse seed Q&A examples covering: word definitions in context (15), sentence summaries (10), pronunciation help (5), comprehension prompts (10), off-topic refusals (10). Set up Python project with `anthropic`, `unsloth`, `datasets`, `trl`, `transformers` deps.
- **Acceptance criteria**:
  - [ ] `tools/assistant/` exists at repo root
  - [ ] `seeds.jsonl` has 50 examples spanning all 5 categories
  - [ ] At least 10 off-topic refusal examples (per spec gap #5)
  - [ ] `pyproject.toml` declares all training dependencies
  - [ ] `README.md` documents the full pipeline operator workflow
  - [ ] CI excludes `tools/assistant/` from app build (verify Codemagic config)
- **Principles**: P20
- **Effort**: L (~3 hr — most of it is writing good seeds)
- **Depends on**: Nothing

### TASK-423: Implement generate_dataset.py
- **Priority**: 2
- **Files**: `CREATE: tools/assistant/generate_dataset.py`
- **Action**: Submit Claude Sonnet 4.6 Batch API job — 50 seeds × 20 expansions = 1,000 examples. Poll until done. Parse and flatten to JSONL in Alpaca format. Save to `train.jsonl`. Log cost estimate before submission, ask for confirmation. Include sanity check: discard examples with malformed JSON, off-tone language, or wrong format.
- **Acceptance criteria**:
  - [ ] Submits Batch API job with correct request format
  - [ ] Polls until `processing_status == "ended"`
  - [ ] Parses results, handles malformed responses gracefully
  - [ ] Outputs Alpaca-format JSONL
  - [ ] Cost estimate logged before submission, confirmation required
  - [ ] At least 800 valid examples from a 1,000-target run (≥80% yield)
- **Principles**: P20
- **Effort**: M (~2 hr)
- **Depends on**: TASK-422

### TASK-424: Implement train.py for QLoRA fine-tuning
- **Priority**: 3
- **Files**: `CREATE: tools/assistant/train.py`
- **Action**: Unsloth-based QLoRA training script. Targets Llama 3.2 1B by default, with 3B as flag. Settings tuned for RTX 2060 6GB: batch size 1, gradient accumulation 8, gradient checkpointing on, paged AdamW 8-bit optimizer, max sequence length 512. Saves LoRA adapter to `output/`. Documented training time: 1B ≈ 4–6 hr, 3B ≈ 10–14 hr.
- **Acceptance criteria**:
  - [ ] Script runs end-to-end on RTX 2060 6GB
  - [ ] 1B training completes without OOM
  - [ ] 3B training completes without OOM (with documented gradient checkpointing on)
  - [ ] LoRA adapter saved to `output/`
  - [ ] Training metrics logged (loss curve)
  - [ ] Documented expected runtime in README
- **Principles**: P20
- **Effort**: L (~3 hr)
- **Depends on**: TASK-423

### TASK-425: Implement eval.py with LLM-as-judge
- **Priority**: 3
- **Files**: `CREATE: tools/assistant/eval.py`, `CREATE: tools/assistant/test_set.jsonl`
- **Action**: Held-out test set (~100 examples). Run trained model on each. Send `(question, expected_answer, model_answer)` to Claude Sonnet 4.6 with judge prompt: "Is the model answer acceptable for this question? Yes/No." Compute acceptance rate. Must be ≥85% per P20 / E-14 to ship.
- **Acceptance criteria**:
  - [ ] Test set of ≥100 examples (separate from training set)
  - [ ] LLM-as-judge prompt is documented
  - [ ] Outputs acceptance rate as percentage
  - [ ] Outputs per-category breakdown (definitions, summaries, refusals, etc.)
  - [ ] Refusal categorization: did model correctly refuse off-topic?
  - [ ] Exits non-zero if acceptance rate < 85% (CI-friendly)
- **Principles**: P20
- **Effort**: M (~2 hr)
- **Depends on**: TASK-424

### TASK-426: Implement convert_to_gguf.py
- **Priority**: 4
- **Files**: `CREATE: tools/assistant/convert_to_gguf.py`
- **Action**: Merge LoRA adapter into base model, convert to GGUF format using llama.cpp's `convert_hf_to_gguf.py`, quantize to Q4_K_M. Output: `output/model.gguf`. Compute SHA-256 and write to `output/model.sha256`.
- **Acceptance criteria**:
  - [ ] LoRA adapter merged into base model successfully
  - [ ] GGUF file produced
  - [ ] Quantized to Q4_K_M
  - [ ] SHA-256 file written
  - [ ] Output GGUF loads in llama.cpp standalone (verify with `llama-cli`)
- **Principles**: P19
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-425

### TASK-427: Implement upload.py for CDN distribution
- **Priority**: 4
- **Files**: `CREATE: tools/assistant/upload.py`
- **Action**: Upload `model.gguf` to CDN bucket. Update `manifest.json` with new version, URL, size, SHA-256. Atomic update — manifest updated last so clients never see broken state. Default target: Cloudflare R2 (per blocker #1).
- **Acceptance criteria**:
  - [ ] Uploads model file to CDN
  - [ ] Updates manifest with all required fields
  - [ ] Manifest update is last operation
  - [ ] Idempotent — re-running with same version is a no-op (or errors clearly)
  - [ ] Documented rollback procedure in README
- **Principles**: None
- **Effort**: M (~1.5 hr)
- **Depends on**: TASK-426

---

## Sprint 8: Privacy, Polish, Release

### TASK-428: Privacy audit — verify no prompt leaks
- **Priority**: 4
- **Files**: All assistant-related files
- **Action**: Manual audit per Rule 36. Search for any `print`, `debugPrint`, `log`, `Logger`, or analytics call that could include prompt text. Test crash report payload generation with active assistant context — verify scrubbing. Verify `Sentry.captureException` (or equivalent) does not include prompt fields.
- **Acceptance criteria**:
  - [ ] grep for `prompt`, `question`, `response`, `sentence` in logging calls — zero hits in non-test code
  - [ ] Crash report payload manually inspected — no prompt content
  - [ ] Analytics events manually inspected — no prompt content
  - [ ] Privacy audit checklist documented in `tools/assistant/README.md`
- **Principles**: P19, Rule 36
- **Effort**: M (~1.5 hr)
- **Depends on**: All Sprint 4–6 tasks

### TASK-429: Battery and memory profiling
- **Priority**: 4
- **Files**: N/A (measurement only)
- **Action**: Manual on-device profiling. Run 30-min reading session with 5 assistant invocations on iPhone 12, iPhone 14, mid-range Android (e.g. Pixel 7a), flagship Android (e.g. Pixel 8 Pro). Measure: peak RSS, battery delta vs control session, first-token latency, subsequent-token latency. Validate against spec acceptance thresholds (P19 / E-13 prediction).
- **Acceptance criteria**:
  - [ ] Battery delta < 5% vs control session on all test devices
  - [ ] Peak RSS < 2 GB for `standard` variant on flagship devices
  - [ ] Peak RSS < 1.5 GB for `lite` variant on all devices
  - [ ] First-token latency < 1.5s on Snapdragon 8 Gen 2, < 3s on iPhone 12
  - [ ] Subsequent-token latency < 80ms on flagship, < 150ms on mid-range
  - [ ] Results documented in `doc/v7-perf-report.md`
- **Principles**: P19
- **Effort**: L (~3 hr — physical device testing)
- **Depends on**: TASK-414, TASK-415

### TASK-430: App size delta verification
- **Priority**: 4
- **Files**: N/A (measurement only)
- **Action**: Compare `.ipa` and `.aab` size between latest v6 release and v7 build. Rust runtime + flutter_rust_bridge + native libs should add < 10 MB total. If over, investigate (likely candidates: debug symbols, unstripped Rust binary).
- **Acceptance criteria**:
  - [ ] iOS `.ipa` size delta < 10 MB
  - [ ] Android `.aab` size delta < 10 MB
  - [ ] Per-architecture `.so` size delta documented in `doc/v7-perf-report.md`
- **Principles**: P19 (model not bundled)
- **Effort**: S (~30 min)
- **Depends on**: TASK-401

### TASK-431: App Store / Play Store release notes and review notes
- **Priority**: 5
- **Files**: `CREATE: doc/v7-release-notes.md`
- **Action**: User-facing release notes ("New: ask the assistant about what you're reading. Runs entirely on your device. No internet required."). App Review notes per blocker #3: "Reading assistant model is downloaded after install for offline AI inference. No code is downloaded — only data files. Model files are GGUF format quantized neural network weights, used by llama.cpp inference library bundled with the app."
- **Acceptance criteria**:
  - [ ] User release notes drafted (English, max 200 words)
  - [ ] App Review notes drafted with explicit data-not-code statement
  - [ ] Privacy nutrition label updated (if needed) — assistant collects no data
  - [ ] Documented in `doc/v7-release-notes.md`
- **Principles**: None
- **Effort**: S (~45 min)
- **Depends on**: All other tasks

---

## Effort Summary

| Sprint | Tasks | Total Effort |
|--------|-------|--------------|
| 1: Foundation | TASK-400 to TASK-403 | ~7 hr |
| 2: Native Inference | TASK-404 to TASK-406 | ~5 hr |
| 3: Model Distribution | TASK-407 to TASK-411 | ~6 hr |
| 4: AssistantSheet UI | TASK-412 to TASK-415 | ~6.5 hr |
| 5: Settings | TASK-416 | ~1 hr |
| 6: Tests | TASK-417 to TASK-421 | ~7 hr |
| 7: Data Pipeline | TASK-422 to TASK-427 | ~13 hr |
| 8: Privacy & Release | TASK-428 to TASK-431 | ~6 hr |
| **Total** | **31 tasks** | **~51.5 hr** |

Sprint 7 (data pipeline) is parallelizable with Sprints 1–6 — it produces the model file that Sprint 4 needs, but the engineering work in Sprints 1–6 can use a stub model for development and testing.

The critical path runs Sprints 1 → 2 → 4 → 6 → 8. Sprint 3 unblocks user-facing distribution but is not on the critical path for getting inference working in dev.
