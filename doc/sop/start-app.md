Yes, if emulator-5554 is already running, this should work:

  flutter run -d emulator-5554 --dart-define-from-file=dart_defines/development.json

  Drop the trailing --; it is only for passing app arguments after Flutter’s options.

  The GPU part is controlled when the emulator starts, not by flutter run. flutter emulators --launch
  runthru_api36 uses the AVD defaults, and your AVD config currently has GPU disabled/auto-ish. To force host GPU
  like the old script did, start the emulator with the Android emulator CLI, then use normal Flutter:

  emulator -avd runthru_api36 -gpu host
  flutter run -d emulator-5554 --dart-define-from-file=dart_defines/development.json

  If snapshots are causing bad boots, use the old script’s boot style:

  emulator -avd runthru_api36 -gpu host -no-snapshot

  I also checked ADB: emulator-5554 is attached right now, so the flutter run -d emulator-5554 ... command should
  target it.
