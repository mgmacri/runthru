# RunThru — Release Triage Board

The single shared work board for the swarm. Agents edit **only their own
row**. Statuses: `todo` · `in-progress` · `blocked` · `done` · `deferred`.
Put the agent name in Owner when claiming, the commit hash in Verify when done.

Severity: **P0** crash or blocks reading · **P1** feature visibly wrong · **P2** polish (not on release path).

## Scope cuts (lane `cuts`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-01 | Remove the placeholder `PurchaseService` stub that granted premium for free | P0 | done | claude | `lib/services/purchase_service.dart` | 2ef8768 — superseded by R-11 (owner wants a one-time purchase) |
| R-02 | Remove Discover / OPDS tab | P1 | done | claude | `lib/screens/discover_screen.dart`, `lib/services/opds_service.dart`, `lib/screens/home_shell.dart` tabs, router redirects, tests | ab21e38 — files were already orphaned |
| R-03 | Drop `CAMERA` permission from Android manifest | P1 | done | claude | `android/app/src/main/AndroidManifest.xml` | 7068e65 — also iOS purpose string + Podfile PERMISSION_CAMERA macro; privacy policy updated |
| R-04 | Hide Google Drive source when OAuth client IDs are empty at runtime | P1 | done | claude | `lib/features/content/widgets/google_drive_source_panel.dart`, `lib/screens/sources_screen.dart`, `lib/features/content/providers/google_drive_auth_provider.dart` | fdb4c4d — googleDriveAvailableProvider gates Sources panel, add action, Settings card |

## Broken features from device pass (lane `fix`)

