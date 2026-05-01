// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

/// Transforms doc/runthru-backlog.json to fix:
/// 1. All PowerShell verification_commands → bash equivalents
/// 2. Add granularity_rationale to every node
/// 3. Add ethical_blockers to accessibility-adjacent epics
/// 4. Fix R3 weeks (13-17 → 14-18)
/// 5. Ensure E1.3.2 depends_on includes E1.3.1

// ──────────────────────────────────────────────
// PowerShell → bash verification command mapping
// ──────────────────────────────────────────────
const verificationFixes = <String, String>{
  // findstr commands
  "grep -ri 'speedy.boy' lib/ | grep -v '.g.dart' | wc -l | findstr /r \"^0\$\"":
      "! grep -ri 'speedy.boy' lib/ --include='*.dart' --exclude='*.g.dart'",
  "grep -ri 'speedy.boy' test/ | wc -l | findstr /r \"^0\$\"":
      "! grep -ri 'speedy.boy' test/",
  "grep -ri 'speedy' android/ | wc -l | findstr /r \"^0\$\"":
      "! grep -ri 'speedy' android/",
  "grep -ri 'speedy' ios/ | wc -l | findstr /r \"^0\$\"":
      "! grep -ri 'speedy' ios/",
  // Select-String commands
  "Select-String -Path pubspec.yaml -Pattern 'name: runthru'":
      "grep 'name: runthru' pubspec.yaml",
  "Select-String -Path android/app/src/main/AndroidManifest.xml -Pattern 'android.intent.action.SEND'":
      "grep 'android.intent.action.SEND' android/app/src/main/AndroidManifest.xml",
  "Select-String -Path android/fastlane/Fastfile -Pattern 'internal'":
      "grep 'internal' android/fastlane/Fastfile",
  "Select-String -Path ios/fastlane/Fastfile -Pattern 'testflight'":
      "grep -i 'testflight' ios/fastlane/Fastfile",
  // Test-Path for files
  'Test-Path android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png':
      'test -f android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
  'Test-Path .github/workflows/ci.yml': 'test -f .github/workflows/ci.yml',
  'Test-Path .github/workflows/release-build.yml':
      'test -f .github/workflows/release-build.yml',
  'Test-Path ios/fastlane/Fastfile': 'test -f ios/fastlane/Fastfile',
  'Test-Path doc/store-listing/app_store_description.md':
      'test -f doc/store-listing/app_store_description.md',
  'Test-Path doc/legal/privacy_policy.md':
      'test -f doc/legal/privacy_policy.md',
  // Test-Path for directories
  'Test-Path assets/fonts/AtkinsonHyperlegible':
      'test -d assets/fonts/AtkinsonHyperlegible',
  'Test-Path ios/ShareExtension': 'test -d ios/ShareExtension',
};

