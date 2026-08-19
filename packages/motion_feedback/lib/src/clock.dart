/// Injectable time source so arbitration/cooldown logic is deterministically
/// testable without waiting on real wall-clock time.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
