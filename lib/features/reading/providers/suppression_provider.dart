import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:runthru/features/content/services/artifact_classifier.dart';

part 'suppression_provider.g.dart';

/// State for artifact suppression — tracks detected regions and user suppressions.
class SuppressionState {
  /// Creates a suppression state with optional regions and suppressed indices.
  const SuppressionState({
    this.regions = const [],
    this.suppressedIndices = const {},
  });

  /// Artifact regions detected by the classifier.
  final List<ArtifactRegion> regions;

  /// Set of word indices the user has marked for suppression (skipping).
  final Set<int> suppressedIndices;

  /// Whether a word at [index] should be skipped during reading.
  bool isSuppressed(int index) => suppressedIndices.contains(index);

  /// Create a copy with modified fields.
  SuppressionState copyWith({
    List<ArtifactRegion>? regions,
    Set<int>? suppressedIndices,
  }) {
    return SuppressionState(
      regions: regions ?? this.regions,
      suppressedIndices: suppressedIndices ?? this.suppressedIndices,
    );
  }
}

/// Manages artifact detection results and user suppression toggles.
/// Auto-disposed when the reading screen unmounts.
@riverpod
class SuppressionNotifier extends _$SuppressionNotifier {
  @override
  SuppressionState build() => const SuppressionState();

  /// Set detected artifact regions (called after classification completes).
  void setRegions(List<ArtifactRegion> regions) {
    state = state.copyWith(regions: regions);
  }

  /// Toggle suppression on all words in a region.
  void toggleRegion(ArtifactRegion region) {
    final indices = Set<int>.from(state.suppressedIndices);
    final regionIndices = List.generate(
      region.length,
      (i) => region.startIndex + i,
    );

    // If any word in the region is already suppressed, unsuppress all
    if (regionIndices.any(indices.contains)) {
      indices.removeAll(regionIndices);
    } else {
      indices.addAll(regionIndices);
    }

    state = state.copyWith(suppressedIndices: indices);
  }

  /// Clear all suppressions (e.g., when loading a new document).
  void clear() {
    state = const SuppressionState();
  }
}