// ──────────────────────────────────────────────
// Granularity rationale for every node, by ID
// ──────────────────────────────────────────────
const rationales = <String, String>{
  // --- Releases ---
  'R1':
      'Release boundary: MVP establishes core product for App Store submission — complete reading experience, content ingestion pipeline, and store presence required before market validation',
  'R2':
      'Release boundary: Confluence Marketplace App targets a different platform (Atlassian Forge/web) requiring skill acquisition (Forge CLI, React custom UI) not yet available',
  'R3':
      'Release boundary: social integrations introduce network I/O, OAuth flows, and third-party API dependencies deferred until on-device reading experience is validated in market',

  // --- Milestones ---
  'M1.1':
      'Milestone boundary: identity and CI/CD must stabilize before feature branches begin — all subsequent milestones depend on correct app naming and automated build verification',
  'M1.2':
      'Milestone boundary: design system tokens and Riverpod provider architecture are consumed by every downstream screen epic — 8 epics declare dependency on M1.2 outputs',
  'M1.3':
      'Milestone boundary: content ingestion is the primary user-acquisition funnel — users cannot experience reading UX without importable content, making this prerequisite to M1.4',
  'M1.4':
      'Milestone boundary: reading experience polish layers on top of M1.2 design system and M1.3 content pipeline — cannot start without styled ConsumerWidget screens and importable content',
  'M1.5':
      'Milestone boundary: launch readiness is the final validation gate — store listing requires feature-complete app for screenshots, and stats require completed reading sessions to measure',

  // --- Epics (Release 1) ---
  'E1.1.1':
      'Epic scope: rebrand is a cross-cutting concern spanning Dart source, test files, platform configs (Android XML, iOS plist), asset files, and pubspec.yaml — requires coordinated multi-file sweep',
  'E1.1.2':
      'Epic scope: CI/CD infrastructure (GitHub Actions YAML, Fastlane Ruby DSL) is a distinct skill domain from app Dart code — parallelizable with rebrand due to zero file overlap',
  'E1.2.1':
      'Epic scope: design system defines color, typography, decoration, and animation tokens consumed by every widget — requires CVD validation, WCAG contrast math, and Flutter ThemeData coordination across 3 features',
  'E1.2.2':
      'Epic scope: applying design system requires touching every existing screen file — depends on both E1.2.1 (design tokens) and E1.2.3 (ConsumerWidget migration) completing first',
  'E1.2.3':
      'Epic scope: Riverpod state migration is foundational architecture — 8 downstream epics declare depends_on E1.2.3 because they require ConsumerWidget + provider patterns established',
  'E1.3.1':
      'Epic scope: universal share sheet coordinates iOS Share Extension (Swift, Xcode target, App Group) with Android Intent receiver (manifest XML, Dart handler) — two platform-native implementations sharing one Dart provider',
  'E1.3.2':
      'Epic scope: content pipeline cleanup spans three extraction formats (PDF, EPUB, text/HTML) with shared isolate concurrency patterns — sequenced after E1.3.1 so content routing is established',
  'E1.3.3':
      'Epic scope: clipboard detection and file picker are independent content-ingestion sources with different platform APIs — parallelizable with E1.3.1 due to zero file overlap',
  'E1.4.1':
      'Epic scope: RSVP UX polish modifies word timer timing, gesture classifier thresholds, and reading screen rendering — coordinates animation, gesture, and state concerns across 3 core files',
  'E1.4.2':
      'Epic scope: multi-mode reading introduces two new widget trees (sentence view, paragraph view) plus mode-switching state — depends on E1.4.1 establishing gesture and timer patterns',
  'E1.4.3':
      'Epic scope: accessibility foundations span settings providers, reading overlays, and design tokens — parallelizable with E1.4.1 because file scopes do not overlap',
  'E1.4.4':
      'Epic scope: artifact suppression combines an isolate-based classification engine with a gesture-driven suppression UI overlay — depends on E1.3.2 content pipeline for standardized input format',
  'E1.5.1':
      'Epic scope: stats foundation requires coordinated Isar schema design, Riverpod provider, and dashboard widget across the new features/stats/ directory',
  'E1.5.2':
      'Epic scope: app store presence spans platform-specific Fastlane configs, legal/privacy documents, and marketing copy — parallelizable with E1.5.1 due to zero file overlap',

  // --- Epics (Release 2 — epic-level only) ---
  'E2.1':
      'Epic-level placeholder: Forge App Shell not decomposed below epic until Atlassian Forge skill gap is resolved and Release 1 ships',
  'E2.2':
      'Epic-level placeholder: Content Extraction Pipeline not decomposed — requires Forge app shell (E2.1) and Confluence REST API knowledge',
  'E2.3':
      'Epic-level placeholder: Flutter Web Build not decomposed — requires understanding Forge Custom UI iframe constraints',
  'E2.4':
      'Epic-level placeholder: Progressive Depth not decomposed — depends on content extraction pipeline (E2.2) establishing input format',
  'E2.5':
      'Epic-level placeholder: Team Analytics not decomposed — requires Forge storage API and privacy-preserving aggregation design',
  'E2.6':
      'Epic-level placeholder: Marketplace Listing not decomposed — gated on Atlassian security self-assessment requirements',

  // --- Epics (Release 3 — epic-level only) ---
  'E3.1':
      'Epic-level placeholder: Social Integration Infrastructure not decomposed — OAuth2 flow patterns determined during Release 1 completion',
  'E3.2':
      'Epic-level placeholder: Reddit Integration not decomposed — depends on social infrastructure (E3.1) establishing auth patterns',
  'E3.3':
      'Epic-level placeholder: Fediverse Integration not decomposed — three protocol clients (AT Protocol, ActivityPub, Lemmy) require separate research',
  'E3.4':
      'Epic-level placeholder: Reading Queue not decomposed — depends on social integrations providing content to enqueue',
  'E3.5':
      'Epic-level placeholder: RSS/Atom Feeds not decomposed — parsing library selection deferred until Release 3 planning',

  // --- Features ---
  'F1.1.1.1':
      'Feature split: code reference renaming is mechanical grep-and-replace across Dart/test files — distinct tooling and skill from visual asset replacement in F1.1.1.2',
  'F1.1.1.2':
      'Feature split: app icons require platform-specific asset pipelines (Android mipmap densities, iOS xcassets) — different skill from text find-replace',
  'F1.1.2.1':
      'Feature split: GitHub Actions uses YAML workflow syntax on Ubuntu runners — distinct from Fastlane Ruby DSL in F1.1.2.2',
  'F1.1.2.2':
      'Feature split: Fastlane involves platform signing certificates, provisioning profiles, and Ruby lane definitions — isolated from GitHub Actions YAML',
  'F1.2.1.1':
      'Feature split: color tokens are the foundation consumed by typography, decoration, and animation tokens — must stabilize API surface before dependents begin',
  'F1.2.1.2':
      'Feature split: typography tokens require font asset bundling (pubspec.yaml fonts section, OTF/TTF files) plus family-switching logic — different concern from color math',
  'F1.2.1.3':
      'Feature split: decoration factories and animation constants depend on color tokens being defined — separate rendering concern from text styling, parallelizable internally',
  'F1.2.2.1':
      'Feature split: library and settings screens are independent screen files with no shared mutable state — two agents can redesign them in parallel',
  'F1.2.2.2':
      'Feature split: reading and analytics screens have different animation requirements — reading needs slow-eased word fades, analytics needs data visualization patterns',
  'F1.2.2.3':
      'Feature split: CVD verification is a test-only pass gated on all screen redesigns completing — produces no production code, only test assertions against color pairs',
  'F1.2.3.1':
      'Feature split: provider architecture scaffolding creates directory structure and exemplar providers — must exist before screen migration (F1.2.3.2) can reference providers',
  'F1.2.3.2':
      'Feature split: screen migration to ConsumerWidget is mechanical once providers exist — three independent screen files parallelizable at 3-agent capacity',
  'F1.3.1.1':
      'Feature split: Android Intent receiver uses AndroidManifest.xml intent-filters and Dart platform channels — platform-isolated from iOS Share Extension in F1.3.1.2',
  'F1.3.1.2':
      'Feature split: iOS Share Extension requires Xcode target creation, App Group configuration, and Swift code — platform-isolated from Android intent handling',
  'F1.3.2.1':
      'Feature split: PDF extraction has unique FFI constraint (pdfrx on main isolate) absent from EPUB/text processing — requires different concurrency strategy',
  'F1.3.2.2':
      'Feature split: EPUB parsing uses dart_epub_viewer with HTML-stripping pipeline — different library, processing model, and chapter-detection logic from PDF or plain text',
  'F1.3.2.3':
      'Feature split: plain text/HTML/Markdown normalisation is a greenfield service — unlike PDF/EPUB cleanup which refactors existing code with known edge cases',
  'F1.3.3.1':
      'Feature split: clipboard detection involves AppLifecycleState observer and platform clipboard API — distinct platform interaction from file system picker in F1.3.3.2',
  'F1.3.3.2':
      'Feature split: local file picker uses file_picker package with MIME type filtering — different platform bridge and user flow from clipboard detection',
  'F1.4.1.1':
      'Feature split: warm-up ramp modifies word_timer.dart timing curve only — isolated from gesture handling code in tap/swipe feature F1.4.1.2',
  'F1.4.1.2':
      'Feature split: tap pause/resume and swipe rewind modify gesture_classifier.dart — isolated from timer arithmetic in warm-up ramp F1.4.1.1',
  'F1.4.2.1':
      'Feature split: sentence mode is a new widget with word-level highlighting and auto-scroll — independent rendering model and widget tree from paragraph mode',
  'F1.4.2.2':
      'Feature split: paragraph mode has timed auto-advance logic absent from sentence mode — requires different timer, progress indicator, and line-spacing strategy',
  'F1.4.2.3':
      'Feature split: mode switching is a coordination layer that depends on both sentence and paragraph mode views existing — cannot implement until F1.4.2.1 and F1.4.2.2 complete',
  'F1.4.3.1':
      'Feature split: adaptive spacing combines a settings provider (settings screen) with a reading ruler overlay (reading screen) — two distinct UI surfaces with independent file scope',
  'F1.4.4.1':
      'Feature split: artifact detection is pure classification logic running in Isolate.run() — no UI dependency, testable in complete isolation from suppression overlay',
  'F1.4.4.2':
      'Feature split: suppression UI requires gesture handling (long-press, range select) and overlay rendering — depends on classification engine output format from F1.4.4.1',
  'F1.5.1.1':
      'Feature split: session tracking combines Isar persistence (data layer model + provider) with dashboard widget (presentation layer) — both co-located in features/stats/',
  'F1.5.2.1':
      'Feature split: store listing content is copywriting and legal documentation — no code changes, distinct from Fastlane CI/CD configuration in F1.5.2.2',
  'F1.5.2.2':
      'Feature split: internal testing setup modifies Fastlane lane definitions for iOS and Android — platform-specific distribution pipeline configs',

  // --- Stories ---
  'S1.1.1.1.1':
      'Story groups 3 tasks across lib/, test/, and pubspec.yaml — same user outcome (no Speedy Boy references) but different file scopes enable parallel execution',
  'S1.1.1.1.2':
      'Story groups 2 platform config tasks (Android, iOS) — same outcome (platform names updated) but platform-isolated files enable parallel execution',
  'S1.1.1.2.1':
      'Single-task story: icon replacement is one design-then-place operation across both platforms — not worth splitting per-platform since assets are generated together',
  'S1.1.2.1.1':
      'Story groups 2 CI workflow tasks (lint+test, release build) — independent YAML files with no shared state, parallelizable by two agents',
  'S1.1.2.2.1':
      'Single-task story: Fastlane setup for both platforms is one coordinated configuration — splitting iOS/Android would create cross-dependency on shared signing conventions',
  'S1.2.1.1.1':
      'Story groups 2 tasks: color token definition and ThemeData factory — tightly coupled by API contract but parallelizable via agreed token interface',
  'S1.2.1.2.1':
      'Story groups 2 tasks: typography Dart code and font asset bundling — different file types (.dart vs .ttf + pubspec.yaml) enable parallel execution',
  'S1.2.1.3.1':
      'Story groups 2 tasks: decoration factories and animation constants — independent design token categories sharing only color token dependency',
  'S1.2.2.1.1':
      'Story groups 2 screen redesign tasks (library, settings) — independent screen files with no shared state enable parallel execution by two agents',
  'S1.2.2.2.1':
      'Story groups 2 screen redesign tasks (reading, analytics) — independent screen files enable parallel execution despite different animation complexity',
  'S1.2.2.3.1':
      'Single-task story: contrast audit is one comprehensive test file covering all theme × color-pair combinations — one test suite, one verification command',
  'S1.2.3.1.1':
      'Story groups 2 provider scaffolding tasks (reading feature, library+settings feature) — independent feature directories enable parallel agent execution',
  'S1.2.3.2.1':
      'Story groups 3 screen migration tasks — independent screen files enable 3-agent parallel execution at maximum concurrent capacity',
  'S1.3.1.1.1':
      'Story groups 2 tasks: Android manifest config and Dart intent handler — tightly coupled platform channel pair but touch different file types (XML vs Dart)',
  'S1.3.1.2.1':
      'Story groups 2 tasks: Xcode target creation then Dart-side reader — sequential dependency (Swift extension must exist before Dart handler can read App Group)',
  'S1.3.2.1.1':
      'Story groups 2 tasks: PDF refactoring and its test file — implementation and verification parallelizable since tests can be written against expected API contract',
  'S1.3.2.2.1':
      'Story groups 2 tasks: EPUB refactoring and its test file — mirrors PDF story pattern, implementation and verification parallelizable',
  'S1.3.2.3.1':
      'Story groups 2 tasks: normaliser implementation then tests — test file depends on implementation API being defined (sequential)',
  'S1.3.3.1.1':
      'Story groups 2 tasks: lifecycle detection provider and UI confirmation widget — logic layer and presentation layer in separate files enable parallel execution',
  'S1.3.3.2.1':
      'Single-task story: file picker integration is a single provider wiring file_picker package output to content routing — not decomposable further',
  'S1.4.1.1.1':
      'Story groups 2 tasks: timer logic implementation and its tests — implementation and test writing parallelizable since test can target expected behavior contract',
  'S1.4.1.2.1':
      'Story groups 2 tasks: tap pause visual feedback and swipe rewind logic — different gesture types modifying different code paths enable parallel execution',
  'S1.4.2.1.1':
      'Single-task story: sentence mode widget is one cohesive UI component — highlight, scroll, and animation are tightly coupled within one widget file',
  'S1.4.2.2.1':
      'Single-task story: paragraph mode widget is one cohesive UI component — timer, progress, and layout are tightly coupled within one widget file',
  'S1.4.2.3.1':
      'Single-task story: mode switcher combines one provider and one widget in tight coordination — splitting would create circular dependency',
  'S1.4.3.1.1':
      'Story groups 2 tasks: spacing settings provider and reading ruler overlay — independent UI surfaces (settings screen vs reading screen) enable parallel execution',
  'S1.4.4.1.1':
      'Story groups 2 tasks: artifact classifier implementation and its test file — implementation and verification parallelizable',
  'S1.4.4.2.1':
      'Single-task story: suppression overlay is one gesture-driven widget — long-press, range select, and visual feedback are tightly coupled in one component',
  'S1.5.1.1.1':
      'Story groups 2 tasks: Isar stats provider (data layer) and dashboard widget (presentation) — independent layers enable parallel execution',
  'S1.5.2.1.1':
      'Story groups 2 tasks: store descriptions and privacy policy — independent documents with no shared content enable parallel writing',
  'S1.5.2.2.1':
      'Story groups 2 tasks: Play Store and TestFlight Fastlane configs — platform-independent lane definitions enable parallel configuration',

  // --- Tasks ---
  'T1.1.1.1.1.1':
      'Atomic: mechanical grep-and-replace across lib/**/*.dart — single operation verifiable by grep returning zero matches',
  'T1.1.1.1.1.2':
      'Atomic: mechanical grep-and-replace across test/**/*.dart — mirrors T1.1.1.1.1.1 in different directory scope, parallelizable',
  'T1.1.1.1.1.3':
      'Atomic: single-file config edit (pubspec.yaml name and description fields) — 15-minute change not worth subdividing',
  'T1.1.1.1.2.1':
      'Atomic: Android platform config files (manifest, build.gradle, strings.xml, settings.gradle) change together as one platform unit',
  'T1.1.1.1.2.2':
      'Atomic: iOS platform config files (Info.plist, project.pbxproj) change together as one platform unit',
  'T1.1.1.2.1.1':
      'Atomic: icon generation and placement is one design-then-copy operation across Android mipmap directories and iOS xcassets — indivisible workflow',
  'T1.1.2.1.1.1':
      'Atomic: single YAML workflow file (.github/workflows/ci.yml) — one CI concern per file, verifiable by file existence and YAML validity',
  'T1.1.2.1.1.2':
      'Atomic: single YAML workflow file (.github/workflows/release-build.yml) — independent trigger pattern from ci.yml, parallelizable',
  'T1.1.2.2.1.1':
      'Atomic: Fastlane config for both platforms is one coordinated setup — splitting iOS/Android Fastlane would duplicate shared Appfile conventions',
  'T1.2.1.1.1.1':
      'Atomic: color token class is one Dart file defining all 4 theme palettes — splitting per-theme would scatter semantically related constants across files',
  'T1.2.1.1.1.2':
      'Atomic: ThemeData factory is one Dart file consuming color tokens — tightly coupled to T1.2.1.1.1.1 token API but parallelizable via agreed interface contract',
  'T1.2.1.2.1.1':
      'Atomic: typography token class is one Dart file with font-family switching — splitting per-style-variant would break the cohesive TextTheme API',
  'T1.2.1.2.1.2':
      'Atomic: font asset placement is one mechanical copy-and-declare operation — Haiku-routed due to zero decision complexity',
  'T1.2.1.3.1.1':
      'Atomic: decoration factory is one Dart file defining shadow/border/radius recipes — depends on color tokens being defined, single-file output',
  'T1.2.1.3.1.2':
      'Atomic: animation constants is one Dart file defining duration/curve pairs with reduced-motion variants — independent from decoration factory file',
  'T1.2.2.1.1.1':
      'Atomic: library_screen.dart redesign applies tokens to one screen file — parallelizable with other screen redesigns due to independent file scope',
  'T1.2.2.1.1.2':
      'Atomic: settings_screen.dart redesign applies tokens to one screen file — parallelizable with library screen redesign',
  'T1.2.2.2.1.1':
      'Atomic: reading_screen.dart redesign requires animation integration (slow-eased fades, reduced-motion checks) — higher complexity justified by 4-hour estimate',
  'T1.2.2.2.1.2':
      'Atomic: analytics_screen.dart redesign applies tokens to one screen file — parallelizable with reading screen redesign',
  'T1.2.2.3.1.1':
      'Atomic: contrast audit is one test file asserting WCAG ratios across all 4 theme × color-pair combinations — single verification artifact',
  'T1.2.3.1.1.1':
      'Atomic: reading feature provider scaffolding creates one directory and one exemplar @riverpod provider — establishes pattern for other features',
  'T1.2.3.1.1.2':
      'Atomic: library + settings provider scaffolding creates two directories with theme and font providers — parallelizable with reading provider setup',
  'T1.2.3.2.1.1':
      'Atomic: library_screen.dart migration is one file converting StatefulWidget → ConsumerWidget — parallelizable with other screen migrations',
  'T1.2.3.2.1.2':
      'Atomic: settings_screen.dart migration is one file converting StatefulWidget → ConsumerWidget — parallelizable with library and analytics',
  'T1.2.3.2.1.3':
      'Atomic: analytics_screen.dart migration is one file converting StatefulWidget → ConsumerWidget — parallelizable with library and settings',
  'T1.3.1.1.1.1':
      'Atomic: AndroidManifest.xml intent-filter addition is one XML config edit — verifiable by grep for ACTION_SEND string',
  'T1.3.1.1.1.2':
      'Atomic: Dart-side share intent provider is one new file creating @riverpod annotated provider with platform channel — parallelizable with manifest config',
  'T1.3.1.2.1.1':
      'Atomic: iOS Share Extension target creation is one Xcode project operation producing ShareViewController.swift and project.pbxproj changes — indivisible',
  'T1.3.1.2.1.2':
      'Atomic: Dart-side iOS handler extends existing share_intent_provider.dart to read from App Group — depends on extension target existing first',
  'T1.3.2.1.1.1':
      'Atomic: pdf_extractor.dart refactoring adds progress stream and error handling to one existing file — splitting would create merge conflicts in shared extraction function',
  'T1.3.2.1.1.2':
      'Atomic: PDF extraction test file covers all edge cases in one test suite — parallelizable with implementation refactor via expected API contract',
  'T1.3.2.2.1.1':
      'Atomic: epub_extractor.dart refactoring adds chapter detection and progress to one existing file — mirrors PDF refactor pattern in different extractor',
  'T1.3.2.2.1.2':
      'Atomic: EPUB extraction test file covers edge cases in one test suite — parallelizable with implementation refactor',
  'T1.3.2.3.1.1':
      'Atomic: content normaliser is one new Dart file with HTML/Markdown stripping logic — greenfield single-file creation with no merge risk',
  'T1.3.2.3.1.2':
      'Atomic: normaliser test file depends on implementation API being defined — sequential dependency on T1.3.2.3.1.1 output',
  'T1.3.3.1.1.1':
      'Atomic: clipboard detection provider is one file with AppLifecycleState observer — parallelizable with prompt widget due to independent file scope',
  'T1.3.3.1.1.2':
      'Atomic: clipboard prompt widget is one UI component file — parallelizable with detection provider, consumes provider via ref.watch',
  'T1.3.3.2.1.1':
      'Atomic: file picker provider is one file wiring file_picker package to content routing — single integration point, not decomposable',
  'T1.4.1.1.1.1':
      'Atomic: warm-up ramp adds timing curve calculation to word_timer.dart — modifies one existing file, verifiable by existing test suite plus new tests',
  'T1.4.1.1.1.2':
      'Atomic: warm-up ramp tests extend existing word_timer_test.dart — parallelizable with implementation via behavior contract',
  'T1.4.1.2.1.1':
      'Atomic: tap pause visual feedback modifies reading_screen.dart — one screen file change adding icon + semantic label for pause state',
  'T1.4.1.2.1.2':
      'Atomic: swipe rewind modifies gesture_classifier.dart and sentence_resolver.dart — tightly coupled files that change together for rewind logic',
  'T1.4.2.1.1.1':
      'Atomic: sentence mode is one new widget file combining highlight, auto-scroll, and animation — 4-hour estimate reflects animation complexity, not decomposable',
  'T1.4.2.2.1.1':
      'Atomic: paragraph mode is one new widget file combining timed advance, progress indicator, and line spacing — independent rendering model from sentence mode',
  'T1.4.2.3.1.1':
      'Atomic: mode switcher combines one provider file and one widget file — tightly coupled pair that must be implemented together to avoid orphan state',
  'T1.4.3.1.1.1':
      'Atomic: spacing provider is one file with slider state and SharedPreferences persistence — parallelizable with reading ruler overlay',
  'T1.4.3.1.1.2':
      'Atomic: reading ruler is one overlay widget file — parallelizable with spacing provider, consumes spacing values via ref.watch',
  'T1.4.4.1.1.1':
      'Atomic: artifact classifier is one new Dart file with pattern-matching logic wrapped in Isolate.run() — pure function, testable without UI',
  'T1.4.4.1.1.2':
      'Atomic: classifier test file covers table/code/figure detection patterns — parallelizable with implementation via expected classification contract',
  'T1.4.4.2.1.1':
      'Atomic: suppression overlay combines gesture handler and visual feedback in one widget — tightly coupled long-press + range-select interaction, not decomposable',
  'T1.5.1.1.1.1':
      'Atomic: session stats provider with Isar ReadingSession model is one provider + one model file — tightly coupled data layer pair changing together',
  'T1.5.1.1.1.2':
      'Atomic: stats dashboard widget is one file rendering aggregated session data — parallelizable with provider creation via agreed data model',
  'T1.5.2.1.1.1':
      'Atomic: store descriptions are one copywriting deliverable per platform — parallelizable with privacy policy, no code dependency',
  'T1.5.2.1.1.2':
      'Atomic: privacy policy is one legal document reflecting on-device-only data handling — parallelizable with store descriptions',
  'T1.5.2.2.1.1':
      'Atomic: Play Store Fastlane internal lane is one config addition to android/fastlane/Fastfile — parallelizable with iOS TestFlight config',
  'T1.5.2.2.1.2':
      'Atomic: TestFlight Fastlane beta lane is one config addition to ios/fastlane/Fastfile — parallelizable with Android Play Store config',
};

