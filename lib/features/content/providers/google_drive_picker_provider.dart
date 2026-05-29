/// Provider for the Drive-aware selected-file picker.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/features/content/services/google_drive_picker.dart';

/// Drive selected-file picker dependency.
final googleDrivePickerProvider = Provider<GoogleDrivePicker>((ref) {
  return const UnavailableGoogleDrivePicker();
});
