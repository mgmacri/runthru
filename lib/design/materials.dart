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
