# Speedy Boy v5.0 — Design Specification & Task Backlog

**Version**: 5.0.0
**Date**: 2026-04-05
**Status**: Draft
**Type**: Removal release — no new features, pure subtraction

---

## Design Philosophy

v5 removes the Discover screen, OPDS catalog service, and all book download infrastructure. The app becomes a focused reading tool: bring your own content (local files + clipboard). Fewer features, smaller binary, less surface area to maintain.

---

## What's Being Removed

| Component | Why |
|-----------|-----|
| Discover screen (bottom nav tab) | Not part of the core RSVP reading value proposition |
| OPDS catalog service | Only existed to feed the Discover screen |
| Book download/import from OPDS | Depends on OPDS service |
| Bottom navigation bar | With Discover gone, Library is the only destination — no nav bar needed |
| Any OPDS-related models, providers, tests | Dead code after removal |

## What Stays

| Component | Notes |
|-----------|-------|
| Library screen | Becomes the app's home screen (direct launch) |
| PDF folder browsing | Local file access unchanged |
| Clipboard reading (v4) | Unaffected |
| Settings screen | Accessed from Library, unchanged |
| Reading viewport | Unchanged |
| All v4 features | Unchanged |

---

## Priority 1: Remove OPDS Service Layer

### Files to Delete
```
lib/services/opds_service.dart        (or wherever the OPDS fetch/parse logic lives)
lib/models/opds_entry.dart            (OPDS catalog entry model, if separate)
lib/models/opds_feed.dart             (OPDS feed model, if separate)
test/services/opds_service_test.dart   (OPDS tests)
```

### Action
- Delete all OPDS-related service files
- Delete all OPDS-related model files
- Delete all OPDS-related test files
- Search lib/ for any remaining imports of deleted files and remove them
- Remove any OPDS-related dependencies from `pubspec.yaml` (e.g., XML parsing libraries used only for OPDS, HTTP clients used only for catalog fetching)

### Do / Don't

| Do | Don't |
|----|-------|
| Delete all OPDS files | Leave dead files "for later" |
| Remove unused pubspec dependencies | Remove HTTP/XML packages that other features use |
| Search for orphaned imports | Assume deleting files is enough |

---

## Priority 2: Remove Discover Screen

### Files to Delete
```
lib/screens/discover_screen.dart      (the Discover tab screen)
lib/widgets/discover_*.dart           (any Discover-specific widgets: book cards, catalog list, etc.)
test/screens/discover_screen_test.dart
test/widgets/discover_*_test.dart
```

### Action
- Delete the Discover screen file
- Delete any widgets only used by the Discover screen
- Delete associated tests
- Search for orphaned imports

---

## Priority 3: Remove Bottom Navigation & Update Routing

### Current State
App has a bottom navigation bar with at least 2 tabs (Library, Discover). With Discover removed, only Library remains.

### v5 Design
- **Remove the bottom navigation bar entirely** — a single-tab nav bar is pointless
- **Library screen becomes the app's root** — launches directly on app start
- **Settings access**: from an icon/button on the Library screen (should already exist)
- Update `go_router` configuration to remove the Discover route and any shell route wrapping the bottom nav

### Files to Modify
```
lib/router.dart (or wherever go_router is configured)
lib/screens/shell_screen.dart (or whatever wraps the bottom nav — may be called main_screen, app_shell, etc.)
```

### Action
1. Find the shell/scaffold widget that contains the bottom NavigationBar
2. Remove the NavigationBar widget entirely
3. Remove the Discover route from go_router
4. Set Library screen as the root route (if not already)
5. If the shell widget ONLY existed to hold the nav bar, delete it and route directly to Library
6. If the shell widget provides other structure (app bar, safe area), keep it but remove the nav bar
7. Verify settings is still accessible from Library screen

### Do / Don't

| Do | Don't |
|----|-------|
| Remove the entire bottom nav bar | Leave a single-tab nav bar |
| Route directly to Library as root | Add a splash screen or redirect |
| Keep settings accessible from Library | Orphan the settings screen |

---

## Priority 4: Remove OPDS Providers

### Action
- Search lib/ for any Riverpod providers related to OPDS:
  - Catalog fetch provider
  - OPDS entry list provider
  - Book download provider
  - Any "discover" named providers
- Delete the provider definitions
- Remove any `ref.watch()` or `ref.read()` calls to deleted providers
- If providers are in a shared file, remove only the OPDS-related ones

