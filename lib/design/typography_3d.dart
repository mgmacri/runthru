import 'package:runthru/design/materials.dart';

/// 3D typography configuration for extruded text rendering.
class Typography3DConfig {
  Typography3DConfig._();

  /// Extrusion depth in logical pixels for a given font size.
  static double extrusionDepth(double fontSize) =>
      fontSize * RunThruMaterials.extrusionDepthFactor;

  /// Bevel radius for extruded letter edges.
  static double get bevelRadius => RunThruMaterials.bevelRadius;

  /// Number of extrusion layers for pseudo-3D effect.
  static const int extrusionLayers = 6;

  /// Darkening factor per extrusion layer.
  static const double layerDarkenFactor = 0.15;
}
