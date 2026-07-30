/// Domain-independent motion analysis core for the Yula Motion family.
///
/// This package holds only machinery that is true for every app in the family:
/// how a skeleton is normalized, how two poses are compared, how a sequence is
/// aligned in time, how beats are counted, how a phase state machine runs, and
/// what a fixture looks like. It holds **no** technique rules, no curriculum
/// and no content — those live in each app, so that a change to salsa footwork
/// can never destabilise a boxing guard.
///
/// It is also the *normative reference*: the real-time loop runs natively
/// (Kotlin/Swift) for latency reasons, and the native ports are validated by
/// replaying shared fixtures and comparing against this implementation's
/// output. When the two disagree, this package is right by definition.
library;

export 'src/fixture/fixture.dart';
export 'src/fixture/replay.dart';
export 'src/fixture/synthetic.dart';
export 'src/geometry/joint_angles.dart';
export 'src/geometry/normalization.dart';
export 'src/geometry/vec3.dart';
export 'src/engine/ai_disclosure.dart';
export 'src/engine/feedback_prioritizer.dart';
export 'src/engine/motion_clock.dart';
export 'src/engine/phase_config.dart';
export 'src/engine/phase_state_machine.dart';
export 'src/engine/provenance.dart';
export 'src/pose/confidence_gate.dart';
export 'src/pose/landmark_index.dart';
export 'src/pose/orientation.dart';
export 'src/pose/orientation_aware_source.dart';
export 'src/pose/pose_frame.dart';
export 'src/pose/smoothing.dart';
export 'src/pose/structural_validator.dart';
export 'src/session/session_store.dart';
export 'src/rhythm/audio_timeline.dart';
export 'src/rhythm/beat_grid.dart';
export 'src/rhythm/cue_gate.dart';
export 'src/rhythm/latency_calibration.dart';
export 'src/rhythm/timing.dart';
export 'src/scoring/cycle_aligner.dart';
export 'src/scoring/cycle_segmentation.dart';
export 'src/scoring/dtw.dart';
export 'src/scoring/reference_builder.dart';
export 'src/scoring/sequence_comparator.dart';
export 'src/scoring/similarity.dart';
export 'src/tooling/reference_cli.dart';
