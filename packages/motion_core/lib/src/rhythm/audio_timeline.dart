import 'beat_grid.dart';

/// Everything that sits between "the engine scheduled a beat" and "the user
/// heard it".
///
/// Getting this wrong is not a rounding error. Bluetooth audio routes add
/// latency on the order of a full sixteenth note; an engine that judges against
/// scheduled time rather than heard time will tell a perfectly-on-time dancer
/// they are late, every single beat, and no amount of tuning the tolerance
/// window will fix a constant bias.
final class AudioLatencyProfile {
  const AudioLatencyProfile({
    this.outputLatencyUs = 0,
    this.userOffsetUs = 0,
    this.route = AudioRoute.unknown,
  });

  /// Latency reported by the platform audio API for the current route.
  ///
  /// Treated as a starting estimate, never as ground truth: platform-reported
  /// latency does not reliably include the wireless link's own buffering, which
  /// is exactly the part that varies most.
  final int outputLatencyUs;

  /// Residual offset measured by the in-app calibration tap test.
  ///
  /// This is the number that actually makes the system honest, because it is
  /// measured end-to-end through whatever the user is really listening on.
  final int userOffsetUs;

  final AudioRoute route;

  int get totalUs => outputLatencyUs + userOffsetUs;

  /// Whether the profile has been measured rather than assumed.
  bool get isCalibrated => userOffsetUs != 0;

  AudioLatencyProfile copyWith({
    int? outputLatencyUs,
    int? userOffsetUs,
    AudioRoute? route,
  }) =>
      AudioLatencyProfile(
        outputLatencyUs: outputLatencyUs ?? this.outputLatencyUs,
        userOffsetUs: userOffsetUs ?? this.userOffsetUs,
        route: route ?? this.route,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'outputLatencyUs': outputLatencyUs,
        'userOffsetUs': userOffsetUs,
        'route': route.name,
      };

  static AudioLatencyProfile fromJson(Map<String, dynamic> json) =>
      AudioLatencyProfile(
        outputLatencyUs: (json['outputLatencyUs'] as num? ?? 0).toInt(),
        userOffsetUs: (json['userOffsetUs'] as num? ?? 0).toInt(),
        route: AudioRoute.values.firstWhere(
          (AudioRoute r) => r.name == json['route'],
          orElse: () => AudioRoute.unknown,
        ),
      );
}

/// Output route, tracked because latency is a property of the route, not the
/// device: a calibration done on the speaker is worthless once the user pairs
/// headphones, so the profile is stored per route and re-prompted on change.
enum AudioRoute { unknown, speaker, wiredHeadphones, bluetooth, other }

/// A beat grid expressed in *perceived* time.
///
/// The engine judges movement against this, never against the raw grid.
final class PerceivedBeatTimeline {
  const PerceivedBeatTimeline({
    required this.grid,
    this.latency = const AudioLatencyProfile(),
    this.expectedAsynchronyUs = 0,
  });

  final BeatGrid grid;
  final AudioLatencyProfile latency;

  /// Expected negative mean asynchrony: how far *before* the beat a human
  /// naturally lands when synchronising to it.
  ///
  /// A well-documented effect in sensorimotor synchronisation research. Left at
  /// zero until measured against our own fixtures — shipping a borrowed
  /// constant here would bias every timing score in the product on the strength
  /// of a number we never verified.
  final int expectedAsynchronyUs;

  int perceivedTimeOfBeatUs(int beatIndex) =>
      grid.timeOfBeatUs(beatIndex) + latency.totalUs - expectedAsynchronyUs;

  double perceivedBeatPositionAt(int tUs) =>
      grid.beatPositionAt(tUs - latency.totalUs + expectedAsynchronyUs);

  int nearestPerceivedBeatIndexAt(int tUs) =>
      perceivedBeatPositionAt(tUs).round();

  /// Signed offset from the nearest perceived beat, in microseconds.
  /// Positive means late.
  int offsetFromNearestBeatUs(int tUs) =>
      tUs - perceivedTimeOfBeatUs(nearestPerceivedBeatIndexAt(tUs));

  int get beatIntervalUs => grid.beatIntervalUs;

  PerceivedBeatTimeline withLatency(AudioLatencyProfile p) =>
      PerceivedBeatTimeline(
        grid: grid,
        latency: p,
        expectedAsynchronyUs: expectedAsynchronyUs,
      );
}
