You are an expert Flutter/Dart engineer working inside this existing Flutter app.

Goal:
Apply real sensor-driven “magic window” parallax to two specific places:

1. The pause screen / pause overlay
2. The paywalled Parallax Reading Mode

The effect should feel like Apple iOS 3D Photos or Facebook/Meta 3D Photos: when the user moves the device, the scene subtly follows the viewer’s eye and reveals depth. Do not implement this as a simple flat-card tilt only.

Project context:
The app already contains a 3D/parallax reading architecture, including files such as:

- `lib/screens/parallax_reading_screen.dart`
- `lib/widgets/pause_fog_3d.dart`
- `lib/three_d/parallax_room.dart`
- `lib/three_d/parallax_room_painter.dart`
- `lib/three_d/off_axis_projection.dart`
- `lib/services/device_capability.dart`
- `lib/store/config.dart`

The repo also describes the app as having optional pointer/IMU-driven “magic window” parallax using mobile gyro/IMU and desktop pointer fallback. :contentReference[oaicite:0]{index=0}

Task:
Implement a reusable motion-parallax input system and wire it specifically into:

- the pause overlay in `pause_fog_3d.dart`
- the paywalled parallax reading screen in `parallax_reading_screen.dart`

Do not apply the effect globally across the app.

Core behavior:
Create a motion controller that outputs normalized viewer/head position:

- `headX`: `-1.0..1.0`
- `headY`: `-1.0..1.0`
- `isAvailable`
- `isCalibrated`
- `source`: `sensor`, `pointer`, or `static`

Use this model to drive off-axis projection, fog depth, layered movement, and/or existing 3D room rendering.

Implementation requirements:

1. Add motion sensor support
   - Use `sensors_plus` unless the project already has a better sensor package.
   - Listen to gyroscope and/or accelerometer streams on iOS/Android.
   - Use pointer/mouse position as fallback on desktop.
   - Use centered static fallback on unsupported platforms, simulator, web, or unavailable sensors.
   - Do not crash if sensors fail.

2. Create reusable motion state
   - Add a model such as `HeadPosition`.
   - Add a Riverpod controller such as `motionParallaxControllerProvider`.
   - Avoid `setState()` for shared motion state.
   - Start sensor subscriptions only when the pause overlay or parallax reading screen is active.
   - Cancel all subscriptions on dispose.

3. Add calibration
   - On entry to pause screen and parallax reading mode, treat the current device orientation as neutral center.
   - Add a `recalibrate()` method.
   - Ensure the first few sensor frames do not jump the UI.

4. Add smoothing
   - Use exponential smoothing / low-pass filtering.
   - Add a small dead zone to remove micro-jitter.
   - Clamp values to `-1.0..1.0`.
   - Avoid noisy motion at rest.

Suggested defaults:
   - smoothing alpha: `0.12`
   - dead zone: `0.025`
   - max subtle displacement: `2.5%` of viewport
   - max full displacement: `5%` of viewport

5. Respect reduced motion
   - If `isReducedMotion(context)` is true, disable sensor tracking.
   - Render the pause screen and parallax reading mode in static centered mode.
   - Do not hide any accessibility-related settings behind the parallax paywall.

6. Add intensity modes
   - `off`
   - `subtle`
   - `full`

The paywalled Parallax Reading Mode should use `subtle` or `full`.
The pause screen should default to `subtle`.

7. Pause screen integration
   - Modify `lib/widgets/pause_fog_3d.dart`.
   - Make the fog, depth layers, highlights, and background surfaces respond to `headX/headY`.
   - The paused word/text should remain readable and not drift excessively.
   - The pause effect should feel like a suspended 3D room, not a rotating card.
   - Keep motion calm and neurodivergent-friendly.

8. Paywalled parallax reading mode integration
   - Modify `lib/screens/parallax_reading_screen.dart`.
   - Wire `headX/headY` into the existing parallax room / off-axis projection system.
   - Preserve the current premium gate behavior.
   - Do not accidentally make non-premium reading unusable.
   - The paid Parallax Reading Mode should visibly gain sensor-driven depth.
   - If premium is not active, continue showing the existing guard/paywall.
   - If premium is active but sensors are unavailable, show the static parallax renderer.

9. Performance requirements
   - Avoid rebuilding the entire reading screen on every sensor event.
   - Prefer repaint notifiers, selected Riverpod values, or painter-level updates.
   - Keep paint operations allocation-light.
   - Maintain 60 FPS target.
   - Do not do heavy computation in `paint()`.

10. Testing requirements
Add or update tests for:

   - smoothing behavior
   - clamping behavior
   - dead zone behavior
   - calibration neutralizes current orientation
   - reduced motion disables sensor motion
   - pause screen renders with static fallback
   - parallax reading mode uses static fallback when sensors are unavailable
   - premium gate behavior remains unchanged

Files to inspect before coding:
- `pubspec.yaml`
- `lib/widgets/pause_fog_3d.dart`
- `lib/screens/parallax_reading_screen.dart`
- `lib/three_d/parallax_room.dart`
- `lib/three_d/parallax_room_painter.dart`
- `lib/three_d/off_axis_projection.dart`
- `lib/services/device_capability.dart`
- `lib/store/config.dart`
- `lib/store/models.dart`
- `test/widgets/pause_fog_3d_test.dart`
- `test/screens/parallax_intensity_test.dart`

Suggested new files:
- `lib/core/head_position.dart`
- `lib/core/motion_parallax_controller.dart`
- `test/core/motion_parallax_controller_test.dart`

Acceptance criteria:
- Opening the pause overlay on a real phone shows subtle sensor-reactive depth.
- Opening paid Parallax Reading Mode shows stronger sensor-reactive 3D room movement.
- The motion follows the viewer’s eye rather than just tilting a flat widget.
- Current device orientation is calibrated as neutral.
- Motion is smooth, clamped, and calm.
- Reduced motion renders static UI.
- Non-premium users still see the existing paywall behavior.
- Sensors unavailable equals graceful static fallback.
- Tests pass.
- `dart analyze --fatal-infos` passes.
- `flutter test` passes.

Before coding:
Explain the architecture briefly and list the files you will touch.

After coding:
Return:
- changed files
- summary of implementation
- commands run
- test results
- limitations, especially any difference between true depth-map 3D photos and the existing 3D room/parallax simulation
