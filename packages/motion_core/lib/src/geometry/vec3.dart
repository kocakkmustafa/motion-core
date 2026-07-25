import 'dart:math' as math;

/// Immutable 3D vector.
///
/// Coordinate convention across the family (matches MediaPipe Tasks output):
///  * `x` grows to the image right, `y` grows *downward* (image convention),
///  * `z` is depth relative to the hip midpoint, negative toward the camera,
///  * for 2D-only work set `z = 0` and use the `*2D` helpers.
///
/// The engine never reasons about raw pixels: everything downstream of
/// [normalization] works in torso-relative units.
final class Vec3 {
  const Vec3(this.x, this.y, this.z);

  const Vec3.xy(this.x, this.y) : z = 0;

  static const Vec3 zero = Vec3(0, 0, 0);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);

  double get length => math.sqrt(x * x + y * y + z * z);
  double get length2 => x * x + y * y + z * z;

  /// Planar (image-plane) length, ignoring depth.
  double get length2D => math.sqrt(x * x + y * y);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  /// Unit vector, or [zero] when the vector is degenerate.
  ///
  /// Returning zero rather than NaN matters: a degenerate limb (two landmarks
  /// collapsed onto each other because the model lost the joint) must flow
  /// through the pipeline as "no information", never as a poisoned number that
  /// silently corrupts a score.
  Vec3 get normalized {
    final double l = length;
    if (l < 1e-9) return zero;
    return Vec3(x / l, y / l, z / l);
  }

  Vec3 lerp(Vec3 o, double t) =>
      Vec3(x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t);

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(4)}, '
      '${y.toStringAsFixed(4)}, ${z.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

/// Midpoint of two points.
Vec3 midpoint(Vec3 a, Vec3 b) => Vec3(
      (a.x + b.x) / 2,
      (a.y + b.y) / 2,
      (a.z + b.z) / 2,
    );

/// Angle in radians at vertex [b] formed by the segments b→a and b→c.
///
/// Returns `double.nan` when either segment is degenerate — callers must treat
/// NaN as "unmeasurable", not as zero. A zero angle is a real, meaningful
/// posture; an unmeasurable one is not, and collapsing the two would let a
/// tracking failure masquerade as a fully-folded joint.
double jointAngle(Vec3 a, Vec3 b, Vec3 c) {
  final Vec3 u = (a - b);
  final Vec3 v = (c - b);
  final double lu = u.length;
  final double lv = v.length;
  if (lu < 1e-9 || lv < 1e-9) return double.nan;
  final double cosine = (u.dot(v) / (lu * lv)).clamp(-1.0, 1.0);
  return math.acos(cosine);
}

/// [jointAngle] restricted to the image plane (ignores depth).
///
/// Single-camera depth from BlazePose is the least reliable channel; planar
/// angles are used wherever the movement happens fronto-parallel to the lens.
double jointAngle2D(Vec3 a, Vec3 b, Vec3 c) => jointAngle(
      Vec3.xy(a.x, a.y),
      Vec3.xy(b.x, b.y),
      Vec3.xy(c.x, c.y),
    );

/// Signed angle of the vector a→b relative to the image +x axis, in radians,
/// in the range (-pi, pi]. Used for limb *orientation* (e.g. "is the forearm
/// pointing up or down"), which a vertex angle cannot express.
double segmentAngle2D(Vec3 a, Vec3 b) => math.atan2(b.y - a.y, b.x - a.x);

/// Wraps an angle into the range `(-pi, pi]`.
double wrapPi(double angle) {
  double a = (angle + math.pi) % (2 * math.pi);
  if (a <= 0) a += 2 * math.pi;
  return a - math.pi;
}

/// Smallest absolute difference between two angles, in radians.
double angleDelta(double a, double b) {
  double d = (a - b).abs() % (2 * math.pi);
  if (d > math.pi) d = 2 * math.pi - d;
  return d;
}

const double radToDeg = 180.0 / math.pi;
const double degToRad = math.pi / 180.0;
