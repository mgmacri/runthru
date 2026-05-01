import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Font-scale slider for Settings screen.
///
/// Range: 50%–200% (0.5–2.0 internally).
/// Calls [onChanged] only when the drag finishes.
class FontSizeSlider extends StatefulWidget {
  const FontSizeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<FontSizeSlider> createState() => _FontSizeSliderState();
}

class _FontSizeSliderState extends State<FontSizeSlider> {
  double? _dragging;

  double get _displayValue => _dragging ?? widget.value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${(_displayValue * 100).round()}%',
          style: RunThruTypography.badge,
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: RunThruTokens.shellAccent,
            inactiveTrackColor: RunThruTokens.shellDarkShadow,
            thumbColor: RunThruTokens.shellTextPrimary,
            overlayColor: RunThruTokens.shellAccent.withAlpha(51),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 12,
            ),
            trackHeight: 6,
          ),
          child: Slider(
            value: _displayValue,
            min: 0.5,
            max: 2.0,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