---

## Priority 5: Dependency Cleanup

### Action
- Run `flutter pub deps` and identify packages used ONLY by OPDS/Discover:
  - XML parsing (e.g., `xml`, `xml2json`) — if only used for OPDS feed parsing
  - HTTP client — likely shared, do NOT remove
  - Image caching for book covers — if only used for OPDS thumbnails
- Remove unused packages from `pubspec.yaml`
- Run `flutter pub get` to verify clean dependency resolution

---

## Priority 6: Verify & Clean

### Action
- `dart analyze lib/` → zero issues
- `flutter test` → all pass
- `grep -r "opds\|OPDS\|discover\|Discover" lib/ test/` → zero results (case-insensitive)
- `grep -r "opds\|OPDS\|discover\|Discover" pubspec.yaml` → zero results
- Build and run on Android emulator:
  - App launches directly to Library screen
  - No bottom navigation bar visible
  - Settings accessible from Library
  - All reading features work (PDF, clipboard, gestures, WPM dial)
  - No crash or orphaned navigation

---

## Task Backlog

### TASK-200: Audit OPDS surface area
- **Priority**: 0 (prerequisite)
- **Files**: All lib/ and test/
- **Action**: Search codebase for all files containing "opds", "OPDS", "discover", "Discover", "catalog", "CatalogEntry", "OpdsFeed", "fetchCatalog". Produce a complete list of files to delete and files to modify. This is investigation only — no code changes.
- **Acceptance criteria**:
  - [ ] Complete list of files to DELETE
  - [ ] Complete list of files to MODIFY (with what to remove from each)
  - [ ] List of pubspec dependencies to evaluate for removal
- **Effort**: S (~20 min)
- **Depends on**: Nothing

---

### TASK-201: Delete OPDS service and model files
- **Priority**: 1
- **Files**: Per TASK-200 audit
- **Action**: Delete all OPDS service files, model files, and their tests.
- **Acceptance criteria**:
  - [ ] All OPDS service files deleted
  - [ ] All OPDS model files deleted
  - [ ] All OPDS test files deleted
- **Effort**: XS (~10 min)
- **Depends on**: TASK-200

---

### TASK-202: Delete Discover screen and widgets
- **Priority**: 2
- **Files**: Per TASK-200 audit
- **Action**: Delete the Discover screen, any Discover-specific widgets, and their tests.
- **Acceptance criteria**:
  - [ ] Discover screen file deleted
  - [ ] All Discover-only widget files deleted
  - [ ] All Discover test files deleted
- **Effort**: XS (~10 min)
- **Depends on**: TASK-200

---

### TASK-203: Remove bottom navigation bar
- **Priority**: 3
- **Files**: Shell/scaffold widget, router config
- **Action**: Remove the bottom NavigationBar widget. If the shell widget only existed for the nav bar, delete the shell and route directly to Library. If the shell provides other structure, keep it minus the nav bar.
- **Acceptance criteria**:
  - [ ] No bottom navigation bar visible
  - [ ] App launches directly to Library screen
  - [ ] No single-tab nav bar remnant
- **Effort**: S (~20 min)
- **Depends on**: TASK-202

---

### TASK-204: Update go_router — remove Discover route
- **Priority**: 3
- **Files**: Router configuration file
- **Action**: Remove the Discover route. Remove any ShellRoute that existed solely to wrap Library + Discover in a nav bar scaffold. Set Library as the root route. Verify settings route still works.
- **Acceptance criteria**:
  - [ ] No Discover route in router
  - [ ] Library is root route (/)
  - [ ] Settings route works
  - [ ] Reading viewport route works
  - [ ] No orphaned routes
- **Effort**: S (~20 min)
- **Depends on**: TASK-203

---

### TASK-205: Remove OPDS providers
- **Priority**: 4
- **Files**: Provider files (per TASK-200 audit)
- **Action**: Delete OPDS-related Riverpod providers. Remove any ref.watch/ref.read calls to deleted providers from remaining code.
- **Acceptance criteria**:
  - [ ] No OPDS providers in lib/
  - [ ] No references to deleted providers
  - [ ] `dart analyze lib/` passes
- **Effort**: S (~15 min)
- **Depends on**: TASK-201

---

