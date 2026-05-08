import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/services/artifact_classifier.dart';

/// Overlay that shows detected artifact regions during paused reading.
///
/// Users can tap a region to toggle suppression (skip during reading).
/// Only visible when reading is paused — never during active RSVP.
class SuppressionOverlay extends StatelessWidget {
  /// Creates a suppression overlay panel.
  const SuppressionOverlay({
    super.key,
    required this.isPaused,
    required this.words,
    required this.regions,
    required this.suppressedIndices,
    required this.onToggleRegion,
  });

  /// Whether reading is currently paused.
  final bool isPaused;

  /// The word list for preview context.
  final List<String> words;

  /// Detected artifact regions from the classifier.
  final List<ArtifactRegion> regions;

  /// Set of word indices currently marked for suppression.
  final Set<int> suppressedIndices;

  /// Callback when user toggles suppression on a region.
  final void Function(ArtifactRegion region) onToggleRegion;

  @override
  Widget build(BuildContext context) {
    if (!isPaused || regions.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RunThruTokens.stageBase.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_fix_high,
                      size: 16,
                      color: RunThruTokens.stageText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Detected Artifacts',
                      style: RunThruTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: RunThruTokens.stageText,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: RunThruTokens.stageDarkShadow),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: regions.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: RunThruTokens.stageDarkShadow,
                  ),
                  itemBuilder: (context, index) {
                    final region = regions[index];
                    return _RegionRow(
                      region: region,
                      words: words,
                      isSuppressed: _isRegionSuppressed(region),
                      onToggle: () => onToggleRegion(region),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isRegionSuppressed(ArtifactRegion region) {
    for (int i = region.startIndex; i <= region.endIndex; i++) {
      if (suppressedIndices.contains(i)) return true;
    }
    return false;
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({
    required this.region,
    required this.words,
    required this.isSuppressed,
    required this.onToggle,
  });

  final ArtifactRegion region;
  final List<String> words;
  final bool isSuppressed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final icon = _iconForType(region.type);
    final label = _labelForType(region.type);
    final preview = _buildPreview();
    final actionLabel = isSuppressed ? 'Include' : 'Skip';
    final actionIcon = isSuppressed ? Icons.visibility : Icons.visibility_off;

    return Semantics(
      label:
          'Detected $label: $preview. '
          'Tap to ${isSuppressed ? 'include' : 'skip'}.',
      child: InkWell(
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: RunThruTokens.stageText),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    style: RunThruTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: RunThruTokens.stageText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preview,
                    style: RunThruTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(actionIcon, size: 16),
                    label: Text(actionLabel, style: RunThruTypography.caption),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildPreview() {
    final start = region.startIndex.clamp(0, words.length - 1);
    final end = (region.startIndex + 4).clamp(0, words.length - 1);
    final previewWords = words.sublist(start, end + 1);
    final text = previewWords.join(' ');
    return region.length > 5 ? '$text…' : text;
  }

  IconData _iconForType(ArtifactType type) {
    return switch (type) {
      ArtifactType.table => Icons.table_chart,
      ArtifactType.codeBlock => Icons.code,
      ArtifactType.caption => Icons.image,
      ArtifactType.pageMarker => Icons.bookmark,
      ArtifactType.reference => Icons.format_quote,
    };
  }

  String _labelForType(ArtifactType type) {
    return switch (type) {
      ArtifactType.table => 'Table',
      ArtifactType.codeBlock => 'Code',
      ArtifactType.caption => 'Caption',
      ArtifactType.pageMarker => 'Page #',
      ArtifactType.reference => 'Reference',
    };
  }
}
