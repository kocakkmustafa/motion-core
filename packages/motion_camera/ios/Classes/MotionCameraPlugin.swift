import AVFoundation
import Flutter
import MediaPipeTasksVision
import UIKit

/// ⚠️ COMPILED, NOT YET RUN — first compiled against MediaPipeTasksVision
/// 0.10.21 on 2026-07-30 (J-071: two real breaks found and fixed by reading
/// the pod's own headers). Device liveness (a real session emitting
/// envelopes) remains a separate, named step — "derleniyor ≠ çalışıyor";
/// until §7.3-7.7 run on hardware this is a compiling bridge, not a proven
/// one.
///
/// Contract: docs/70-KAMERA-KOPRUSU-SOZLESMESI.md. Responsibilities of this
/// layer, and nothing more:
///  - own the AVCaptureSession and the PoseLandmarker (.video mode)
///  - latest-wins backpressure: never queue frames, count what was discarded
///  - run the passes the current PassPlan asks for on the SAME pixel buffer;
///    inverted pass = MPImage(pixelBuffer:orientation: .down) (0.10.21's
///    in-plane-rotation surface), landmarks mapped back x→1-x, y→1-y
///    (in-plane rotation, no L/R index swap)
///  - stamp envelopes with the capture PTS (host clock — monotonic on iOS)
///  - refuse with named error codes; never request permission itself
public class MotionCameraPlugin: NSObject, FlutterPlugin {
  static let libraryTag = "mp-ios-0.10.21"

  private var control: FlutterMethodChannel?
  private var frames: FlutterEventChannel?
  private var frameSink: FlutterEventSink?
  private var applicationStateObserver: NSObjectProtocol?

  private let sessionQueue = DispatchQueue(label: "motion_camera.session")
  private let inferenceQueue = DispatchQueue(label: "motion_camera.inference")

  private var captureSession: AVCaptureSession?
  private var videoOutput: AVCaptureVideoDataOutput?
  private var landmarker: PoseLandmarker?
  private var modelString = ""
  private var plan = "upright"

  /// Latest-wins slot + drop accounting. Guarded by `slotLock`: the capture
  /// callback overwrites, the inference loop takes.
  private let slotLock = NSLock()
  private var pendingBuffer: CVPixelBuffer?
  private var pendingTimestampUs: Int64 = 0
  private var pendingGeneration: UInt64 = 0
  private var droppedSinceLastEmit = 0
  private var inferenceBusyGeneration: UInt64?
  private var generation: UInt64 = 0
  private var sessionActive = false

  private struct PendingStart {
    let generation: UInt64
    let result: FlutterResult
  }