Fill during Step 1 of `RELEASE_PLAN.md`. One row per failure. Repro goes in the title or a sub-bullet.

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| B-01 | Screenshot generator hung `flutter test` (toImage under fake async + window_manager channel + pending timers). Now tagged `screenshots`, skipped by default via `dart_test.yaml`; run with `flutter test --tags screenshots --run-skipped test/screenshots` | P0 | done | claude | `test/screenshots/app_screenshots_test.dart`, `dart_test.yaml` | 1943eea |
| B-02 | Range picker `dispose()` called `ref.read` (throws on unmount in Riverpod 2.6), skipping the rest of dispose and leaking controllers | P0 | done | claude | `lib/screens/range_picker_screen.dart`, `test/screens/range_picker_screen_test.dart` | a603151 |
| B-03 | Google Drive source panel title row overflowed 44px at 390pt width (iPhone 14) | P1 | done | claude | `lib/features/content/widgets/google_drive_source_panel.dart` | 838dce8 |
| B-04 | Primary button announced its label twice and exposed no semantic tap | P1 | done | claude | `lib/widgets/runthru_shell_widgets.dart` | cfe365b |
| B-05 | Gate script wrote analyzer/test output to fixed `/tmp` files shared by every worktree, so parallel swarm gates reported each other's failures | P1 | done | claude | `scripts/verify_release_readiness.sh` | per-run `mktemp` logs |
| B-06 | Onboarding "Next" threw `LateInitializationError` with reduced motion on (`nextPage(Duration.zero)`), stranding users on card 1. Found on emulator with animations off | P0 | done | claude | `lib/widgets/reading_goal_onboarding_gate.dart`, `test/widgets/reading_entry_onboarding_gate_test.dart` | jumpToPage under reduced motion; regression test |
| B-07 | Onboarding drew the design mockup's fake status bar ("8:19 · 5G", signal, battery) under the real one; TalkBack read it out | P1 | done | claude | `lib/widgets/reading_goal_onboarding_gate.dart`, `test/screens/home_shell_test.dart` | widget removed in 3554151; test now asserts it is absent |
| B-08 | EPUB text showed raw markup (`epub:type="titlepage"`, `class="level1">`, `id="toc-li-2">`) in every reading mode: the opening-block-tag rule ate only `<p ` and left attributes behind. Head `<title>` was also read as body text | P0 | done | claude | `lib/services/epub_extractor.dart`, `test/services/epub_extractor_test.dart` | consume whole tag, drop `<head>`; regression test |
| B-09 | Reading views polish (owner: core feature must be perfect). (1) Anchor letter landed on punctuation for punctuated words, so short words like "to." showed no colour and others tinted the wrong letter; three divergent copies of the rule, ASCII-only. Now one `anchorIndexInWord` for all modes. (2) Word-mode guide ticks floated ~34dp outside the em box; now 6dp. Sentence ticks collided with the active-word underline; spacing now derives from font size. (3) Paragraph/Full Page/Sentence text scrolled under the transparent header and play/speed tray; now fades into the stage behind them. (4) Read lines under the dim mask showed pink anchor speckles; anchors now only inside the clear band. (5) Full Page spotlight was a RadialGradient sized by the band's short side, drawing a grey blot mid-screen; now a full-width band. (6) Settings anchor colour was ignored by the main reader; now honoured in every mode, default High Risk Red (4.51:1; Hot Coral was 2.72:1), stored under a new key so the never-applied legacy default does not carry over | P1 | done | claude | `lib/core/orp.dart`, `lib/features/reading/widgets/*`, `lib/screens/parallax_reading_screen.dart`, `lib/store/models.dart`, tests | verified on emulator per mode; gate 1013 pass |
| B-10 | Reader "Aa" pushed `/settings`, which redirects to `/?tab=3` and stacked a second home shell over the reader: the book was left, and Back from the next book landed on Settings | P1 | done | claude | `lib/navigation/app_router.dart`, `lib/screens/settings_screen.dart`, `lib/screens/parallax_reading_screen.dart`, `test/widgets/reading_goal_presets_test.dart` | `/reader-settings` route with back button; verified on emulator |
| B-11 | Reader speed tray highlighted 300 (and told TalkBack it was selected) whenever the speed was between chips, e.g. the 250 WPM Comfortable default, contradicting the header | P1 | done | claude | `lib/screens/parallax_reading_screen.dart`, `test/screens/parallax_reading_screen_test.dart` | exact match only; regression test |
| B-12 | Pause overlay's Focus Mode toggle was centred (`Alignment(0, 0.15)`) and covered the paused focal word, hiding where the reader stopped | P1 | done | claude | `lib/widgets/pause_fog_3d.dart` | moved below the header; verified on emulator |
| B-13 | Paused Word-mode sentence panel is capped at 4 lines; in a long sentence the bold current word fell past line 4 and was faded out | P2 | done | claude | `lib/core/sentence_resolver.dart`, `lib/screens/parallax_reading_screen.dart`, `test/core/sentence_resolver_test.dart` | 30-word window around the current word with ellipses; unit tests |
| B-14 | EPUB table of contents (`properties="nav"`) and `linear="no"` spine items were read as body text: every pandoc/Calibre book opened with "Chapter One: Arrival Chapter Two … Table of Contents" | P1 | done | claude | `lib/services/epub_extractor.dart`, `test/services/epub_extractor_test.dart` | skipped in `_getChapters` (shared by count + extract, so page counts stay consistent); regression test |
| B-15 | Scanned-book EPUBs (e.g. Internet Archive: one XHTML file per print page, 457 here) broke Book pages and paragraphs mid-sentence at every file boundary; documents without paragraph data could lay out the whole book as one block | P1 | done | claude | `lib/services/epub_extractor.dart`, `lib/features/reading/widgets/book_mode_view.dart`, `lib/screens/parallax_reading_screen.dart` | cross-file sentence continuation joins the paragraph; spine files break pages only when they open with a heading; 1200-word block cap + sentence-based fallback paragraphs; tests |
| B-16 | Reader header said "461 min left" while Book's footer said "7 h 40 min left" | P2 | done | claude | `lib/core/time_left.dart` (new), `parallax_reading_screen.dart`, `book_mode_view.dart` | one formatter; unit test |
| B-17 | Sources showed a "Substack · Coming soon" row (definition of done: no stub or coming-soon in the UI) | P1 | done | claude | `lib/screens/sources_screen.dart`, `test/screens/sources_screen_test.dart` | row removed; test asserts no coming-soon |
| B-18 | Library, reader header and Continue Reading showed raw file names ("lighthouse.epub", "…pdfread.net (1).epub"); library rows and the Continue Reading card announced their title three times to TalkBack; Book-mode reading never reached Continue Reading | P1 | done | claude | `lib/services/epub_extractor.dart` (`epubTitle`), `lib/core/document_title.dart`, `lib/features/content/providers/document_title_provider.dart` (new), `library_screen.dart`, `parallax_reading_screen.dart` | EPUB `dc:title` or cleaned file name everywhere; single labelled node with tap action; progress recorded per page turn; tests + emulator |
| B-19 | Settings sliders misreported values to TalkBack: Reading speed said "23%", each pacing slider exposed two contradictory nodes ("100 percent" and "43%"), spacing said "0%"; Reset pacing announced twice | P1 | done | claude | `lib/widgets/wpm_slider.dart`, `lib/features/settings/widgets/pacing_panel.dart`, `lib/features/settings/widgets/spacing_controls.dart` | one merged node per slider with real units (words per minute / percent / pixels); verified via emulator semantics dump |
| B-20 | Regression from B-18: leaving a local book threw `Cannot use "ref" after the widget was disposed` (dispose → Continue Reading save → title getter read `ref`), aborting the rest of dispose | P0 | done | claude | `lib/screens/parallax_reading_screen.dart`, `test/screens/parallax_reading_screen_test.dart` | title cached in build, getter ref-free; regression test proven to fail on the old code |
| B-21 | Library hero "Continue reading" card announced title/source/percent plus its children (raw "local"), and printed minutes in its own format | P2 | done | claude | `lib/screens/library_screen.dart` | single labelled node with tap action; shared time format |
| B-22 | Shared web links read the whole page: navigation, account links, tabs, tables of contents, infobox tables and footers came through as text (each as a bold "heading" in Book mode); titled "Shared text" instead of the page title; inline markup left "word ," spacing (also in EPUBs: `<em>Titanic</em>,` → "Titanic ,"); sharing while a shared text was open showed the new title over the old text; Book mode threw on an empty document during the swap | P1 | done | claude | `content_normaliser.dart`, `share_intent_provider.dart`, `epub_extractor.dart`, `text_segmentation.dart`, `document_title.dart`, `app.dart`, `app_router.dart`, `book_mode_view.dart` | reading-view extraction (article/main region, chrome + link-list removal, citation markers), og:title/<title>, first-line titles for shared/pasted text, inline tags add no space, reader keyed by shared document, empty guard; tests + emulator with en.wikipedia.org/wiki/Lighthouse |
| B-23 | Web reading view kept small link-only navigation ("edit" beside headings, "Article" / "Talk" tabs) | P2 | done | claude | `content_normaliser.dart` + test | elements whose whole text is one short link are dropped |

