import 'clock.dart';
import 'cue.dart';

/// Enforces the family's "one correction at a time" rule: at most one [Cue]
/// is active at once, and a new candidate only interrupts it if strictly
/// higher priority. Fail-closed: anything malformed is silently rejected
/// (never delivered, never thrown) so a bad candidate can only fail safe by
/// producing silence, not a crash or a wrong/garbled correction.
class CueArbitrator {
  CueArbitrator({Clock clock = const SystemClock()}) : _clock = clock;

  final Clock _clock;
  Cue? _active;
  DateTime? _activeExpiresAt;

  Cue? get activeCue => _active;

  /// Offers a candidate cue for delivery. Returns whether it was accepted
  /// and became (or remained) the active cue.
  bool offer(Cue cue) {
    if (!cue.isWellFormed) return false;

    final now = _clock.now();
    final activeStillLive = _active != null &&
        _activeExpiresAt != null &&
        now.isBefore(_activeExpiresAt!);

    if (activeStillLive && cue.priority.index >= _active!.priority.index) {
      return false;
    }

    _active = cue;
    _activeExpiresAt = now.add(cue.cooldown);
    return true;
  }
}
