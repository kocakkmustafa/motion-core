import AVFoundation
import Flutter
import MediaPipeTasksVision
import UIKit

/// ⚠️ CURRENT OWNED BRIDGE NOT YET COMPILED OR RUN — the older bridge first
/// compiled against MediaPipeTasksVision 0.10.21 on 2026-07-30 (J-071).
/// Host helper tests do not compile this framework bridge. Device liveness
/// (a real session emitting
/// envelopes) remains a separate, named step — "derleniyor ≠ çalışıyor";
/// Current framework compilation and §7.3-7.7 hardware acceptance remain open.
///
/// Contract: docs/70-KAMERA-KOPRUSU-SOZLESMESI.md. Responsibilities of this
/// layer, and nothing more:
///  - own the AVCaptureSession and two orientation PoseLandmarker VIDEO graphs
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
  private var frameSinkOwner: String?
  private var frameSinkGeneration: UInt64?
  private var applicationStateObserver: NSObjectProtocol?

  private let sessionQueue = DispatchQueue(label: "motion_camera.session")
  private let inferenceQueue = DispatchQueue(label: "motion_camera.inference")

  private var captureSession: AVCaptureSession?
  private var videoOutput: AVCaptureVideoDataOutput?
  private var poseTasks: OrientedCaptureTasks<PoseLandmarker>?
  private let lifecycle = CaptureLifecycle()
  private final class RetiredCapture {
    let session: AVCaptureSession?
    var tasks: OrientedCaptureTasks<PoseLandmarker>?
    init(session: AVCaptureSession?, tasks: OrientedCaptureTasks<PoseLandmarker>?) {
      self.session = session
      self.tasks = tasks
    }
  }
  private var closingResources: RetiredCapture?
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
    case "start", "startOwned":
      start(call, result: result)
    case "stop":
      stop(result: result)
    case "stopOwned":
      guard let owner = ownedArgument(call) else {
        result(FlutterError(code: "bad-arguments", message: "ownerId missing", details: nil))
        return
      }
      tearDown(ownerId: owner, scoped: true) { [weak self] closed in
        guard let self else { return }
        result(closed ? self.lifecycle.observation(ownerId: owner) : self.closeError())
      }
    case "readback":
      guard let owner = ownedArgument(call),
            let args = call.arguments as? [String: Any],
            let nonce = args["nonce"] as? NSNumber, nonce.intValue > 0 else {
        result(FlutterError(code: "bad-arguments", message: "ownerId/nonce missing", details: nil))
        return
      }
      result(lifecycle.observation(ownerId: owner, nonce: nonce.intValue))
    case "setPassPlan", "setPassPlanOwned":
      guard let args = call.arguments as? [String: Any],
            let newPlan = args["plan"] as? String,
            ["upright", "inverted", "dual"].contains(newPlan) else {
        result(FlutterError(code: "bad-arguments", message: "plan missing", details: nil))
        return
      }
      if call.method == "setPassPlanOwned" {
        guard let owner = ownedArgument(call),
              let requestedGeneration = args["generation"] as? NSNumber,
              lifecycle.currentOwner() == owner,
              lifecycle.isCurrent(requestedGeneration.uint64Value) else {
          result(FlutterError(code: "session-interrupted", message: "capture owner retired", details: nil))
          return
        }
      }
      slotLock.lock()
      let canUpdatePlan = sessionActive && captureSession != nil
      if canUpdatePlan { plan = newPlan }
      slotLock.unlock()
      guard canUpdatePlan else {
        result(FlutterError(code: "not-running", message: "no active session", details: nil))
        return
      }
      if call.method == "setPassPlanOwned", let owner = ownedArgument(call) {
        result(lifecycle.observation(ownerId: owner))
      } else { result(nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Session lifecycle

  private func ownedArgument(_ call: FlutterMethodCall) -> String? {
    guard let args = call.arguments as? [String: Any],
          let owner = args["ownerId"] as? String,
          !owner.isEmpty, owner.count <= 128 else { return nil }
    return owner
  }

  private func closeError() -> FlutterError {
    FlutterError(code: "close-uncertain", message: "capture/model closure is uncertain", details: nil)
  }

  private func start(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if let code = lifecycle.startRefusalCode() {
      result(FlutterError(code: code, message: "capture is active or closing", details: nil))
      return
    }
    let ownerId = call.method == "startOwned" ? ownedArgument(call) : nil
    if call.method == "startOwned", ownerId == nil {
      result(FlutterError(code: "bad-arguments", message: "ownerId missing", details: nil))
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
          let initialPlan = args["plan"] as? String,
          ["upright", "inverted", "dual"].contains(initialPlan) else {
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
    options.runningMode = .video
    options.numPoses = 1
    let candidateTasks: OrientedCaptureTasks<PoseLandmarker>
    do {
      // Each VIDEO graph owns tracking/timestamp state for one orientation.
      // Both receive the original capture PTS; no artificial timestamp offset.
      candidateTasks = try OrientedCaptureTasks(
        upright: PoseLandmarker(options: options),
        inverted: PoseLandmarker(options: options))
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
    let currentGeneration: UInt64
    do { currentGeneration = try lifecycle.begin(ownerId: ownerId) }
    catch {
      output.setSampleBufferDelegate(nil, queue: nil)
      result(closeError())
      return
    }
    var sessionInfo: [String: Any] = [
      "w": Int(min(dims.width, dims.height)),
      "h": Int(max(dims.width, dims.height)),
      // CMSampleBuffer PTS rides the host clock (mach_absolute_time family):
      // monotonic by platform guarantee on iOS.
      "clock": "monotonic",
      "library": Self.libraryTag,
    ]
    if let ownerId {
      sessionInfo["protocol"] = 1
      sessionInfo["ownerId"] = ownerId
      sessionInfo["generation"] = currentGeneration
    }

    slotLock.lock()
    generation = currentGeneration
    sessionActive = true
    captureSession = session
    videoOutput = output
    poseTasks = candidateTasks
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
    tearDown { [weak self] closed in
      result(closed ? nil : self?.closeError())
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
    if canComplete && lifecycle.markRunning(generation) { pending?.result(info) }
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
    return current && lifecycle.isCurrent(candidate)
  }

  /// Shared, idempotent teardown for stop, stream cancellation, application
  /// deactivation, and engine detach. Generation is invalidated before
  /// native resources are released, so queued callbacks fail closed.
  private func tearDown(
    cancelPendingStart: Bool = true,
    ownerId: String? = nil,
    scoped: Bool = false,
    completion: ((Bool) -> Void)? = nil
  ) {
    // The helper retains the shared completion before resource fields are
    // cleared. Repeated stop/cancel/background calls can never ACK early.
    let ownsBarrier = lifecycle.requestClose(ownerId: ownerId, scoped: scoped) { closed in
      guard let completion else { return }
      if Thread.isMainThread { completion(closed) }
      else { DispatchQueue.main.async { completion(closed) } }
    }
    guard ownsBarrier else { return }
    slotLock.lock()
    sessionActive = false
    let session = captureSession
    let output = videoOutput
    let pending = pendingStart
    let retired = RetiredCapture(session: session, tasks: poseTasks)
    closingResources = retired
    captureSession = nil
    videoOutput = nil
    poseTasks = nil
    pendingStart = nil
    pendingBuffer = nil
    pendingGeneration = generation
    droppedSinceLastEmit = 0
    inferenceBusyGeneration = nil
    slotLock.unlock()

    output?.setSampleBufferDelegate(nil, queue: nil)
    // Teardown itself owns the resource lifetime, including engine detach.
    // Retain the plugin until the physical stop, model drain, and completion
    // finish; a weak capture could skip stopRunning after registrar release.
    sessionQueue.async {
      if let session = retired.session, session.isRunning { session.stopRunning() }
      let captureClosed = retired.session?.isRunning != true
      // Accepted inference was enqueued while holding slotLock. This barrier
      // therefore runs after every detect holding a task reference. The pinned
      // iOS API has no public close(); releasing the final task pair here uses
      // its ARC destruction contract, after physical stopRunning readback.
      self.inferenceQueue.async {
        if captureClosed { retired.tasks = nil }
        DispatchQueue.main.async {
          if captureClosed { self.closingResources = nil }
          // On failure keep the resources and sticky uncertain state. No new
          // session is permitted while closure cannot be confirmed.
          self.lifecycle.finishClose(success: captureClosed)
        }
      }
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

  // MARK: - Inference

  private func drainSlot() {
    slotLock.lock()
    guard sessionActive,
          inferenceBusyGeneration == nil,
          let buffer = pendingBuffer,
          pendingGeneration == generation,
          let currentTasks = poseTasks else {
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
    // Publish work before releasing the lock, so teardown's inference barrier
    // cannot overtake a task reference captured by this accepted frame.
    inferenceQueue.async { [weak self] in
      guard let self else { return }
      if self.isCurrentGeneration(generation) {
        self.infer(
          buffer: buffer,
          tUs: tUs,
          dropped: dropped,
          plan: currentPlan,
          tasks: currentTasks,
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
    slotLock.unlock()
  }

  private func infer(
    buffer: CVPixelBuffer,
    tUs: Int64,
    dropped: Int,
    plan: String,
    tasks: OrientedCaptureTasks<PoseLandmarker>,
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
    if let owner = lifecycle.currentOwner() {
      envelope["ownerId"] = owner
      envelope["generation"] = generation
    }

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
        let result = try? tasks.task(inverted: rotated).detect(
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
      if let sinkOwner = self.frameSinkOwner {
        guard sinkOwner == self.lifecycle.currentOwner(),
              self.frameSinkGeneration == generation else { return }
      }
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
    if let args = arguments as? [String: Any] {
      guard let owner = args["ownerId"] as? String,
            let requestedGeneration = args["generation"] as? NSNumber,
            lifecycle.currentOwner() == owner,
            lifecycle.isCurrent(requestedGeneration.uint64Value) else {
        return FlutterError(code: "session-interrupted", message: "stream owner retired", details: nil)
      }
      frameSinkOwner = owner
      frameSinkGeneration = requestedGeneration.uint64Value
    } else {
      frameSinkOwner = nil
      frameSinkGeneration = nil
    }
    frameSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let args = arguments as? [String: Any] {
      guard let owner = args["ownerId"] as? String,
            let requestedGeneration = args["generation"] as? NSNumber else {
        return FlutterError(code: "bad-arguments", message: "stream owner missing", details: nil)
      }
      // A retired stream cancellation must not clear a successor's sink.
      if frameSinkOwner == owner && frameSinkGeneration == requestedGeneration.uint64Value {
        frameSink = nil
        frameSinkOwner = nil
        frameSinkGeneration = nil
      }
      if lifecycle.currentOwner() == owner && lifecycle.isCurrent(requestedGeneration.uint64Value) {
        tearDown(ownerId: owner, scoped: true)
      }
      return nil
    }
    // Flutter cancels a replaced listener with nil arguments. Use the stored
    // identity of that listener instead of stopping the global successor.
    if let owner = frameSinkOwner {
      let listenerGeneration = frameSinkGeneration
      frameSink = nil
      frameSinkOwner = nil
      frameSinkGeneration = nil
      if let listenerGeneration, lifecycle.currentOwner() == owner,
         lifecycle.isCurrent(listenerGeneration) { tearDown(ownerId: owner, scoped: true) }
      return nil
    }
    frameSink = nil
    frameSinkOwner = nil
    frameSinkGeneration = nil
    tearDown()
    return nil
  }
}