// Counters
int verificationFixCount = 0;
int rationaleAddCount = 0;
int ethicalBlockerCount = 0;

void main() {
  final file = File('doc/runthru-backlog.json');
  if (!file.existsSync()) {
    print('ERROR: doc/runthru-backlog.json not found');
    exit(1);
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final releases = json['releases'] as List;

  for (final release in releases) {
    processRelease(release as Map<String, dynamic>);
  }

  // Write with 2-space indent
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(json)}\n');

  // Summary
  print('=== Backlog transformation complete ===');
  print('  Verification commands fixed: $verificationFixCount');
  print('  Granularity rationales added: $rationaleAddCount');
  print('  Ethical blockers added: $ethicalBlockerCount');

  // Verify all nodes got rationale
  final missing = <String>[];
  _collectMissingRationale(json, missing);
  if (missing.isNotEmpty) {
    print('  WARNING: ${missing.length} nodes missing granularity_rationale:');
    for (final id in missing) {
      print('    - $id');
    }
  } else {
    print('  All nodes have granularity_rationale: YES');
  }
}

// ──────────────────────────────────────────────
// Tree walkers
// ──────────────────────────────────────────────
void processRelease(Map<String, dynamic> release) {
  final id = release['id'] as String;

  // Fix R3 weeks
  if (id == 'R3') {
    release['weeks'] = '14-18';
    print('  Fixed R3 weeks: 13-17 → 14-18');
  }

  _addRationale(release);

  // R1 has milestones
  if (release.containsKey('milestones')) {
    for (final ms in release['milestones'] as List) {
      processMilestone(ms as Map<String, dynamic>);
    }
  }

  // R2/R3 have epics directly (epic-level only)
  if (release.containsKey('epics') && !release.containsKey('milestones')) {
    for (final epic in release['epics'] as List) {
      final e = epic as Map<String, dynamic>;
      _addRationale(e);
    }
  }
}

