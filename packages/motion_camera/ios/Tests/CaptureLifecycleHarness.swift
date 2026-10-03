import Foundation

@main struct CaptureLifecycleHarness {
  static var assertions = 0
  static var scenarios = 0
  static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { fatalError(message) }
  }
  static func scenario(_ name: String, _ body: () throws -> Void) rethrows {
    try body()
    scenarios += 1
    print("PASS \(name)")
  }
  final class Graph {
    var last = -1
    var samples: [Int] = []
    func detect(_ timestamp: Int) {
      expect(timestamp > last, "a VIDEO graph received a duplicate timestamp")
      last = timestamp
      samples.append(timestamp)
    }
  }

  static func main() throws {
    try scenario("repeated stop shares pending physical/model close") {
      let lifecycle = CaptureLifecycle()
      let generation = try lifecycle.begin(ownerId: "A")
      expect(lifecycle.markRunning(generation), "start not running")
      var acknowledgements = 0
      expect(lifecycle.requestClose(ownerId: "A", scoped: true) {
        expect($0, "first close failed"); acknowledgements += 1
      }, "first close must own resource barrier")
      expect(!lifecycle.requestClose(ownerId: "A", scoped: true) {
        expect($0, "second close failed"); acknowledgements += 1
      }, "second close must join barrier")
      expect(acknowledgements == 0, "early close ACK")
      expect(lifecycle.observation(ownerId: "A")["state"] as? String == "closing", "wrong state")
      lifecycle.finishClose(success: true)
      expect(acknowledgements == 2, "not all close waiters acknowledged")
    }
    try scenario("lifecycle teardown then explicit stop cannot ACK early") {
      let lifecycle = CaptureLifecycle()
      _ = try lifecycle.begin(ownerId: "A")
      expect(lifecycle.requestClose(), "lifecycle teardown did not own barrier")
      var ack = false
      expect(!lifecycle.requestClose(ownerId: "A", scoped: true) { ack = $0 }, "stop duplicated barrier")
      expect(!ack, "explicit stop ACK before lifecycle barrier")
      lifecycle.finishClose(success: true)
      expect(ack, "explicit stop missing completion")
    }
    try scenario("closing prevents replacement and stale pending start") {
      let lifecycle = CaptureLifecycle()
      let generation = try lifecycle.begin(ownerId: "A")
      expect(lifecycle.requestClose(), "missing barrier")
      expect(!lifecycle.markRunning(generation), "retired pending start revived")
      do { _ = try lifecycle.begin(ownerId: "B"); expect(false, "replacement during close") }
      catch CaptureLifecycle.Refusal.closeUncertain { expect(true, "named refusal") }
      lifecycle.finishClose(success: true)
      let next = try lifecycle.begin(ownerId: "B")
      expect(next > generation, "generation was reused")
      expect(!lifecycle.isCurrent(generation), "stale generation accepted")
    }
    try scenario("denied or stale owner cannot stop successor") {
      let lifecycle = CaptureLifecycle()
      let successor = try lifecycle.begin(ownerId: "B")
      expect(lifecycle.markRunning(successor), "successor not running")
      var ack = false
      expect(!lifecycle.requestClose(ownerId: "A", scoped: true) { ack = $0 }, "foreign owner tore down B")
      expect(ack, "absent owner not observed closed")
      expect(lifecycle.isCurrent(successor), "successor lost ownership")
      expect(lifecycle.observation(ownerId: "A")["generation"] as? UInt64 == 0, "foreign generation leaked")
    }
    try scenario("close failure is sticky for every waiter and replacement") {
      let lifecycle = CaptureLifecycle()
      _ = try lifecycle.begin(ownerId: "A")
      var refused = 0
      expect(lifecycle.requestClose { if !$0 { refused += 1 } }, "missing barrier")
      expect(!lifecycle.requestClose { if !$0 { refused += 1 } }, "duplicate barrier")
      lifecycle.finishClose(success: false)
      expect(refused == 2, "failure not delivered to both waiters")
      expect(lifecycle.observation(ownerId: "A")["modelsClosed"] as? Bool == false, "uncertain model called closed")
      do { _ = try lifecycle.begin(ownerId: "B"); expect(false, "uncertain close allowed replacement") }
      catch CaptureLifecycle.Refusal.closeUncertain { expect(true, "named refusal") }
    }
    try scenario("fresh readback is owner/generation/nonce bound") {
      let lifecycle = CaptureLifecycle()
      let generation = try lifecycle.begin(ownerId: "A")
      expect(lifecycle.requestClose(), "missing barrier")
      lifecycle.finishClose(success: true)
      let state = lifecycle.observation(ownerId: "A", nonce: 42)
      expect(state["ownerId"] as? String == "A", "wrong owner")
      expect(state["generation"] as? UInt64 == generation, "wrong generation")
      expect(state["nonce"] as? Int == 42, "stale readback nonce")
      expect(state["closeSequence"] as? UInt64 == 1, "close not observed")
      expect(state["captureClosed"] as? Bool == true, "capture not closed")
    }
    try scenario("dual uses separate VIDEO graphs with unchanged real PTS") {
      let up = Graph(), inv = Graph()
      let pair = try OrientedCaptureTasks(upright: up, inverted: inv)
      for timestamp in [400, 401] {
        pair.task(inverted: false).detect(timestamp)
        pair.task(inverted: true).detect(timestamp)
      }
      expect(up.samples == inv.samples, "orientation timestamps changed")
      expect(up !== inv, "orientation graph shared")
      do { _ = try OrientedCaptureTasks(upright: up, inverted: up); expect(false, "shared graph accepted") }
      catch OrientedCaptureTasks<Graph>.PairError.sharedGraph { expect(true, "shared graph refused") }
    }
    print("RESULT scenarios=\(scenarios) assertions=\(assertions) failures=0")
  }
}
