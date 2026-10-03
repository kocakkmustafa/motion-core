import Foundation

/// Shared by the plugin and host harness. Resource closure is performed by the
/// plugin; only finishClose(success:) can acknowledge that resource barrier.
final class CaptureLifecycle {
  enum Phase: String { case closed, opening, running, closing, uncertain }
  enum Refusal: Error { case alreadyRunning, closeUncertain }
  private let lock = NSLock()
  private var phase: Phase = .closed
  private var owner: String?
  private var generation: UInt64 = 0
  private var closeSequence: UInt64 = 0
  private var waiters: [(Bool) -> Void] = []

  func startRefusalCode() -> String? {
    lock.lock()
    defer { lock.unlock() }
    if phase == .closed { return nil }
    return phase == .closing || phase == .uncertain ? "close-uncertain" : "already-running"
  }

  func begin(ownerId: String?) throws -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    guard phase == .closed else {
      if phase == .closing || phase == .uncertain { throw Refusal.closeUncertain }
      throw Refusal.alreadyRunning
    }
    generation &+= 1
    owner = ownerId
    phase = .opening
    return generation
  }

  @discardableResult func markRunning(_ candidate: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard phase == .opening, generation == candidate else { return false }
    phase = .running
    return true
  }

  func isCurrent(_ candidate: UInt64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return (phase == .opening || phase == .running) && generation == candidate
  }

  func currentOwner() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return owner
  }

  /// True exactly once means the caller must start the resource barrier. A
  /// repeated stop joins the same completion; a foreign owner stops nothing.
  func requestClose(ownerId: String? = nil, scoped: Bool = false,
                    completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
    lock.lock()
    if (scoped && ownerId != owner) || phase == .closed {
      lock.unlock()
      completion(true)
      return false
    }
    if phase == .uncertain {
      lock.unlock()
      completion(false)
      return false
    }
    waiters.append(completion)
    if phase == .closing {
      lock.unlock()
      return false
    }
    phase = .closing
    lock.unlock()
    return true
  }

  func finishClose(success: Bool) {
    lock.lock()
    guard phase == .closing else { lock.unlock(); return }
    phase = success ? .closed : .uncertain
    if success { closeSequence &+= 1 }
    let pending = waiters
    waiters.removeAll()
    lock.unlock()
    pending.forEach { $0(success) }
  }

  func observation(ownerId: String, nonce: Int = 0) -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    let target = ownerId == owner ? phase : .closed
    return [
      "protocol": 1, "ownerId": ownerId,
      "generation": ownerId == owner ? generation : UInt64(0),
      "state": target.rawValue,
      "captureClosed": target == .closed, "modelsClosed": target == .closed,
      "closeSequence": closeSequence, "nonce": nonce,
    ]
  }
}

/// VIDEO graphs retain per-stream tracking/timestamp state. The two orientations
/// must never share one graph, even though they process the same capture PTS.
final class OrientedCaptureTasks<Task: AnyObject> {
  enum PairError: Error { case sharedGraph }
  let upright: Task
  let inverted: Task

  init(upright: Task, inverted: Task) throws {
    guard upright !== inverted else { throw PairError.sharedGraph }
    self.upright = upright
    self.inverted = inverted
  }

  func task(inverted: Bool) -> Task { inverted ? self.inverted : upright }
}
