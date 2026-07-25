/// MediaPipe Pose Landmarker (BlazePose GHUM) 33-point topology.
///
/// This is the family-wide skeleton contract (see `10-ARAC-KATALOGU.md` §1).
/// Every fixture, every rule set and every native port indexes landmarks with
/// these constants — never with bare integers.
library;

/// Indices into a 33-element pose landmark list.
///
/// Deliberately a class of `static const int` rather than an `enum`: landmark
/// arrays arrive from the native bridge as flat buffers, so callers index them
/// with plain ints. An enum would force a `.index` at every call site.
abstract final class Lm {
  static const int nose = 0;
  static const int leftEyeInner = 1;
  static const int leftEye = 2;
  static const int leftEyeOuter = 3;
  static const int rightEyeInner = 4;
  static const int rightEye = 5;
  static const int rightEyeOuter = 6;
  static const int leftEar = 7;
  static const int rightEar = 8;
  static const int mouthLeft = 9;
  static const int mouthRight = 10;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
  static const int leftPinky = 17;
  static const int rightPinky = 18;
  static const int leftIndex = 19;
  static const int rightIndex = 20;
  static const int leftThumb = 21;
  static const int rightThumb = 22;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;

  /// Number of landmarks in the BlazePose GHUM topology.
  static const int count = 33;

  /// Human-readable names, indexed identically to the constants above.
  static const List<String> names = <String>[
    'nose',
    'left_eye_inner',
    'left_eye',
    'left_eye_outer',
    'right_eye_inner',
    'right_eye',
    'right_eye_outer',
    'left_ear',
    'right_ear',
    'mouth_left',
    'mouth_right',
    'left_shoulder',
    'right_shoulder',
    'left_elbow',
    'right_elbow',
    'left_wrist',
    'right_wrist',
    'left_pinky',
    'right_pinky',
    'left_index',
    'right_index',
    'left_thumb',
    'right_thumb',
    'left_hip',
    'right_hip',
    'left_knee',
    'right_knee',
    'left_ankle',
    'right_ankle',
    'left_heel',
    'right_heel',
    'left_foot_index',
    'right_foot_index',
  ];

  static String nameOf(int index) =>
      (index >= 0 && index < count) ? names[index] : 'unknown($index)';
}

/// Named groups of landmarks used by confidence gating and framing checks.
///
/// A technique declares which regions it *requires*; if a required region is
/// not reliably visible the engine must report "cannot judge" rather than
/// guessing (family rule: no verdict under low confidence).
abstract final class LmRegion {
  static const List<int> head = <int>[
    Lm.nose,
    Lm.leftEye,
    Lm.rightEye,
    Lm.leftEar,
    Lm.rightEar,
  ];

  static const List<int> torso = <int>[
    Lm.leftShoulder,
    Lm.rightShoulder,
    Lm.leftHip,
    Lm.rightHip,
  ];

  static const List<int> leftArm = <int>[
    Lm.leftShoulder,
    Lm.leftElbow,
    Lm.leftWrist,
  ];

  static const List<int> rightArm = <int>[
    Lm.rightShoulder,
    Lm.rightElbow,
    Lm.rightWrist,
  ];

  static const List<int> leftLeg = <int>[
    Lm.leftHip,
    Lm.leftKnee,
    Lm.leftAnkle,
  ];

  static const List<int> rightLeg = <int>[
    Lm.rightHip,
    Lm.rightKnee,
    Lm.rightAnkle,
  ];

  static const List<int> leftFoot = <int>[
    Lm.leftAnkle,
    Lm.leftHeel,
    Lm.leftFootIndex,
  ];

  static const List<int> rightFoot = <int>[
    Lm.rightAnkle,
    Lm.rightHeel,
    Lm.rightFootIndex,
  ];

  /// Everything needed to judge a full-body movement.
  static const List<int> fullBody = <int>[
    Lm.leftShoulder,
    Lm.rightShoulder,
    Lm.leftElbow,
    Lm.rightElbow,
    Lm.leftWrist,
    Lm.rightWrist,
    Lm.leftHip,
    Lm.rightHip,
    Lm.leftKnee,
    Lm.rightKnee,
    Lm.leftAnkle,
    Lm.rightAnkle,
  ];

  static const Map<String, List<int>> byName = <String, List<int>>{
    'head': head,
    'torso': torso,
    'leftArm': leftArm,
    'rightArm': rightArm,
    'leftLeg': leftLeg,
    'rightLeg': rightLeg,
    'leftFoot': leftFoot,
    'rightFoot': rightFoot,
    'fullBody': fullBody,
  };
}

/// Left/right mirror mapping.
///
/// Used for two independent purposes:
///  * stance mirroring (JabLab orthodox/southpaw, Choreia lead-side swap), and
///  * mirror-mode teaching, where the on-screen reference is flipped so the
///    learner can copy it as if looking in a mirror (Choreia C-005).
abstract final class LmMirror {
  static const Map<int, int> pairs = <int, int>{
    Lm.leftEyeInner: Lm.rightEyeInner,
    Lm.leftEye: Lm.rightEye,
    Lm.leftEyeOuter: Lm.rightEyeOuter,
    Lm.leftEar: Lm.rightEar,
    Lm.mouthLeft: Lm.mouthRight,
    Lm.leftShoulder: Lm.rightShoulder,
    Lm.leftElbow: Lm.rightElbow,
    Lm.leftWrist: Lm.rightWrist,
    Lm.leftPinky: Lm.rightPinky,
    Lm.leftIndex: Lm.rightIndex,
    Lm.leftThumb: Lm.rightThumb,
    Lm.leftHip: Lm.rightHip,
    Lm.leftKnee: Lm.rightKnee,
    Lm.leftAnkle: Lm.rightAnkle,
    Lm.leftHeel: Lm.rightHeel,
    Lm.leftFootIndex: Lm.rightFootIndex,
  };

  /// Index of the mirrored counterpart, or the same index for midline points.
  static int of(int index) {
    final int? right = pairs[index];
    if (right != null) return right;
    for (final MapEntry<int, int> e in pairs.entries) {
      if (e.value == index) return e.key;
    }
    return index; // midline landmark (nose)
  }
}