void processMilestone(Map<String, dynamic> ms) {
  _addRationale(ms);
  for (final epic in ms['epics'] as List) {
    processEpic(epic as Map<String, dynamic>);
  }
}

void processEpic(Map<String, dynamic> epic) {
  final id = epic['id'] as String;

  // Ensure E1.3.2 depends_on includes E1.3.1
  if (id == 'E1.3.2') {
    final deps = epic['depends_on'] as List;
    if (!deps.contains('E1.3.1')) {
      deps.add('E1.3.1');
      print('  Fixed E1.3.2 depends_on: added E1.3.1');
    } else {
      print('  E1.3.2 depends_on already includes E1.3.1 (no change needed)');
    }
  }

  // Add ethical_blockers to accessibility-adjacent epics
  if (id == 'E1.2.1') {
    _ensureEthicalBlocker(
      epic,
      'accessibility',
      'Accessibility features (OpenDyslexic font, CVD-safe themes, font size controls) are NEVER paywalled — free forever per ethical commitment',
    );
  }
  if (id == 'E1.4.3') {
    _ensureEthicalBlocker(
      epic,
      'accessibility',
      'Accessibility features (adaptive letter/word spacing, reading ruler, focus line) are NEVER paywalled — free forever per ethical commitment',
    );
  }
  if (id == 'E1.5.1') {
    _ensureEthicalBlocker(
      epic,
      'privacy',
      'All analytics data stored on-device only — no cloud upload without explicit per-session opt-in',
    );
  }

  _addRationale(epic);

  if (epic.containsKey('features')) {
    for (final feature in epic['features'] as List) {
      if (feature is Map<String, dynamic>) {
        processFeature(feature);
      }
    }
  }
}