  private var pendingStart: PendingStart?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MotionCameraPlugin()
    let control = FlutterMethodChannel(
      name: "motion_camera/control", binaryMessenger: registrar.messenger())
    let frames = FlutterEventChannel(
      name: "motion_camera/frames", binaryMessenger: registrar.messenger()
    )
    instance.control = control
    instance.frames = frames
    registrar.addMethodCallDelegate(instance, channel: control)
    frames.setStreamHandler(instance)
    registrar.publish(instance)
    instance.observeApplicationLifecycle()
  }

  private func observeApplicationLifecycle() {
    applicationStateObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.tearDown()
    }
  }

  @objc(detachFromEngineForRegistrar:)
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    tearDown()
    frameSink = nil
    frames?.setStreamHandler(nil)
    frames = nil
    control = nil
    if let observer = applicationStateObserver {
      NotificationCenter.default.removeObserver(observer)
      applicationStateObserver = nil
    }
  }

  deinit {
    if let observer = applicationStateObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      start(call, result: result)
    case "stop":
      stop(result: result)
    case "setPassPlan":
      guard let args = call.arguments as? [String: Any],
            let newPlan = args["plan"] as? String else {
        result(FlutterError(code: "bad-arguments", message: "plan missing", details: nil))
        return
      }
      slotLock.lock()
      let canUpdatePlan = sessionActive && captureSession != nil
      if canUpdatePlan { plan = newPlan }
      slotLock.unlock()
      guard canUpdatePlan else {
        result(FlutterError(code: "not-running", message: "no active session", details: nil))
        return
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Session lifecycle

  private func start(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    slotLock.lock()
    let alreadyActive = sessionActive
    slotLock.unlock()
    guard !alreadyActive else {
      result(FlutterError(code: "already-running", message: "a session is active", details: nil))
      return
    }
    guard UIApplication.shared.applicationState == .active else {
      result(FlutterError(
        code: "lifecycle-unavailable",
        message: "the application must be active before camera capture starts",
        details: nil))
      return
    }
    guard let args = call.arguments as? [String: Any],
          let modelPath = args["modelPath"] as? String,
          let modelId = args["modelId"] as? String,
          let lens = args["lens"] as? String,
          let initialPlan = args["plan"] as? String else {
      result(FlutterError(code: "bad-arguments", message: "start arguments incomplete", details: nil))
      return
    }

    // The plugin never ASKS for permission — it refuses with a name the app
    // can route to its own permission UX.
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
      result(FlutterError(
        code: "camera-permission-denied",
        message: "camera permission is not granted; the app must request it first",
        details: nil))
      return
    }

    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.runningMode = .video  // sync per-frame: required for dual-pass on one buffer
    options.numPoses = 1
    let candidateLandmarker: PoseLandmarker
    do {
      candidateLandmarker = try PoseLandmarker(options: options)
    } catch {
      result(FlutterError(
        code: "model-load-failed",
        message: "PoseLandmarker rejected \(modelPath): \(error.localizedDescription)",
        details: nil))
      return
    }
    let position: AVCaptureDevice.Position = lens == "back" ? .back : .front
    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera, for: .video, position: position),
      let input = try? AVCaptureDeviceInput(device: device) else {
      result(FlutterError(code: "no-such-camera", message: "no \(lens) camera", details: nil))
      return
    }

    let session = AVCaptureSession()
    session.sessionPreset = .hd1280x720
    guard session.canAddInput(input) else {
      result(FlutterError(code: "no-such-camera", message: "camera input unavailable", details: nil))
      return
    }
    session.addInput(input)
    let output = AVCaptureVideoDataOutput()
    output.videoSettings =
      [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: sessionQueue)
    guard session.canAddOutput(output) else {
      output.setSampleBufferDelegate(nil, queue: nil)
      result(FlutterError(code: "no-such-camera", message: "camera output unavailable", details: nil))
      return
    }
    session.addOutput(output)

    // Normalize the connection so emitted w×h and landmark space are portrait
    // regardless of sensor mounting.
    if let connection = output.connection(with: .video) {
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }
      if position == .front && connection.isVideoMirroringSupported {
        // The engine judges the BODY, not the selfie preview — un-mirror so
        // "left wrist" means the subject's anatomical left (mirror-mode
        // teaching is a core-side decision via PoseFrame.mirrored()).
        connection.isVideoMirrored = false
      }
    }

    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    let sessionInfo: [String: Any] = [
      "w": Int(min(dims.width, dims.height)),
      "h": Int(max(dims.width, dims.height)),
      // CMSampleBuffer PTS rides the host clock (mach_absolute_time family):
      // monotonic by platform guarantee on iOS.
      "clock": "monotonic",
      "library": Self.libraryTag,
    ]

    slotLock.lock()
    generation &+= 1
    let currentGeneration = generation
    sessionActive = true
    captureSession = session
    videoOutput = output
    landmarker = candidateLandmarker
    modelString = "\(Self.libraryTag)+\(modelId)"
    plan = initialPlan
    pendingBuffer = nil
    pendingGeneration = currentGeneration
    droppedSinceLastEmit = 0
    inferenceBusyGeneration = nil
    pendingStart = PendingStart(generation: currentGeneration, result: result)
    slotLock.unlock()

    sessionQueue.async { [weak self] in
      guard let self else { return }
      guard self.isCurrentGeneration(currentGeneration) else { return }
      session.startRunning()
      let isRunning = session.isRunning
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard self.isCurrentGeneration(currentGeneration) else { return }
        if isRunning {
          self.completeStart(generation: currentGeneration, info: sessionInfo)
        } else {
          self.failStart(
            generation: currentGeneration,
            code: "no-such-camera",
            message: "camera session did not start")
        }
      }
    }
  }

  private func stop(result: @escaping FlutterResult) {
    tearDown {
      result(nil)
    }
  }

  private func completeStart(generation: UInt64, info: [String: Any]) {
    slotLock.lock()
    let pending = pendingStart
    let canComplete = sessionActive
      && self.generation == generation
      && pending?.generation == generation
    if canComplete { pendingStart = nil }
    slotLock.unlock()
    if canComplete { pending?.result(info) }
  }

  private func failStart(generation: UInt64, code: String, message: String) {
    slotLock.lock()
    let pending = pendingStart
    let canFail = sessionActive
      && self.generation == generation
      && pending?.generation == generation
    if canFail { pendingStart = nil }
    slotLock.unlock()
    guard canFail else { return }
    tearDown(cancelPendingStart: false)
    pending?.result(FlutterError(code: code, message: message, details: nil))
  }

  private func isCurrentGeneration(_ candidate: UInt64) -> Bool {
    slotLock.lock()
    let current = sessionActive && generation == candidate
    slotLock.unlock()
    return current
  }

  /// Shared, idempotent teardown for stop, stream cancellation, application
  /// deactivation, and engine detach. Generation is invalidated before
  /// native resources are released, so queued callbacks fail closed.
  private func tearDown(
    cancelPendingStart: Bool = true,
    completion: (() -> Void)? = nil
  ) {
    slotLock.lock()
    generation &+= 1
    sessionActive = false
    let session = captureSession
    let output = videoOutput
    let pending = pendingStart
    captureSession = nil
    videoOutput = nil
    landmarker = nil
    pendingStart = nil
    pendingBuffer = nil
    pendingGeneration = generation
    droppedSinceLastEmit = 0
    inferenceBusyGeneration = nil
    slotLock.unlock()

    output?.setSampleBufferDelegate(nil, queue: nil)
    if let session {
      sessionQueue.async {
        if session.isRunning { session.stopRunning() }
        guard let completion else { return }
        DispatchQueue.main.async(execute: completion)
      }
    } else {
      completeOnMain(completion)
    }

    if cancelPendingStart, let pending {
      let error = FlutterError(
        code: "session-interrupted",
        message: "camera start was interrupted by lifecycle teardown",
        details: nil)
      if Thread.isMainThread {
        pending.result(error)
      } else {
        DispatchQueue.main.async { pending.result(error) }
      }
    }
  }

  private func completeOnMain(_ completion: (() -> Void)?) {
    guard let completion else { return }
    if Thread.isMainThread {
      completion()
    } else {
      DispatchQueue.main.async(execute: completion)
    }
  }

  // MARK: - Inference

  private func drainSlot() {
    slotLock.lock()
    guard sessionActive,
          inferenceBusyGeneration == nil,
          let buffer = pendingBuffer,
          pendingGeneration == generation,
          let currentLandmarker = landmarker else {
      slotLock.unlock()
      return
    }
    let generation = pendingGeneration
    let tUs = pendingTimestampUs
    let dropped = droppedSinceLastEmit
    let currentPlan = plan
    let currentModelString = modelString
    pendingBuffer = nil
    droppedSinceLastEmit = 0
    inferenceBusyGeneration = generation
    slotLock.unlock()

    inferenceQueue.async { [weak self] in
      guard let self else { return }
      if self.isCurrentGeneration(generation) {
        self.infer(
          buffer: buffer,
          tUs: tUs,
          dropped: dropped,
          plan: currentPlan,
          landmarker: currentLandmarker,
          modelString: currentModelString,
          generation: generation)
      }
      self.slotLock.lock()
      if self.inferenceBusyGeneration == generation {
        self.inferenceBusyGeneration = nil
      }
      let shouldDrain = self.sessionActive && self.generation == generation
      self.slotLock.unlock()
      if shouldDrain { self.drainSlot() }  // a frame may have landed while busy
    }
  }

  private func infer(
    buffer: CVPixelBuffer,
    tUs: Int64,
    dropped: Int,
    plan: String,
    landmarker: PoseLandmarker,
    modelString: String,
    generation: UInt64
  ) {
    guard isCurrentGeneration(generation) else { return }
    let started = DispatchTime.now()
    var envelope: [String: Any] = [
      "t": tUs,
      "w": CVPixelBufferGetWidth(buffer),
      "h": CVPixelBufferGetHeight(buffer),
      "model": modelString,
      "clock": "monotonic",
      "dropped": dropped,
    ]

    func run(rotated: Bool) -> FlutterStandardTypedData? {
      guard isCurrentGeneration(generation) else { return nil }
      // ROTATION LIVES ON THE IMAGE, not on a separate options object.
      // Measured against the pin (J-071, first compile ever): 0.10.21 has
      // NO `ImageProcessingOptions` type at all, and
      // `detect(videoFrame:timestampInMilliseconds:)` takes no
      // `imageProcessingOptions:` argument — both were compile errors. The
      // version's own way to express in-plane rotation is
      // `MPImage(pixelBuffer:orientation:)`, where `.down` is 180°.
      //
      // Semantics are PRESERVED: MediaPipe rotates a copy before inference
      // and returns coordinates in the ROTATED frame, so the back-mapping
      // below (x→1-x, y→1-y, no index swap) stays exactly as it was.
      guard
        let image = try? MPImage(
          pixelBuffer: buffer,
          orientation: rotated ? .down : .up)
      else { return nil }
      guard
        let result = try? landmarker.detect(
          videoFrame: image,
          timestampInMilliseconds: Int(tUs / 1000)),
        let pose = result.landmarks.first
      else { return nil }  // model saw no person → pass value null
      var floats = [Float32](repeating: 0, count: 132)
      for (i, lm) in pose.enumerated() where i < 33 {
        // Inverted pass: map back to the original frame of reference.
        // 180° in-plane rotation → x→1-x, y→1-y, NO left/right index swap.
        let x = rotated ? 1 - lm.x : lm.x
        let y = rotated ? 1 - lm.y : lm.y
        floats[i * 4] = x
        floats[i * 4 + 1] = y
        floats[i * 4 + 2] = lm.z
        floats[i * 4 + 3] = lm.visibility?.floatValue ?? 0
      }
      return FlutterStandardTypedData(
        float32: Data(bytes: floats, count: floats.count * 4))
    }

    if plan == "upright" || plan == "dual" {
      envelope["up"] = run(rotated: false) ?? NSNull()
    }
    if plan == "inverted" || plan == "dual" {
      envelope["inv"] = run(rotated: true) ?? NSNull()
    }
    envelope["infUs"] =
      Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1000)

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.isCurrentGeneration(generation) else { return }
      self.frameSink?(envelope)
    }
  }
}

// MARK: - Capture delegate (latest-wins)

extension MotionCameraPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let tUs = Int64(CMTimeGetSeconds(pts) * 1_000_000)

    slotLock.lock()
    guard sessionActive,
          let activeOutput = videoOutput,
          output === activeOutput else {
      slotLock.unlock()
      return
    }
    let currentGeneration = generation
    if pendingBuffer != nil && pendingGeneration == currentGeneration {
      // Inference has not taken the previous frame: it is now stale.
      // Coaching on old frames is lying about the present — drop and count.
      droppedSinceLastEmit += 1
    }
    pendingBuffer = buffer
    pendingTimestampUs = tUs
    pendingGeneration = currentGeneration
    slotLock.unlock()
    drainSlot()
  }
}

// MARK: - Event channel

extension MotionCameraPlugin: FlutterStreamHandler {
  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    frameSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    frameSink = nil
    tearDown()
    return nil
  }
}
