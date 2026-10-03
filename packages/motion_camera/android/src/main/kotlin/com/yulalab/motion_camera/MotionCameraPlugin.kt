package com.yulalab.motion_camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.hardware.camera2.CameraCharacteristics
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.Camera
import androidx.camera.core.CameraState
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.Observer
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * ⚠️ CURRENT OWNED BRIDGE NOT YET COMPILED OR RUN — source targets
 * tasks-vision 0.10.29 (M-L-02). Host helper tests do not compile this bridge.
 * Historical 0.1.2 compilation does not validate this change. Liveness (a real session emitting
 * envelopes) is a separate, named step; until it happens this file is design
 * made concrete, not a working bridge (beyan ≠ canlı).
 *
 * Contract: docs/70-KAMERA-KOPRUSU-SOZLESMESI.md. Mirrors the iOS layer:
 *  - CameraX ImageAnalysis with STRATEGY_KEEP_ONLY_LATEST (latest-wins is
 *    built in; we additionally COUNT what was skipped — the platform drops
 *    silently, the family does not)
 *  - PoseLandmarker in VIDEO mode; dual pass on the same bitmap, inverted =
 *    ImageProcessingOptions rotation 180°, landmarks mapped back x→1-x, y→1-y
 *  - clock domain is REPORTED, not assumed: SENSOR_INFO_TIMESTAMP_SOURCE
 *    REALTIME → "monotonic", otherwise "unknown" (fusion with the audio
 *    clock then requires a measured offset — beat-alignment honesty)
 *  - named refusals; the plugin never requests permission itself
 */
class MotionCameraPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, ActivityAware, DefaultLifecycleObserver {

    companion object {
        const val LIBRARY_TAG = "mp-android-0.10.29"
    }

    private lateinit var context: Context
    private lateinit var control: MethodChannel
    private lateinit var frames: EventChannel
    private var frameSink: EventChannel.EventSink? = null
    private var frameSinkOwner: String? = null
    private var frameSinkGeneration: Long? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var inferenceExecutor = Executors.newSingleThreadExecutor()
    private var analysisExecutor = Executors.newSingleThreadExecutor()

    private var activityBinding: ActivityPluginBinding? = null
    private var activityLifecycleOwner: LifecycleOwner? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var camera: Camera? = null
    private var bindingAttempted = false
    private var poseTasks: OrientedCaptureTasks<PoseLandmarker>? = null
    private var pendingPoseTasks: OrientedCaptureTasks<PoseLandmarker>? = null
    private val loadingTasks = mutableListOf<PoseLandmarker>()
    private val lifecycle = CaptureLifecycle()
    private data class RetiredCapture(
        val camera: Camera?,
        val provider: ProcessCameraProvider?,
        val analysis: ImageAnalysis?,
        val markers: List<PoseLandmarker>,
    )
    private var closingResources: RetiredCapture? = null
    private var closeFailure: Exception? = null
    private var modelString = ""
    @Volatile private var plan = "upright"
    @Volatile private var clockDomain = "unknown"
    @Volatile private var activeGeneration = 0L
    @Volatile private var sessionActive = false
    @Volatile private var droppedGeneration = 0L
    @Volatile private var droppedSinceLastEmit = 0
    @Volatile private var inferenceBusyGeneration = 0L

    private data class PendingStart(
        val generation: Long,
        val result: MethodChannel.Result,
    )

