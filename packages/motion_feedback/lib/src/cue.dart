/// Delivery urgency, ordered highest to lowest ([CuePriority.critical] first).
/// Enum declaration order IS the priority order — do not reorder members.
enum CuePriority { critical, high, medium, low }

/// Generic delivery category. Deliberately domain/skill-independent: an app's
/// rule engine decides *which* correction applies, never this package.
enum CueCategory { safety, form, tempo, encouragement, system }

enum HapticPattern { none, light, medium, heavy, warning }

/// A single feedback delivery candidate. Holds only opaque references
/// ([audioAssetRef]) — never display text, lesson content or a product name.
/// Callers own content; this package only arbitrates delivery.
class Cue {
  const Cue({
    required this.id,
    required this.priority,
    required this.category,
    required this.audioAssetRef,
    required this.haptic,
    required this.cooldown,
  });

  final String id;
  final CuePriority priority;
  final CueCategory category;
  final String audioAssetRef;
  final HapticPattern haptic;
  final Duration cooldown;

  /// Structurally well-formed: non-blank identifiers and a non-negative
  /// cooldown. Does not (and cannot) validate that [audioAssetRef] points at
  /// a real bundled asset — that is a caller/build-time concern.
  bool get isWellFormed =>
      id.trim().isNotEmpty && audioAssetRef.trim().isNotEmpty && !cooldown.isNegative;
}
