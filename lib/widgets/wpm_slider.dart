import 'package:flutter/material.dart';
import 'package:speedy_boy/design/design.dart';

/// WPM slider for Settings screen with neumorphic appearance.
class WpmSlider extends StatelessWidget {
  const WpmSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value WPM',
          style: SpeedyBoyTypography.badge,
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: SpeedyBoyTokens.shellAccent,
            inactiveTrackColor: SpeedyBoyTokens.shellDarkShadow,
            thumbColor: SpeedyBoyTokens.shellTextPrimary,
            overlayColor: SpeedyBoyTokens.shellAccent.withOpacity(0.2),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 12,
            ),
            trackHeight: 6,
          ),
          child: Slider(
            value: value.toDouble(),
            min: 30,
            max: 1000,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}