void processFeature(Map<String, dynamic> feature) {
  _addRationale(feature);
  if (feature.containsKey('stories')) {
    for (final story in feature['stories'] as List) {
      processStory(story as Map<String, dynamic>);
    }
  }
}

void processStory(Map<String, dynamic> story) {
  _addRationale(story);
  if (story.containsKey('tasks')) {
    for (final task in story['tasks'] as List) {
      processTask(task as Map<String, dynamic>);
    }
  }
}

void processTask(Map<String, dynamic> task) {
  // Fix verification commands
  if (task.containsKey('verification_command')) {
    final cmd = task['verification_command'] as String;
    if (verificationFixes.containsKey(cmd)) {
      task['verification_command'] = verificationFixes[cmd];
      verificationFixCount++;
    }
  }
  _addRationale(task);
}

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────
void _addRationale(Map<String, dynamic> node) {
  if (node.containsKey('granularity_rationale')) return;
  final id = node['id'] as String?;
  if (id == null) return;

  final text = rationales[id];
  if (text != null) {
    node['granularity_rationale'] = text;
    rationaleAddCount++;
  } else {
    // Fallback — should not happen if rationales map is complete
    print('  WARNING: No rationale defined for $id');
    node['granularity_rationale'] = 'MISSING — add rationale for $id';
    rationaleAddCount++;
  }
}

void _ensureEthicalBlocker(
  Map<String, dynamic> node,
  String type,
  String rule,
) {
  if (!node.containsKey('ethical_blockers')) {
    node['ethical_blockers'] = <Map<String, dynamic>>[];
  }
  final blockers = node['ethical_blockers'] as List;
  final exists = blockers.any(
    (b) => b is Map<String, dynamic> && b['type'] == type,
  );
  if (!exists) {
    blockers.add(<String, dynamic>{
      'type': type,
      'rule': rule,
      'blocker': true,
    });
    ethicalBlockerCount++;
  }
}

/// Walk entire tree to find nodes missing granularity_rationale
void _collectMissingRationale(dynamic node, List<String> missing) {
  if (node is Map<String, dynamic>) {
    if (node.containsKey('id') && !node.containsKey('granularity_rationale')) {
      missing.add(node['id'] as String);
    }
    for (final value in node.values) {
      _collectMissingRationale(value, missing);
    }
  } else if (node is List) {
    for (final item in node) {
      _collectMissingRationale(item, missing);
    }
  }
}