## Reading screen (lane `reading`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-05 | Sentence mode aligned with the design reference (karaoke line, edge fade) and shipped | P1 | done | claude | `lib/features/reading/widgets/sentence_mode_view.dart`, `reading_focus_chrome.dart` | 945e407 — owner needs Sentence mode |
| R-06 | 60 fps word-flash check on low-end Android with `FpsProbe` | P1 | blocked | claude → owner | `lib/debug/fps_probe.dart`, `lib/screens/parallax_reading_screen.dart` (only if a regression is found) | needs a physical low-end Android (none attached); run on the Play internal-track build and paste the probe log here |

## Store readiness (lane `store`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| R-07 | Privacy policy: real contact, hosted URL, linked from Settings | P0 | done | claude | `doc/legal/privacy_policy.md`, `lib/screens/settings_screen.dart`, gh-pages `privacy/index.html` | a5a6686 + gh-pages 9a22a0a; live at https://runthruapp.com/privacy. OWNER: paste URL into both store consoles |
| R-08 | Store listing copy + screenshots + feature graphic | P0 | in-progress | claude | `doc/release/store/` (new), `screenshots/` | copy in doc/release/store/listing.md. OWNER: 6.9" screenshots, feature graphic, console entry |
| R-09 | Version bump to `2.0.0+16`, release notes | P0 | done | claude | `pubspec.yaml`, `doc/release/CHANGELOG.md` (new) | 31bd936 — Android versionCode now auto-increments in Codemagic |
| R-10 | Verify Codemagic env groups and signing (keystore, ASC key) | P0 | in-progress | claude | `codemagic.yaml` | static check OK (export compliance set, build numbers monotonic, groups referenced); Flutter pinned to 3.41.2. Remaining: green TestFlight + internal builds after push to `main` |
| R-11 | RunThru Unlock one-time IAP (`runthru_unlock`): store purchase, restore, gates on Reading Wins / page ranges / 3D room | P0 | done | claude | `lib/services/purchase_service.dart`, `lib/widgets/unlock_sheet.dart`, gates in home shell / router / settings | be22190 — OWNER: create product in both consoles, set price, sandbox-test on device |
| R-12 | **Book mode (owner request 2026-11-09): Kindle-style paged, non-RSVP reading.** Pages laid out with the same painter settings used to render (never a cut line), real paragraphs, detected headings, EPUB chapters start a fresh page, tap zones (left third back) + swipes + arrow/space keys + labelled 48dp footer buttons, A−/A+ text size (persisted), `% · time left` footer, slide turn (instant under reduced motion), no timer/fog/tray. Turning pages moves the shared position, so Word mode resumes at the top of the page. Last reading mode now persists across books. Prerequisite: shared `textToSentences` keeps paragraph starts (`Sentence.startsParagraph`, JSON `p`), stops inserting fake full stops at clipboard/article paragraph breaks, splits after closing quotes, keeps EPUB headings separate; Paragraph/Full Page now use real paragraphs instead of 50-word chunks | P1 | done | claude | `lib/features/reading/widgets/book_mode_view.dart` (new), `lib/core/text_segmentation.dart` (new), reading mode provider/switcher, `parallax_reading_screen.dart`, extractors, `models.dart`, config | widget tests: every word exactly once across pages, prev returns, chapter breaks, headings, 48dp; verified on emulator |

