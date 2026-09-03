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
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
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
import java.util.concurrent.atomic.AtomicLong

/**
 * ⚠️ PROVISIONAL — written against tasks-vision 0.10.29 (M-L-02 pin) but NOT
 * yet compiled or run on a device. Liveness (a real session emitting
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
    private val mainHandler = Handler(Looper.getMainLooper())

    private var inferenceExecutor = Executors.newSingleThreadExecutor()
    private var analysisExecutor = Executors.newSingleThreadExecutor()

    private var activityBinding: ActivityPluginBinding? = null
    private var activityLifecycleOwner: LifecycleOwner? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var landmarker: PoseLandmarker? = null
    private var pendingLandmarker: PoseLandmarker? = null
    private var modelString = ""
    @Volatile private var plan = "upright"
    @Volatile private var clockDomain = "unknown"
    private val generationCounter = AtomicLong(0)
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
            "start" -> start(call, result)
            "stop" -> stop(result)
            "setPassPlan" -> {
                val newPlan = call.argument<String>("plan")
                if (newPlan == null) {
                    result.error("bad-arguments", "plan missing", null); return
                }
                if (!sessionActive || cameraProvider == null) {
                    result.error("not-running", "no active session", null); return
                }
                plan = newPlan
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Session lifecycle ──────────────────────────────────────────────────

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (sessionActive) {
            result.error("already-running", "a session is active", null); return
        }
        val modelPath = call.argument<String>("modelPath")
        val modelId = call.argument<String>("modelId")
        val lens = call.argument<String>("lens")
        val initialPlan = call.argument<String>("plan")
        if (modelPath == null || modelId == null || lens == null || initialPlan == null) {
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

        val candidateLandmarker = try {
            PoseLandmarker.createFromOptions(
                context,
                PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(
                        BaseOptions.builder().setModelAssetPath(modelPath).build()
                    )
                    // VIDEO mode: sync per-frame, required for dual-pass on one image.
                    .setRunningMode(RunningMode.VIDEO)
                    .setNumPoses(1)
                    .build()
            )
        } catch (e: Exception) {
            result.error(
                "model-load-failed",
                "PoseLandmarker rejected $modelPath: ${e.message}", null
            ); return
        }

        val generation = generationCounter.incrementAndGet()
        activeGeneration = generation
        sessionActive = true
        droppedGeneration = generation
        droppedSinceLastEmit = 0
        inferenceBusyGeneration = 0
        pendingLandmarker = candidateLandmarker
        pendingStart = PendingStart(generation, result)
        modelString = "$LIBRARY_TAG+$modelId"
        plan = initialPlan

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

                val camera = provider.bindToLifecycle(owner, selector, analysis)
                cameraProvider = provider
                imageAnalysis = analysis
                landmarker = candidateLandmarker
                if (pendingLandmarker === candidateLandmarker) {
                    pendingLandmarker = null
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
                    mapOf(
                        // Portrait-normalized like iOS: min/max of the pair.
                        "w" to (res?.let { minOf(it.width, it.height) } ?: 0),
                        "h" to (res?.let { maxOf(it.width, it.height) } ?: 0),
                        "clock" to clockDomain,
                        "library" to LIBRARY_TAG,
                    ),
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
        tearDown()
        result.success(null)
    }

    private fun isCurrentGeneration(generation: Long): Boolean =
        sessionActive && activeGeneration == generation

    /**
     * The one teardown path for explicit stop, stream cancellation, Activity
     * stop/detach (including config changes), and engine detach. Invalidate
     * first: already queued analyzer/inference/main-thread callbacks become
     * harmless before any native resource is released.
     */
    private fun tearDown(cancelPendingStart: Boolean = true) {
        sessionActive = false
        activeGeneration = generationCounter.incrementAndGet()

        val pending = pendingStart
        pendingStart = null

        runCatching { imageAnalysis?.clearAnalyzer() }
        val analysis = imageAnalysis
        imageAnalysis = null
        cameraProvider?.let { provider ->
            if (analysis != null) runCatching { provider.unbind(analysis) }
        }
        cameraProvider = null

        val markers = listOfNotNull(landmarker, pendingLandmarker).distinct()
        landmarker = null
        pendingLandmarker = null
        markers.forEach { marker ->
            // Serialized after any in-flight detectForVideo call.
            inferenceExecutor.execute { marker.close() }
        }

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
        val lm = landmarker ?: return
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
                lm.detectForVideo(image, processing, tUs / 1000)
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
        if (plan == "upright" || plan == "dual") envelope["up"] = run(inverted = false)
        if (plan == "inverted" || plan == "dual") envelope["inv"] = run(inverted = true)
        envelope["infUs"] =
            ((SystemClock.elapsedRealtimeNanos() - started) / 1000).toInt()

        mainHandler.post {
            if (!isCurrentGeneration(generation)) return@post
            frameSink?.success(envelope)
        }
    }

    // ── Event channel ──────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        frameSink = events
    }

    override fun onCancel(arguments: Any?) {
        frameSink = null
        tearDown()
    }
}
