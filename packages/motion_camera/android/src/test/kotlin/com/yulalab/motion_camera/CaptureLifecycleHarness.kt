package com.yulalab.motion_camera

private var assertions = 0
private var scenarios = 0
private fun expect(condition: Boolean, message: String) {
    assertions += 1
    check(condition) { message }
}
private fun scenario(name: String, body: () -> Unit) {
    body(); scenarios += 1; println("PASS $name")
}
private class Graph {
    private var last = -1
    val samples = mutableListOf<Int>()
    fun detect(timestamp: Int) {
        expect(timestamp > last, "VIDEO graph received duplicate timestamp")
        last = timestamp; samples.add(timestamp)
    }
}
fun main() {
    scenario("repeated stop shares physical/model barrier") {
        val lifecycle = CaptureLifecycle()
        val generation = lifecycle.begin("A")
        expect(lifecycle.markRunning(generation), "start not running")
        var acknowledgements = 0
        expect(lifecycle.requestClose("A", true) {
            expect(it, "first close failed"); acknowledgements += 1
        }, "first close did not own barrier")
        expect(!lifecycle.requestClose("A", true) {
            expect(it, "second close failed"); acknowledgements += 1
        }, "second close duplicated barrier")
        expect(acknowledgements == 0, "early ACK")
        expect(lifecycle.observation("A")["state"] == "closing", "wrong state")
        lifecycle.finishClose(true)
        expect(acknowledgements == 2, "not all waiters acknowledged")
    }
    scenario("lifecycle teardown then explicit stop waits") {
        val lifecycle = CaptureLifecycle(); lifecycle.begin("A")
        expect(lifecycle.requestClose(), "missing lifecycle barrier")
        var ack = false
        expect(!lifecycle.requestClose("A", true) { ack = it }, "duplicate barrier")
        expect(!ack, "early explicit ACK")
        lifecycle.finishClose(true)
        expect(ack, "missing explicit completion")
    }
    scenario("closing prevents replacement and late pending start") {
        val lifecycle = CaptureLifecycle(); val generation = lifecycle.begin("A")
        expect(lifecycle.requestClose(), "missing barrier")
        expect(!lifecycle.markRunning(generation), "pending start revived")
        try { lifecycle.begin("B"); expect(false, "replacement during closing") }
        catch (e: CaptureLifecycle.Refusal) { expect(e.code == "close-uncertain", "wrong refusal") }
        lifecycle.finishClose(true)
        expect(lifecycle.begin("B") > generation, "generation reused")
        expect(!lifecycle.isCurrent(generation), "stale generation accepted")
    }
    scenario("denied or stale owner leaves successor active") {
        val lifecycle = CaptureLifecycle(); val successor = lifecycle.begin("B")
        expect(lifecycle.markRunning(successor), "successor not running")
        var ack = false
        expect(!lifecycle.requestClose("A", true) { ack = it }, "foreign close tore down B")
        expect(ack, "absent owner not observed closed")
        expect(lifecycle.isCurrent(successor), "successor lost ownership")
        expect(lifecycle.observation("A")["generation"] == 0L, "foreign generation")
    }
    scenario("failure is sticky for all waiters and replacement") {
        val lifecycle = CaptureLifecycle(); lifecycle.begin("A")
        var refused = 0
        expect(lifecycle.requestClose { if (!it) refused += 1 }, "missing barrier")
        expect(!lifecycle.requestClose { if (!it) refused += 1 }, "duplicate barrier")
        lifecycle.finishClose(false)
        expect(refused == 2, "failure not delivered to all waiters")
        expect(lifecycle.observation("A")["modelsClosed"] == false, "uncertain called closed")
        try { lifecycle.begin("B"); expect(false, "replacement after failure") }
        catch (e: CaptureLifecycle.Refusal) { expect(e.code == "close-uncertain", "wrong refusal") }
    }
    scenario("readback binds owner generation fresh nonce") {
        val lifecycle = CaptureLifecycle(); val generation = lifecycle.begin("A")
        expect(lifecycle.requestClose(), "missing barrier"); lifecycle.finishClose(true)
        val state = lifecycle.observation("A", 42)
        expect(state["ownerId"] == "A", "wrong owner")
        expect(state["generation"] == generation, "wrong generation")
        expect(state["nonce"] == 42, "stale nonce")
        expect(state["closeSequence"] == 1L, "close not observed")
        expect(state["captureClosed"] == true, "capture not closed")
    }
    scenario("dual uses independent VIDEO graphs unchanged PTS") {
        val up = Graph(); val inv = Graph(); val pair = OrientedCaptureTasks(up, inv)
        for (timestamp in listOf(400, 401)) {
            pair.task(false).detect(timestamp); pair.task(true).detect(timestamp)
        }
        expect(up.samples == inv.samples, "orientation timestamps changed")
        expect(up !== inv, "shared graph")
        try { OrientedCaptureTasks(up, up); expect(false, "shared graph accepted") }
        catch (_: IllegalArgumentException) { expect(true, "shared graph rejected") }
    }
    println("RESULT scenarios=$scenarios assertions=$assertions failures=0")
}