    private var pendingStart: PendingStart? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (analysisExecutor.isShutdown || inferenceExecutor.isShutdown) {
            analysisExecutor = Executors.newSingleThreadExecutor()
            inferenceExecutor = Executors.newSingleThreadExecutor()
        }
        context = binding.applicationContext
        control = MethodChannel(binding.binaryMessenger, "motion_camera/control")
        control.setMethodCallHandler(this)
        frames = EventChannel(binding.binaryMessenger, "motion_camera/frames")
        frames.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        tearDown()
        shutDownExecutors()
        detachActivityLifecycle()
        control.setMethodCallHandler(null)
        frames.setStreamHandler(null)
        frameSink = null
    }

    private fun shutDownExecutors() {
        if (analysisExecutor.isShutdown) return
        val inferenceToShutDown = inferenceExecutor
        // The sentinel runs after any analyzer that could still enqueue stale
        // inference work. Both executors then drain and terminate cleanly.
        analysisExecutor.execute { inferenceToShutDown.shutdown() }
        analysisExecutor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivityLifecycle(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        tearDown()
        detachActivityLifecycle()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivityLifecycle(binding)
    }

    override fun onDetachedFromActivity() {
        tearDown()
        detachActivityLifecycle()
    }

    override fun onStop(owner: LifecycleOwner) {
        if (owner === activityLifecycleOwner) tearDown()
    }

    private fun attachActivityLifecycle(binding: ActivityPluginBinding) {
        detachActivityLifecycle()
        activityBinding = binding
        activityLifecycleOwner = binding.activity as? LifecycleOwner
        activityLifecycleOwner?.lifecycle?.addObserver(this)
    }

    private fun detachActivityLifecycle() {
        activityLifecycleOwner?.lifecycle?.removeObserver(this)
        activityLifecycleOwner = null
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start", "startOwned" -> start(call, result)
            "stop" -> stop(result)
            "stopOwned" -> {
                val ownerId = ownedArgument(call)
                if (ownerId == null) {
                    result.error("bad-arguments", "ownerId missing", null); return
                }
                tearDown(ownerId = ownerId, scoped = true) { closed ->
                    if (closed) result.success(lifecycle.observation(ownerId))
                    else result.error("close-uncertain", closeFailure?.message ?: "capture/model closure is uncertain", null)
                }
            }
            "readback" -> {
                val ownerId = ownedArgument(call)
                val nonce = call.argument<Number>("nonce")?.toInt()
                if (ownerId == null || nonce == null || nonce <= 0) {
                    result.error("bad-arguments", "ownerId/nonce missing", null); return
                }
                result.success(lifecycle.observation(ownerId, nonce))
            }
            "setPassPlan", "setPassPlanOwned" -> {
                val newPlan = call.argument<String>("plan")
                if (newPlan !in listOf("upright", "inverted", "dual")) {
                    result.error("bad-arguments", "plan missing", null); return
                }
                val ownerId = ownedArgument(call)
                if (call.method == "setPassPlanOwned") {
                    val generation = call.argument<Number>("generation")?.toLong()
                    if (ownerId == null || generation == null ||
                        lifecycle.currentOwner() != ownerId || !lifecycle.isCurrent(generation)) {
                        result.error("session-interrupted", "capture owner retired", null); return
                    }
                }
                if (!sessionActive || cameraProvider == null) {
                    result.error("not-running", "no active session", null); return
                }
                plan = newPlan!!
                if (call.method == "setPassPlanOwned") result.success(lifecycle.observation(ownerId!!))
                else result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Session lifecycle ──────────────────────────────────────────────────

    private fun ownedArgument(call: MethodCall): String? =
        call.argument<String>("ownerId")?.takeIf { it.isNotEmpty() && it.length <= 128 }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        lifecycle.startRefusalCode()?.let {
            result.error(it, "capture is active or closing", null); return
        }
        val ownerId = if (call.method == "startOwned") ownedArgument(call) else null
        if (call.method == "startOwned" && ownerId == null) {
            result.error("bad-arguments", "ownerId missing", null); return
        }
        val modelPath = call.argument<String>("modelPath")
        val modelId = call.argument<String>("modelId")
        val lens = call.argument<String>("lens")
        val initialPlan = call.argument<String>("plan")
        if (modelPath == null || modelId == null || lens == null ||
            initialPlan !in listOf("upright", "inverted", "dual")) {
            result.error("bad-arguments", "start arguments incomplete", null); return
        }

        // Named refusal — the app owns the permission UX.
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "camera-permission-denied",
                "camera permission is not granted; the app must request it first",
                null
            ); return
        }

        val owner = activityLifecycleOwner
        if (owner == null || !owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            result.error(
                "lifecycle-unavailable",
                "the attached Activity is not a started LifecycleOwner",
                null,
            ); return
        }

        val generation = try { lifecycle.begin(ownerId) }
        catch (e: CaptureLifecycle.Refusal) {
            result.error(e.code, "capture cannot begin", null); return
        }
        activeGeneration = generation
        sessionActive = true
        droppedGeneration = generation
        droppedSinceLastEmit = 0
        inferenceBusyGeneration = 0
        pendingStart = PendingStart(generation, result)
        modelString = "$LIBRARY_TAG+$modelId"
        plan = initialPlan!!

        val candidateTasks = try {
            fun createTask(): PoseLandmarker = PoseLandmarker.createFromOptions(
                context,
                PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(
                        BaseOptions.builder().setModelAssetPath(modelPath).build()
                    )
                    // Each orientation owns a separate VIDEO tracking graph.
                    .setRunningMode(RunningMode.VIDEO)
                    .setNumPoses(1)
                    .build()
            ).also { loadingTasks.add(it) }
            OrientedCaptureTasks(createTask(), createTask()).also {
                pendingPoseTasks = it
                loadingTasks.clear()
            }
        } catch (e: Exception) {
            failStart(generation,
                "model-load-failed",
                "PoseLandmarker rejected $modelPath: ${e.message}"
            ); return
        }

        val selector = if (lens == "back") CameraSelector.DEFAULT_BACK_CAMERA
        else CameraSelector.DEFAULT_FRONT_CAMERA

        val providerFuture = try {
            ProcessCameraProvider.getInstance(context)
        } catch (e: Exception) {
            failStart(generation, "no-such-camera", "provider failed: ${e.message}")
            return
        }
        providerFuture.addListener({
            if (!isCurrentGeneration(generation)) return@addListener
            try {
                val provider = providerFuture.get()
                if (!isCurrentGeneration(generation)) return@addListener

                val analysis = ImageAnalysis.Builder()
                    // Latest-wins is the platform default here; we add the COUNT.
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                analysis.setAnalyzer(analysisExecutor) { proxy ->
                    analyze(proxy, generation)
                }

                cameraProvider = provider
                imageAnalysis = analysis
                bindingAttempted = true
                val camera = provider.bindToLifecycle(owner, selector, analysis)
                this.camera = camera
                poseTasks = candidateTasks
                if (pendingPoseTasks === candidateTasks) {
                    pendingPoseTasks = null
                }
                // Report the clock domain instead of assuming it: vendor camera
                // HALs are allowed to timestamp from an arbitrary zero.
                val source = Camera2CameraInfo.from(camera.cameraInfo)
                    .getCameraCharacteristic(
                        CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE
                    )
                clockDomain = if (
                    source == CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME
                ) "monotonic" else "unknown"

                if (!isCurrentGeneration(generation)) {
                    analysis.clearAnalyzer()
                    provider.unbind(analysis)
                    return@addListener
                }

                val res = analysis.resolutionInfo?.resolution
                completeStart(
                    generation,
                    buildMap<String, Any> {
                        // Portrait-normalized like iOS: min/max of the pair.
                        put("w", res?.let { minOf(it.width, it.height) } ?: 0)
                        put("h", res?.let { maxOf(it.width, it.height) } ?: 0)
                        put("clock", clockDomain)
                        put("library", LIBRARY_TAG)
                        if (ownerId != null) {
                            put("protocol", 1)
                            put("ownerId", ownerId)
                            put("generation", generation)
                        }
                    },
                )
            } catch (e: Exception) {
                failStart(
                    generation,
                    "no-such-camera",
                    "bind failed: ${e.message}",
                )
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun completeStart(generation: Long, info: Map<String, Any>) {
        val pending = pendingStart
        if (!isCurrentGeneration(generation) || pending?.generation != generation) return
        if (!lifecycle.markRunning(generation)) return
        pendingStart = null
        pending.result.success(info)
    }

    private fun failStart(generation: Long, code: String, message: String) {
        val pending = pendingStart
        if (!isCurrentGeneration(generation) || pending?.generation != generation) return
        pendingStart = null
        tearDown(cancelPendingStart = false)
        pending.result.error(code, message, null)
    }

    private fun stop(result: MethodChannel.Result) {
        tearDown { closed ->
            if (closed) result.success(null)
            else result.error("close-uncertain", closeFailure?.message ?: "capture/model closure is uncertain", null)
        }
    }

    private fun isCurrentGeneration(generation: Long): Boolean =
        sessionActive && activeGeneration == generation && lifecycle.isCurrent(generation)

    /**
     * The one teardown path for explicit stop, stream cancellation, Activity
     * stop/detach (including config changes), and engine detach. Invalidate
     * first: already queued analyzer/inference/main-thread callbacks become
     * harmless before any native resource is released.
     */
    private fun tearDown(cancelPendingStart: Boolean = true,
                         ownerId: String? = null, scoped: Boolean = false,
                         completion: (Boolean) -> Unit = {}) {
        // Register before clearing fields. All repeated/in-flight stops share
        // the physical CameraState.CLOSED + every landmarker.close() barrier.
        if (!lifecycle.requestClose(ownerId, scoped) { closed ->
            if (Looper.myLooper() == Looper.getMainLooper()) completion(closed)
            else mainHandler.post { completion(closed) }
        }) return
        sessionActive = false
        activeGeneration = 0

        val pending = pendingStart
        pendingStart = null

        val retired = RetiredCapture(
            camera, cameraProvider, imageAnalysis,
            (poseTasks?.all().orEmpty() + pendingPoseTasks?.all().orEmpty() + loadingTasks).distinct(),
        )
        closingResources = retired
        val wasBinding = bindingAttempted
        camera = null
        imageAnalysis = null
        cameraProvider = null
        bindingAttempted = false
        poseTasks = null
        pendingPoseTasks = null
        loadingTasks.clear()

        var failed = false
        var captureClosed = false
        var modelsClosed = false
        var finished = false
        var cameraObserver: Observer<CameraState>? = null
        lateinit var timeout: Runnable
        fun finishIfReady() {
            if (finished || !modelsClosed || (!captureClosed && !failed)) return
            finished = true
            mainHandler.removeCallbacks(timeout)
            cameraObserver?.let { retired.camera?.cameraInfo?.cameraState?.removeObserver(it) }
            if (!failed && captureClosed) closingResources = null
            // Never swallow unbind/close/timeout failure and advertise closure.
            lifecycle.finishClose(!failed && captureClosed)
        }
        timeout = Runnable {
            if (!finished) {
                closeFailure = closeFailure ?: IllegalStateException("native capture/model close timed out")
                failed = true; modelsClosed = true; finishIfReady()
            }
        }
        mainHandler.postDelayed(timeout, 10_000)
        try {
            retired.analysis?.clearAnalyzer()
            retired.analysis?.let { retired.provider?.unbind(it) }
            if (retired.analysis != null && retired.provider?.isBound(retired.analysis) == true) {
                throw IllegalStateException("analysis remained bound after unbind")
            }
            if (retired.camera == null) {
                // No bind attempted means no capture existed. A failed bind
                // without a Camera readback is uncertain, rather than proof.
                captureClosed = !wasBinding
                if (wasBinding) {
                    closeFailure = IllegalStateException("failed bind has no physical Camera readback")
                    failed = true
                }
            } else {
                val observer = Observer<CameraState> { state ->
                    if (state?.type == CameraState.Type.CLOSED) {
                        captureClosed = true
                        finishIfReady()
                    }
                }
                cameraObserver = observer
                retired.camera.cameraInfo.cameraState.observeForever(observer)
            }
        } catch (e: Exception) {
            closeFailure = closeFailure ?: e
            failed = true
        }
        try {
            inferenceExecutor.execute {
                var modelFailure: Exception? = null
                // Serialized after in-flight detect. Attempt both close calls
                // even if the first fails; the failure remains sticky.
                retired.markers.forEach { marker ->
                    try { marker.close() } catch (e: Exception) { modelFailure = modelFailure ?: e }
                }
                mainHandler.post {
                    if (modelFailure != null) {
                        closeFailure = closeFailure ?: modelFailure
                        failed = true
                    }
                    modelsClosed = true
                    finishIfReady()
                }
            }
        } catch (e: Exception) {
            closeFailure = closeFailure ?: e
            failed = true
            modelsClosed = true
        }
        finishIfReady()

        droppedGeneration = activeGeneration
        droppedSinceLastEmit = 0
        inferenceBusyGeneration = 0

        if (cancelPendingStart && pending != null) {
            pending.result.error(
                "session-interrupted",
                "camera start was interrupted by lifecycle teardown",
                null,
            )
        }
    }

    // ── Inference (latest-wins with drop accounting) ───────────────────────

    private fun analyze(proxy: ImageProxy, generation: Long) {
        if (!isCurrentGeneration(generation)) {
            proxy.close()
            return
        }
        if (inferenceBusyGeneration == generation) {
            // KEEP_ONLY_LATEST already discarded intermediates silently; this
            // counts the ones that reach us while the model is still busy.
            if (droppedGeneration == generation) droppedSinceLastEmit += 1
            proxy.close()
            return
        }
        inferenceBusyGeneration = generation

        // Copy out of the proxy so the camera can reuse the buffer immediately.
        val rotation = proxy.imageInfo.rotationDegrees
        // Image timestamp domain matches SENSOR_INFO_TIMESTAMP_SOURCE; when
        // REALTIME it is elapsedRealtimeNanos — monotonic. µs for the wire.
        val tUs = proxy.imageInfo.timestamp / 1000
        val bitmap: Bitmap = try {
            proxy.toBitmap()
        } catch (_: Exception) {
            if (inferenceBusyGeneration == generation) inferenceBusyGeneration = 0
            return
        } finally {
            proxy.close()
        }

        val dropped = if (droppedGeneration == generation) {
            droppedSinceLastEmit.also { droppedSinceLastEmit = 0 }
        } else {
            0
        }
        val currentPlan = plan

        inferenceExecutor.execute {
            try {
                if (isCurrentGeneration(generation)) {
                    emitEnvelope(
                        bitmap,
                        rotation,
                        tUs,
                        dropped,
                        currentPlan,
                        generation,
                    )
                }
            } finally {
                if (inferenceBusyGeneration == generation) {
                    inferenceBusyGeneration = 0
                }
            }
        }
    }

    private fun emitEnvelope(
        bitmap: Bitmap,
        sensorRotation: Int,
        tUs: Long,
        dropped: Int,
        plan: String,
        generation: Long,
    ) {
        if (!isCurrentGeneration(generation)) return
        val tasks = poseTasks ?: return
        val started = SystemClock.elapsedRealtimeNanos()
        val image = BitmapImageBuilder(bitmap).build()

        fun run(inverted: Boolean): FloatArray? {
            if (!isCurrentGeneration(generation)) return null
            // Sensor rotation normalizes to portrait; the inverted pass adds
            // 180° on top. MediaPipe maps landmarks back into the UNROTATED
            // input space for the sensor rotation, so only OUR extra 180°
            // needs manual map-back (x→1-x, y→1-y, no L/R index swap).
            val degrees = (sensorRotation + if (inverted) 180 else 0) % 360
            val processing = ImageProcessingOptions.builder()
                .setRotationDegrees(degrees).build()
            val result = try {
                tasks.task(inverted).detectForVideo(image, processing, tUs / 1000)
            } catch (e: Exception) {
                return null
            }
            val pose = result.landmarks().firstOrNull() ?: return null
            val floats = FloatArray(132)
            pose.forEachIndexed { i, landmark ->
                if (i < 33) {
                    val x = if (inverted) 1f - landmark.x() else landmark.x()
                    val y = if (inverted) 1f - landmark.y() else landmark.y()
                    floats[i * 4] = x
                    floats[i * 4 + 1] = y
                    floats[i * 4 + 2] = landmark.z()
                    floats[i * 4 + 3] = landmark.visibility().orElse(0f)
                }
            }
            return floats
        }

        val portrait = sensorRotation % 180 != 0
        val envelope = HashMap<String, Any?>()
        envelope["t"] = tUs
        envelope["w"] = if (portrait) bitmap.height else bitmap.width
        envelope["h"] = if (portrait) bitmap.width else bitmap.height
        envelope["model"] = modelString
        envelope["clock"] = clockDomain
        envelope["dropped"] = dropped
        lifecycle.currentOwner()?.let {
            envelope["ownerId"] = it
            envelope["generation"] = generation
        }
        try {
            if (plan == "upright" || plan == "dual") envelope["up"] = run(inverted = false)
            if (plan == "inverted" || plan == "dual") envelope["inv"] = run(inverted = true)
        } finally {
            image.close()
        }
        envelope["infUs"] =
            ((SystemClock.elapsedRealtimeNanos() - started) / 1000).toInt()

        mainHandler.post {
            if (!isCurrentGeneration(generation)) return@post
            if (frameSinkOwner != null &&
                (frameSinkOwner != lifecycle.currentOwner() || frameSinkGeneration != generation)) return@post
            frameSink?.success(envelope)
        }
    }

    // ── Event channel ──────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (arguments is Map<*, *>) {
            val ownerId = arguments["ownerId"] as? String
            val generation = (arguments["generation"] as? Number)?.toLong()
            if (ownerId == null || generation == null || lifecycle.currentOwner() != ownerId ||
                !lifecycle.isCurrent(generation)) {
                events?.error("session-interrupted", "stream owner retired", null)
                return
            }
            frameSinkOwner = ownerId
            frameSinkGeneration = generation
        } else {
            frameSinkOwner = null
            frameSinkGeneration = null
        }
        frameSink = events
    }

    override fun onCancel(arguments: Any?) {
        if (arguments is Map<*, *>) {
            val ownerId = arguments["ownerId"] as? String ?: return
            val generation = (arguments["generation"] as? Number)?.toLong() ?: return
            if (frameSinkOwner == ownerId && frameSinkGeneration == generation) {
                frameSink = null
                frameSinkOwner = null
                frameSinkGeneration = null
            }
            if (lifecycle.currentOwner() == ownerId && lifecycle.isCurrent(generation)) {
                tearDown(ownerId = ownerId, scoped = true)
            }
            return
        }
        // Flutter cancels a replaced listener with null arguments. Retain
        // that listener's identity rather than stopping the global successor.
        frameSinkOwner?.let { ownerId ->
            val listenerGeneration = frameSinkGeneration
            frameSink = null
            frameSinkOwner = null
            frameSinkGeneration = null
            if (listenerGeneration != null && lifecycle.currentOwner() == ownerId &&
                lifecycle.isCurrent(listenerGeneration)) tearDown(ownerId = ownerId, scoped = true)
            return
        }
        frameSink = null
        frameSinkOwner = null
        frameSinkGeneration = null
        tearDown()
    }
}
