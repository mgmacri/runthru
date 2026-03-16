# Speedy Boy — Copilot Instructions (Dart/Flutter)

You are an expert Flutter/Dart developer building **Speedy Boy v2.0**, a speed reading app with a **3D neumorphic cube viewport** and optional **stereoscopic head-tracking**.

## Absolute Rules — NEVER Violate

1. **No raw hex Color()** in widget code. All colors MUST use `SpeedyBoyTokens.tokenName` from `lib/design/tokens.dart`. The ONLY file with `Color(0xFF...)` is `tokens.dart`.
2. **No hardcoded TextStyle** in widget files. All styles from `SpeedyBoyTypography` in `lib/design/typography.dart`.
3. **No hardcoded BoxDecoration shadows** in widgets. Use `SpeedyBoyDecorations.raisedDecoration(surface, size)` or `.insetDecoration(...)`.
4. **No hardcoded 3D material constants.** Use `SpeedyBoyMaterials` from `lib/design/materials.dart`.
5. **Every animation** must check `isReducedMotion(context)` and apply the reduced-motion override.
6. **Stereoscopic is always optional.** Every code path involving camera/head-tracking must have graceful fallback.
7. **Two surface worlds** — NEVER mix `stage*` tokens on shell surfaces or vice versa.
8. **Bricolage Grotesque for shell UI.** Reading stage font is user-selectable (default Bricolage Grotesque). See `SpeedyBoyTypography.availableFonts` for the canonical list.
9. **TextPainter pool** (max 3) for 3D word rendering. Never allocate TextPainters in `paint()`.
10. **All imports from design system** go through `lib/design/design.dart` barrel export.
11. **Heavy computation in Isolates.** PDF extraction, cache I/O — never on the main isolate's event loop.
12. **Dart naming conventions.** `lowerCamelCase` for variables/functions, `UpperCamelCase` for classes, `snake_case` for file names.
13. **Riverpod for state.** No raw setState() for global/shared state.
14. **go_router for navigation.** No Navigator.push() calls.
15. **No raw Material loading widgets.** Never use CircularProgressIndicator, LinearProgressIndicator, or RefreshIndicator. Use the SpeedyBoy design system loading states (neumorphic pulse, ripple overlay, or styled text).
16. **CI build number is auto-managed.** Never manually set the +N build number in pubspec.yaml for release builds. Codemagic auto-increments it. For local development builds, the +N value is ignored.
17. **No deprecated Flutter APIs.** Prefer ListenableBuilder over AnimatedBuilder. When Flutter deprecates an API, migrate promptly.

## Quarterly Maintenance Checklist
- [ ] Run `dart analyze lib/` with zero warnings
- [ ] Run `flutter test` with zero failures
- [ ] Search pubspec.yaml dependencies for unused packages (zero imports in lib/)
- [ ] Search assets/ for unreferenced files
- [ ] Verify all text colors respect surface world boundaries (rule 7)
- [ ] Verify all animations check isReducedMotion (rule 5)
- [ ] Bump minimum Flutter SDK if deprecated APIs have been migrated
