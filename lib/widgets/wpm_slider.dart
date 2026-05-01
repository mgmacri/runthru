import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// WPM slider for Settings screen with neumorphic appearance.
///
/// Tracks local drag state internally for smooth interaction.
/// Calls [onChanged] only when the drag finishes (finger lifts).
class WpmSlider extends StatefulWidget {
  const WpmSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<WpmSlider> createState() => _WpmSliderState();
}

class _WpmSliderState extends State<WpmSlider> {
  double? _dragging;

  double get _displayValue => _dragging ?? widget.value.toDouble();

  @override
  void didUpdateWidget(WpmSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If external value changed and we're not dragging, reset
    if (_dragging == null && widget.value != oldWidget.value) {
      // No setState needed — build will use new widget.value
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_displayValue.round()} WPM',
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
            min: 30,
            max: 1000,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v.round());
            },
          ),
        ),
      ],
    );
  }
}
