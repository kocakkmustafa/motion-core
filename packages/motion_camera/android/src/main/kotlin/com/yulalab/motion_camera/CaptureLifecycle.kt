package com.yulalab.motion_camera

/** Actual plugin state machine; the host harness imports this same source. */
internal class CaptureLifecycle {
    enum class Phase { CLOSED, OPENING, RUNNING, CLOSING, UNCERTAIN }
    class Refusal(val code: String) : IllegalStateException(code)
    private var phase = Phase.CLOSED
    private var owner: String? = null
    private var generation = 0L
    private var closeSequence = 0L
    private val waiters = mutableListOf<(Boolean) -> Unit>()

    @Synchronized fun startRefusalCode(): String? = when (phase) {
        Phase.CLOSED -> null
        Phase.CLOSING, Phase.UNCERTAIN -> "close-uncertain"
        else -> "already-running"
    }

    @Synchronized fun begin(ownerId: String?): Long {
        if (phase != Phase.CLOSED) throw Refusal(
            if (phase == Phase.CLOSING || phase == Phase.UNCERTAIN)
                "close-uncertain" else "already-running",
        )
        generation += 1
        owner = ownerId
        phase = Phase.OPENING
        return generation
    }

    @Synchronized fun markRunning(candidate: Long): Boolean {
        if (phase != Phase.OPENING || generation != candidate) return false
        phase = Phase.RUNNING
        return true
    }

    @Synchronized fun isCurrent(candidate: Long): Boolean =
        (phase == Phase.OPENING || phase == Phase.RUNNING) && generation == candidate

    @Synchronized fun currentOwner(): String? = owner

    /** Only the first caller performs teardown; all later callers await it. */
    fun requestClose(ownerId: String? = null, scoped: Boolean = false,
                     completion: (Boolean) -> Unit = {}): Boolean {
        val immediate: Boolean?
        synchronized(this) {
            immediate = when {
                (scoped && ownerId != owner) || phase == Phase.CLOSED -> true
                phase == Phase.UNCERTAIN -> false
                else -> null
            }
            if (immediate == null) {
                waiters.add(completion)
                if (phase == Phase.CLOSING) return false
                phase = Phase.CLOSING
                return true
            }
        }
        completion(immediate!!)
        return false
    }

    fun finishClose(success: Boolean) {
        val pending: List<(Boolean) -> Unit>
        synchronized(this) {
            if (phase != Phase.CLOSING) return
            phase = if (success) Phase.CLOSED else Phase.UNCERTAIN
            if (success) closeSequence += 1
            pending = waiters.toList()
            waiters.clear()
        }
        pending.forEach { it(success) }
    }

    @Synchronized fun observation(ownerId: String, nonce: Int = 0): Map<String, Any> {
        val target = if (ownerId == owner) phase else Phase.CLOSED
        return mapOf(
            "protocol" to 1, "ownerId" to ownerId,
            "generation" to if (ownerId == owner) generation else 0L,
            "state" to target.name.lowercase(),
            "captureClosed" to (target == Phase.CLOSED),
            "modelsClosed" to (target == Phase.CLOSED),
            "closeSequence" to closeSequence, "nonce" to nonce,
        )
    }
}

/** VIDEO graph state is independent for each orientation, with real timestamps. */
internal class OrientedCaptureTasks<T : Any>(val upright: T, val inverted: T) {
    init { require(upright !== inverted) { "orientation tasks share one graph" } }
    fun task(inverted: Boolean): T = if (inverted) this.inverted else upright
    fun all(): List<T> = listOf(upright, inverted)
}
