/// 3D material constants consumed by CustomPainter shaders.
class SpeedyBoyMaterials {
  SpeedyBoyMaterials._();

  /// PBR-approximation material for marble box interior walls.
  static const MaterialParams stageWall = MaterialParams(
    roughness: 0.25,
    metalness: 0.0,
    emissive: 0.0,
  );

  /// Material for 3D extruded word front faces.
  static const MaterialParams wordFront = MaterialParams(
    roughness: 0.4,
    metalness: 0.0,
    emissive: 0.01,
  );

  /// Material for the ORP anchor letter (slight glow).
  static const MaterialParams anchorLetter = MaterialParams(
    roughness: 0.3,
    metalness: 0.0,
    emissive: 0.10,
  );

  /// Material for extrusion side faces.
  static const MaterialParams extrusionSide = MaterialParams(
    roughness: 0.6,
    metalness: 0.0,
    emissive: 0.0,
  );

  /// Material for the WPM dial disc.
  static const MaterialParams dialDisc = MaterialParams(
    roughness: 0.5,
    metalness: 0.05,
    emissive: 0.0,
  );

  /// Extrusion depth = fontSize * this factor.
  static const double extrusionDepthFactor = 0.08;

  /// Bevel radius for extruded letter edges.
  static const double bevelRadius = 0.5;

  // ── A-013: Word Depth Bounce-In constants ──
  // "Felt, not seen" — all values are tuned to be barely perceptible.

  /// Room units of forward Z-travel during word bounce-in.
  static const double wordBounceDepthDeltaZ = 0.8;

  /// Shadow blur range: (start, resting).
  static const double wordBounceShadowBlurMin = 44.0;
  static const double wordBounceShadowBlurMax = 52.0;

  /// Shadow opacity range: (start dim, resting full).
  static const double wordBounceShadowOpacityMin = 0.252; // 0.36 * 0.7
  static const double wordBounceShadowOpacityMax = 0.36;

  /// Shadow Y offset at full bounce (room units).
  static const double wordBounceShadowOffsetY = 2.0;

  /// Bounce overshoot fraction (4%).
  static const double wordBounceOvershoot = 0.04;
}

class MaterialParams {
  const MaterialParams({
    required this.roughness,
    required this.metalness,
    required this.emissive,
  });

  final double roughness;
  final double metalness;
  final double emissive;
}
