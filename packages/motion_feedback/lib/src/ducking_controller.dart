/// Opaque handle for one outstanding duck request. Deliberately has no
/// fields and no overridden equality: identity (`==`) is the only notion of
/// sameness, so a token from one [DuckingController] can never collide with
/// a token from another, or with another request on the same controller.
class DuckingToken {
  DuckingToken._();
}

/// Reference-counted, bracket-safe background-audio ducking. Multiple
/// overlapping cues can each hold a duck request; audio level only restores
/// once every outstanding token is released. Releasing an unknown or
/// already-released token is a safe no-op — callers never need to guard
/// against double-release.
class DuckingController {
  final _outstanding = <DuckingToken>{};

  bool get isDucking => _outstanding.isNotEmpty;

  DuckingToken requestDuck() {
    final token = DuckingToken._();
    _outstanding.add(token);
    return token;
  }

  void release(DuckingToken token) {
    _outstanding.remove(token);
  }
}
