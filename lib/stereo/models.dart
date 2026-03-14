/// 3D offset representing head position in space.
class Offset3D {
  const Offset3D(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  /// Euclidean distance from origin.
  double get distance {
    return (x * x + y * y + z * z);
  }

  Offset3D operator +(Offset3D other) =>
      Offset3D(x + other.x, y + other.y, z + other.z);

  Offset3D operator *(double factor) =>
      Offset3D(x * factor, y * factor, z * factor);

  static const Offset3D zero = Offset3D(0, 0, 0);
}
