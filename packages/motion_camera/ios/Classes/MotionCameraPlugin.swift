import AVFoundation
import Flutter
import MediaPipeTasksVision
import UIKit

/// ⚠️ PROVISIONAL — written against MediaPipeTasksVision 0.10.21 (M-L-02 pin)
/// but NOT yet compiled or run on a device. Liveness (a real session emitting
/// envelopes) is a separate, named step; until it happens this file is design
/// made concrete, not a working bridge (beyan ≠ canlı).
///
/// Contract: docs/70-KAMERA-KOPRUSU-SOZLESMESI.md. Responsibilities of this
/// layer, and nothing more:
///  - own the AVCaptureSession and the PoseLandmarker (.video mode)
///  - latest-wins backpressure: never queue frames, count what was discarded
///  - run the passes the current PassPlan asks for on the SAME pixel buffer;
///    inverted pass = ImageProcessingOptions(rotationDegrees: 180), landmarks
///    mapped back x→1-x, y→1-y (in-plane rotation, no L/R index swap)
///  - stamp envelopes with the capture PTS (host clock — monotonic on iOS)
///  - refuse with named error codes; never request permission itself
public class MotionCameraPlugin: NSObject, FlutterPlugin {
  static let libraryTag = "mp-ios-0.10.21"

  private var control: FlutterMethodChannel!
  private var frameSink: FlutterEventSink?

  private let sessionQueue = DispatchQueue(label: "motion_camera.session")
  private let inferenceQueue = DispatchQueue(label: "motion_camera.inference")

  private var captureSession: AVCaptureSession?
  private var landmarker: PoseLandmarker?
  private var modelString = ""
  private var plan = "upright"

  /// Latest-wins slot + drop accounting. Guarded by `slotLock`: the capture
  /// callback overwrites, the inference loop takes.
  private let slotLock = NSLock()
  private var pendingBuffer: CVPixelBuffer?
  private var pendingTimestampUs: Int64 = 0
  private var droppedSinceLastEmit = 0
  private var inferenceBusy = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MotionCameraPlugin()
    instance.control = FlutterMethodChannel(
      name: "motion_camera/control", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.control)
    FlutterEventChannel(
      name: "motion_camera/frames", binaryMessenger: registrar.messenger()
    ).setStreamHandler(instance)
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
      guard captureSession != nil else {
        result(FlutterError(code: "not-running", message: "no active session", details: nil))
        return
      }
      slotLock.lock(); plan = newPlan; slotLock.unlock()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Session lifecycle

  private func start(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard captureSession == nil else {
      result(FlutterError(code: "already-running", message: "a session is active", details: nil))
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
    do {
      landmarker = try PoseLandmarker(options: options)
    } catch {
      result(FlutterError(
        code: "model-load-failed",
        message: "PoseLandmarker rejected \(modelPath): \(error.localizedDescription)",
        details: nil))
      return
    }
    modelString = "\(Self.libraryTag)+\(modelId)"
    plan = initialPlan

    let position: AVCaptureDevice.Position = lens == "back" ? .back : .front
    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera, for: .video, position: position),
      let input = try? AVCaptureDeviceInput(device: device) else {
      landmarker = nil
      result(FlutterError(code: "no-such-camera", message: "no \(lens) camera", details: nil))
      return
    }

    let session = AVCaptureSession()
    session.sessionPreset = .hd1280x720
    session.addInput(input)
    let output = AVCaptureVideoDataOutput()
    output.videoSettings =
      [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: sessionQueue)
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

    captureSession = session
    sessionQueue.async { session.startRunning() }

    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    // After portrait normalization width/height swap relative to the sensor.
    result([
      "w": Int(min(dims.width, dims.height)),
      "h": Int(max(dims.width, dims.height)),
      // CMSampleBuffer PTS rides the host clock (mach_absolute_time family):
      // monotonic by platform guarantee on iOS.
      "clock": "monotonic",
      "library": Self.libraryTag,
    ])
  }

  private func stop(result: @escaping FlutterResult) {
    guard let session = captureSession else {
      result(FlutterError(code: "not-running", message: "no active session", details: nil))
      return
    }
    sessionQueue.async { session.stopRunning() }
    captureSession = nil
    landmarker = nil
    slotLock.lock()
    pendingBuffer = nil
    droppedSinceLastEmit = 0
    inferenceBusy = false
    slotLock.unlock()
    result(nil)
  }

  // MARK: - Inference

  private func drainSlot() {
    slotLock.lock()
    guard !inferenceBusy, let buffer = pendingBuffer else {
      slotLock.unlock()
      return
    }
    let tUs = pendingTimestampUs
    let dropped = droppedSinceLastEmit
    let currentPlan = plan
    pendingBuffer = nil
    droppedSinceLastEmit = 0
    inferenceBusy = true
    slotLock.unlock()

    inferenceQueue.async { [weak self] in
      self?.infer(buffer: buffer, tUs: tUs, dropped: dropped, plan: currentPlan)
      self?.slotLock.lock()
      self?.inferenceBusy = false
      self?.slotLock.unlock()
      self?.drainSlot()  // a frame may have landed while we were busy
    }
  }

  private func infer(buffer: CVPixelBuffer, tUs: Int64, dropped: Int, plan: String) {
    guard let landmarker = landmarker else { return }
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
      self?.frameSink?(envelope)
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
    if pendingBuffer != nil {
      // Inference has not taken the previous frame: it is now stale.
      // Coaching on old frames is lying about the present — drop and count.
      droppedSinceLastEmit += 1
    }
    pendingBuffer = buffer
    pendingTimestampUs = tUs
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
    return nil
  }
}