## AI lane (non-blocking, see `AI_INTEGRATION.md`)

| ID | Title | Sev | Status | Owner | Files | Verify |
|----|-------|-----|--------|-------|-------|--------|
| A-01 | Define `summarize` and `difficulty` tasks + annotation schema | P2 | done | swarm/A-01 | `lib/services/edge_ai_queue.dart`, `lib/services/content_store/section_models.dart` | c45ca7f |
| A-02 | Implement a `ModelProcessor` behind an opt-in flag (default off) | P2 | deferred |  | `lib/services/edge_ai_queue.dart`, new `lib/services/ai/` | 2.1 per RELEASE_PLAN "After release"; AI lane does not block 2.0 |
| A-03 | Consent + settings toggle; privacy policy addendum draft | P2 | deferred |  | `lib/screens/settings_screen.dart`, `doc/legal/privacy_policy.md` | 2.1 per RELEASE_PLAN "After release"; AI lane does not block 2.0 |

## Deferred

| ID | Title | Reason |
|----|-------|--------|
| P-8 | Range picker picks first occurrence of duplicate word | needs pdfrx positional data; edge case |
| LEG | Remove `/read-legacy` + `ReadingScreen` | keep as deep-link fallback for one release |
| EPUB-CACHE | Text extracted before B-08 and migrated from legacy caches keeps the leaked markup (identity is content hash, so re-import does not re-extract) | ContentStore is new in 2.0 so no shipped ContentStore cache exists; bump `kContentStoreSchemaVersion` with a read-path re-extract in 2.0.1 |
| AIQ | `SectionProcessingRequest.fromJson` uses `as` casts; a wrongly typed persisted entry throws `TypeError` that `_decode` does not catch | nothing enqueues in 2.0 (A-02 deferred); fix before A-02 lands |