### TASK-206: Remove orphaned imports
- **Priority**: 4
- **Files**: All lib/
- **Action**: Run `dart analyze lib/` — fix all "unused import" warnings from deleted files. Search for any remaining string references to "opds", "discover", "catalog" in lib/.
- **Acceptance criteria**:
  - [ ] Zero unused import warnings
  - [ ] Zero string references to removed features
- **Effort**: S (~15 min)
- **Depends on**: TASK-201, TASK-202, TASK-205

---

### TASK-207: Clean pubspec dependencies
- **Priority**: 5
- **Files**: `pubspec.yaml`
- **Action**: Identify and remove packages used only by OPDS/Discover. Run `flutter pub get` to verify. Do NOT remove packages used by other features.
- **Acceptance criteria**:
  - [ ] No OPDS-only packages in pubspec.yaml
  - [ ] `flutter pub get` succeeds
  - [ ] No runtime errors from missing packages
- **Effort**: S (~15 min)
- **Depends on**: TASK-206

---

### TASK-208: Final verification
- **Priority**: 6
- **Files**: All
- **Action**:
  ```bash
  dart analyze lib/
  flutter test
  grep -ri "opds\|discover\|catalog" lib/ test/ pubspec.yaml
  ```
  All must return clean. Build and run on Android emulator. Verify:
  - App launches to Library
  - No bottom nav
  - Settings accessible
  - PDF reading works
  - Clipboard reading works
  - All v4 gestures work
- **Acceptance criteria**:
  - [ ] `dart analyze lib/` → zero issues
  - [ ] `flutter test` → all pass
  - [ ] grep returns zero results
  - [ ] App runs clean on Android emulator
- **Effort**: S (~20 min)
- **Depends on**: TASK-207

---

## Dependency Graph

```
TASK-200 (audit) ──┬── TASK-201 (delete OPDS service) ── TASK-205 (delete providers)
                   ├── TASK-202 (delete Discover screen) ── TASK-203 (remove nav bar)
                   │                                            └── TASK-204 (update router)
                   └── All ── TASK-206 (orphaned imports) ── TASK-207 (pubspec) ── TASK-208 (verify)
```

## Effort Distribution

- XS: 2 tasks
- S: 7 tasks
- **Total tasks**: 9
- **Estimated total**: ~2.5 hours

This is a single-session job. The entire v5 can be done in one Agent mode pass.

---

## Autopilot Prompt (Single Sprint)

Paste this into Copilot Agent mode to execute the entire v5 in one pass:

```
Execute the Speedy Boy v5 release: remove ALL OPDS and Discover functionality.
Read docs/v5-design-spec.md for full context.

This is a REMOVAL release. No new features. Pure deletion and cleanup.

PHASE 1 — AUDIT (do this first, report findings before proceeding):
Search the entire codebase for all files containing "opds", "OPDS", "discover",
"Discover", "catalog", "CatalogEntry", "OpdsFeed", "fetchCatalog".
List every file that needs to be DELETED and every file that needs to be MODIFIED.
Check pubspec.yaml for packages used only by OPDS (XML parsing, etc).

PHASE 2 — DELETE:
Delete all OPDS service files, model files, and tests.
Delete the Discover screen, its widgets, and tests.
Delete all OPDS-related Riverpod providers.

PHASE 3 — NAVIGATION:
Remove the bottom NavigationBar from the shell/scaffold widget.
If the shell widget ONLY existed for the nav bar, delete it entirely.
Update go_router: remove Discover route, remove any ShellRoute that
wrapped Library+Discover, set Library screen as root route (/).
Verify settings and reading viewport routes still work.

PHASE 4 — CLEANUP:
Run dart analyze lib/ — fix all unused import warnings.
Search for any remaining string references to removed features.
Check pubspec.yaml — remove packages used ONLY by OPDS/Discover.
Do NOT remove packages shared with other features (e.g., http client).
Run flutter pub get to verify.

PHASE 5 — VERIFY:
Run: dart analyze lib/
Run: flutter test
Run: grep -ri "opds\|discover\|catalog" lib/ test/ pubspec.yaml
All must return clean.

RULES:
- Rule 14: go_router for navigation
- Rule 10: update barrel exports if any design system files affected
- Rule 13: Riverpod — clean up any provider references
- Do NOT touch any reading viewport, gesture, or v4 feature code
- Do NOT add any new features — this is pure removal

Report the final status of all 3 verification commands.
```
