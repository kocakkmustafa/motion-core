

# ==== pose-models ====

## SUMMARY
The 2025-2026 on-device mobile pose landscape is dominated by three Google-family options — MediaPipe Pose Landmarker (Tasks API, BlazePose GHUM 3D, 33 landmarks incl. world coords, Apache-2.0, lite/full/heavy variants), Google ML Kit Pose Detection (also 33 landmarks, easier native SDK but explicitly BETA/no-SLA), and MoveNet (17 COCO keypoints only, fastest, Apache-2.0, but too coarse for hand/foot-precision needs). RTMPose/RTMO (OpenMMLab, Apache-2.0) is a credible higher-accuracy alternative with an existing open-source Flutter+ONNX Runtime reference implementation, at the cost of owning your own inference pipeline. YOLO11/YOLOv8-pose is popular but AGPL-3.0-licensed by default — a genuine commercial blocker for closed-source solo apps unless an Ultralytics Enterprise license is purchased. Apple's Vision framework (VNDetectHumanBodyPoseRequest 2D / VNDetectHumanBodyPose3DRequest 3D) and ARKit body tracking are free, mature, on-device, iOS-only options well-suited to a native Swift bridge layer, with 3D Vision requiring a physical device (no Simulator support) and lacking per-joint confidence in ARKit specifically. Meta's Sapiens/Sapiens2 represents the accuracy frontier but is impractical for real-time mobile (0.1B+ params) and carries a non-standard Meta license requiring legal review. MediaPipe Hand Landmarker (21 landmarks/hand, Apache-2.0) remains actively maintained and is directly relevant to Ostinato's bow/finger tracking, though combined pose+hand inference cost on mid-range phones is unverified. QuickPose.ai is a paid black-box SDK wrapper option, native-only (no Flutter SDK), with no public disclosure of its underlying model or inversion-handling. On the critical Gravita sub-question — pose reliability on inverted bodies (handstands/headstands) — direct evidence is thin: no official MediaPipe/ML Kit/Apple documentation was found explicitly addressing inverted-body accuracy or providing benchmarks, and a firsthand-relevant open-source repo (ai-coach-eiji/handstand-v2) documents building a handstand-pose app on MediaPipe but does not discuss any rotation-related failure or workaround. Indirect evidence is more informative: BlazePose's own architecture normalizes rotation/scale via a predicted person-circle (hip midpoint + shoulder-hip incline angle) specifically to be more robust to varied camera/body orientation than plain 2D keypoint models, which is a structural (if unverified for the extreme case) argument in MediaPipe's favor over MoveNet/YOLO-pose. A 2019 arXiv paper on extreme/wild motions (cartwheels, handstands) found pose-tracker confidence dropping when predictions broke continuity with prior frames, motivating data augmentation for such motions (full text wasn't machine-readable in this pass — should be read manually). A more recent (2025) fall-detection paper (VIRA-GCN) demonstrates that explicit multi-angle rotation augmentation (9 vertical x 3 horizontal synthetic viewpoints) plus inference-time multi-view probability averaging took a 3D-skeleton classifier from 94.25% to 99.81% accuracy under rotated/occluded views — strong general evidence that rotation-augmented training and/or test-time rotation ensembling is the standard, effective mitigation pattern, transferable in principle to a Gravita-specific fine-tune or a runtime workaround (e.g., feeding the frame rotated 180° when inversion is suspected and comparing/aggregating both passes).

## RECOMMENDATIONS
- For the shared motion-core (all 5 apps): standardize on MediaPipe Pose Landmarker (Tasks API, full or heavy variant) as the primary cross-platform on-device pose engine — Apache 2.0, 33 landmarks with world coordinates, actively maintained, and the only option offering both 3D landmarks and reasonable Flutter-bridgeable native SDKs on both Android and iOS.
- For Ostinato specifically, pair MediaPipe Pose Landmarker with MediaPipe Hand Landmarker for bow/finger tracking, but benchmark the combined per-frame cost on a genuine mid-range Android device early — this is an unverified risk, not a known-good combo.
- Treat Ultralytics YOLO11/YOLOv8-pose as DISQUALIFIED unless the founder is willing to pay for an Ultralytics Enterprise license — do not let any implementation drift toward AGPL dependencies.
- For Gravita's handstand/inversion problem (gate D1), do NOT assume MediaPipe 'just works' upside-down — budget an explicit validation spike: record real handstand footage, run it through Pose Landmarker as-is, then compare against a 180°-pre-rotated-input pass (a cheap, code-only workaround requiring no retraining) and measure landmark stability/confidence before committing to the gate.
- If the 180°-rotation workaround proves insufficient, the VIRA-GCN paper's approach (train-time multi-angle rotation augmentation + inference-time multi-view aggregation) is the most concretely evidence-backed fallback pattern, though it implies either fine-tuning BlazePose (Google hasn't published a fine-tuning path for the closed Tasks API models) or building a custom lightweight rotation-invariant classifier on top of MediaPipe's raw landmark outputs — the latter is more feasible for a solo team.
- Consider Apple Vision's VNDetectHumanBodyPose3DRequest as an iOS-only quality upgrade layered on top of the MediaPipe baseline (better native 3D + per-joint confidence + zero extra bundle size), given the app family already plans native Swift/Kotlin bridges — but remember it requires a physical device for testing (no Simulator support), complicating the dev loop.
- Do not pursue Meta Sapiens/Sapiens2 or server-side/cloud pose models for the real-time coaching loop — they violate the on-device-only, raw-video-never-leaves-device constraint and are computationally impractical regardless of license.
- Treat QuickPose.ai as low-priority: no Flutter SDK, undisclosed underlying model, recurring commercial cost, and no evidence it handles inversions better than a self-integrated MediaPipe pipeline would.

## RISKS
- No official vendor documentation (Google or Apple) was found that explicitly characterizes pose-model behavior on inverted/upside-down bodies — the Gravita gate D1 question remains empirically unanswered pending your own device testing; do not treat any claim in this report as a substitute for that test.
- fps/latency figures cited across sources (MoveNet 30+FPS, MediaPipe 22-32FPS native Android, RTMPose-s 70+FPS on Snapdragon 865) come from vendor blogs, third-party benchmarks, or 2023-era hardware — none were independently reproduced in this research pass and should be re-benchmarked on your actual target mid-range devices before committing to a gate.
- MediaPipe Pose Landmarker and Hand Landmarker are still officially labeled 'MediaPipe Solutions Preview / early release' by Google with no formal backward-compatibility guarantee — a real risk for a multi-year product roadmap across 5 apps; monitor Google's release notes.
- ML Kit Pose Detection is explicitly BETA with no SLA/deprecation policy — treat as secondary, not primary.
- Meta Sapiens2's license terms were not independently verified beyond the name 'Sapiens2 License' — do not use without a founder/legal read of the actual license text, especially given Meta's history of restrictive research licenses on the original Sapiens.
- The arXiv 1902.04250 paper (most directly relevant academic source on handstand/cartwheel pose accuracy) could not be read as text in this pass (binary/image-only PDF extraction failure) — its specific quantitative findings on handstands should be verified by reading the paper directly (e.g. via a PDF viewer) rather than relying on the partial secondhand summary surfaced by web search.
- QuickPose.ai and other closed-SDK wrappers offer no visibility into underlying model provenance or license terms for redistribution inside your own commercial app — a legal/IP risk if adopted without a contract review.

## ITEMS (name | license | on_device | url)
### MediaPipe Pose Landmarker (Tasks API, BlazePose GHUM 3D)
- what: Google's current on-device pose model, successor to legacy MediaPipe Pose Solution. Ships as Tasks API (tasks-vision) for Android/iOS/Web/Python/C++. Detects 33 landmarks (2D image-normalized + 3D world coordinates in meters relative to hip midpoint), optional segmentation mask. Three model bundles: lite, full, heavy (accuracy/speed tradeoff; lite ~3MB). Detector stage predicts a person-centered c
- why: This is the primary on-device candidate for all 5 apps (Gravita, Lissom, JabLab, Ostinato, Choreia) — single camera, on-device, 33 landmarks including feet, Flutter-integrable via platform channel or existing plugins.
- license: Apache 2.0 (code and models) — commercial use allowed.
- maturity: Actively maintained by Google (google-ai-edge org), docs updated as recently as May 2026; considered production-stable, though officially still labeled 'MediaPipe Solutions Preview / early release' wi
- on_device: Yes, fully on-device; input 224x224x3 (detector) / 256x256x3 (landmarker), float16. Community-reported ~22-32 FPS native Android for full/heavy variants; lite faster. Official docs do not publish per-variant size/fps tables (verify empirically per ta
- integration: Flutter: no official Google Flutter plugin — typical path is a native Android (Kotlin, MediaPipe Tasks Vision AAR) + iOS (Swift, MediaPipe Tasks Vision pod) bridge exposed via platform channel/FFI, or community Flutter wrapper packages (audit mainten
- caveats: No explicit official documentation found describing behavior on inverted/upside-down bodies (handstands/headstands) — this is the open sub-question, see risks. Model card and per-variant fps/size numbers were not found in the fetched docs; treat any published fps figures as third-party benchmarks, n
- url: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
### Google ML Kit Pose Detection
- what: Google's higher-level, Firebase-adjacent SDK wrapping a pose model; 33 landmarks (aligned with BlazePose lineage), two variants: 'pose-detection' (base, faster) and 'pose-detection-accurate' (accurate). Includes InFrameLikelihood confidence per landmark. Native Android/iOS only, no web/Flutter-official.
- why: Alternative to raw MediaPipe Tasks API with a more polished native SDK surface (Google-managed on-device inference, no manual model bundling) — plausible fallback if Tasks API integration proves brittle.
- license: Apache 2.0 for code samples; ML Kit itself is Google's proprietary on-device SDK, but free and licensed for commercial app use under Google's ML Kit terms.
- maturity: Labeled explicitly as BETA with no SLA and no deprecation policy guarantee — 'changes may break backward compatibility.' Still active per docs as of mid-2026.
- on_device: Yes, fully on-device, real-time capable per Google's marketing (used in home-fitness demo apps).
- integration: Flutter: unofficial community packages exist (e.g. google_mlkit_pose_detection on pub.dev, actively maintained by the flutter-mlkit community org) — more mature Flutter path than raw MediaPipe Tasks in practice.
- caveats: Beta status is a real risk for a shipping product roadmap; no official guarantee against breaking changes. No inverted-pose documentation found.
- url: https://developers.google.com/ml-kit/vision/pose-detection
### MoveNet (Lightning / Thunder / MultiPose)
- what: TensorFlow's ultra-fast single-person pose model in two size tiers (Lightning=speed, Thunder=accuracy) plus a MultiPose Lightning variant for multiple people at roughly constant cost. 17 COCO keypoints only (no hands/feet detail, no native 3D).
- why: Fastest lightweight option if 17-point 2D is sufficient (e.g. coarse full-body tracking for Choreia's beat-sync or JabLab's gross limb tracking), but likely too coarse for Gravita's precise handstand alignment or Ostinato's fine hand/bow posture need
- license: Apache 2.0 (TensorFlow ecosystem) — commercial use allowed.
- maturity: Google's TF Hub model, well established since 2021, still distributed via TF Hub/TFLite; community activity continues (GitHub topic pages active) but no major 2025-2026 model refresh found in this res
- on_device: Yes; 30+ FPS on modern phones per TensorFlow's own blog claims; TFLite FP16 and INT8 quantized builds available for broad hardware compatibility.
- integration: Flutter: via tflite_flutter running the .tflite model directly, or community wrapper packages; well-trodden path with many tutorials (Heartbeat/Comet, Morioh Flutter posts found in this research).
- caveats: Only 17 keypoints, no z/3D world coordinates, no hand landmarks — likely insufficient alone for Ostinato (needs hand/bow tracking) or precise Gravita alignment scoring without pairing with another model.
- url: https://www.tensorflow.org/hub/tutorials/movenet
### RTMPose / RTMO (OpenMMLab MMPose)
- what: Real-time top-down (RTMPose) and one-stage multi-person (RTMO) pose estimators from the MMPose research ecosystem, exportable to ONNX/NCNN/TensorRT/OpenVINO/RKNN for edge deployment. RTMPose-s reported at 70+ FPS on a Snapdragon 865 CPU with 72.2% COCO AP; RTMPose-m even higher AP on desktop/server hardware.
- why: A credible, higher-accuracy-per-FLOP alternative to MediaPipe/MoveNet if the team is willing to own an ONNX Runtime inference pipeline; a working Flutter integration already exists in the open-source community (konyshevgmbh/pose_estimation_flutter, R
- license: Apache 2.0 (MMPose/OpenMMLab license) — commercial use allowed.
- maturity: Active OpenMMLab project (arXiv 2303.07399, 2023) with ongoing releases; a Qualcomm-optimized 'RTMPose-Body2d' build exists on Hugging Face for mobile NPUs, indicating vendor-level mobile deployment i
- on_device: Yes, via ONNX Runtime Mobile or NCNN; requires bundling your own runtime rather than a turnkey mobile SDK — heavier integration lift than MediaPipe/ML Kit.
- integration: Flutter: reference implementation exists at https://github.com/konyshevgmbh/pose_estimation_flutter using onnxruntime Flutter bindings, camera plugin abstraction across 6 platforms — good starting point to fork/adapt rather than build integration fro
- caveats: Requires more DIY ML-ops (model export/quantization, ONNX Runtime setup) than Google's turnkey SDKs; fps numbers cited (Snapdragon 865) are from the 2023 paper on an older chip generation and should be re-benchmarked on current mid-range targets.
- url: https://github.com/open-mmlab/mmpose/tree/main/projects/rtmpose
### YOLO11-pose / YOLOv8-pose (Ultralytics)
- what: Ultralytics' single-stage detection+pose models, multi-person, 17 COCO keypoints, five size tiers (n/s/m/l/x), exportable to CoreML/TFLite/ONNX/TensorRT for mobile deployment.
- why: Popular and fast, frequently recommended in tutorials, but carries a hard licensing blocker for a closed-source commercial indie app.
- license: DUAL LICENSE — AGPL-3.0 by default (requires your entire app/service to be open-sourced under AGPL if you use it, including network use) OR a paid Ultralytics Enterprise License for closed-source comm
- maturity: Very actively developed, large community, frequent releases (YOLO11, and a newer 'YOLO26' referenced in July 2026 third-party coverage) — technically mature.
- on_device: Yes technically (CoreML/TFLite export), but licensing makes this impractical for Gravita/Lissom/etc. without paying for an Enterprise license.
- integration: Flutter: would require CoreML (iOS) / TFLite (Android) export and custom platform-channel inference, no first-party Flutter SDK.
- caveats: AGPL-3.0 licensing problem is real and explicitly confirmed by Ultralytics's own licensing page/Roboflow's license summary — treat YOLO11/YOLOv8-pose as DISQUALIFIED for these apps unless Fable/founder decides to pay for an Enterprise license.
- url: https://github.com/ultralytics/ultralytics
### Apple Vision Framework — VNDetectHumanBodyPoseRequest (2D) & VNDetectHumanBodyPose3DRequest (3D)
- what: Apple-native, iOS-only pose detection. 2D request returns ~19 joints; 3D request (introduced WWDC23) returns a full 3D body-pose rig (Apple docs describe a skeleton with dozens of joints) plus per-point confidence, distinguishing it from ARKit's live body tracking which lacks per-point confidence.
- why: For iOS-only builds or as an iOS-specific fast path (native, zero extra model bundling, tightly integrated with AVFoundation camera pipeline), this is the lowest-friction and most battery-efficient option on Apple hardware.
- license: Proprietary Apple framework, free to use under standard Apple Developer Program terms — commercial use fully permitted, no attribution/royalty required.
- maturity: Shipping since iOS 14 (2D) and iOS 17 (3D); Apple actively maintains Vision framework each WWDC cycle.
- on_device: Yes, fully on-device, hardware-accelerated via Neural Engine. 3D request explicitly requires a physical device with Neural Engine — NOT supported on Simulator, which complicates CI/dev-loop testing.
- integration: Native Swift API only; Flutter integration requires a Swift platform channel / method channel bridge (no official Flutter plugin) — natural fit for the existing 'native Kotlin/Swift camera/ML bridges' architecture already assumed for this app family.
- caveats: iOS-only — Android needs a separate model (MediaPipe/ML Kit/MoveNet) regardless, so Apple Vision would be a platform-specific optimization layered on top of a cross-platform baseline, not a full replacement. No documentation found on inverted-body reliability specifically.
- url: https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-3d-with-vision
### ARKit Body Tracking (ARBodyTrackingConfiguration)
- what: Apple's AR-focused live body-motion capture (distinct from the Vision framework), returns a full 3D skeleton anchor in real time for motion-capture/AR overlay use cases.
- why: Alternative to Vision's 3D pose request specifically for live AR-anchored skeletal tracking (e.g. overlay coaching cues in 3D space) — Apple's docs explicitly contrast it with Vision: ARKit is for live motion capture, Vision works on still images/off
- license: Proprietary Apple framework, free under standard Developer Program terms.
- maturity: Mature, shipping since ARKit 3 (iOS 13).
- on_device: Yes, on-device, real-time, Neural Engine accelerated.
- integration: Native Swift/ARKit only; requires rear or front TrueDepth-capable hardware for full 3D depending on configuration.
- caveats: iOS-only; no confidence scores per joint (a documented gap vs. Vision's 3D request) — a meaningful limitation if the coaching logic needs to gate on per-landmark confidence (e.g. distrust an occluded wrist).
- url: https://developer.apple.com/documentation/arkit/capturing-body-motion-in-3d
### BlazePose GHUM 3D
- what: The underlying model architecture powering MediaPipe Pose Landmarker (not a separate product) — a two-stage detector+tracker producing 33 3D landmarks aligned to a GHUM (statistical human mesh) representation, with a rotation/scale-normalizing detector stage using a person-centered circle abstraction.
- why: Understanding this architecture explains why MediaPipe's rotation robustness is plausibly better than raw 2D keypoint models like MoveNet or YOLO-pose — worth citing directly when evaluating the Gravita inversion question.
- license: Apache 2.0 as distributed via MediaPipe.
- maturity: The original research is from 2020 (BlazePose paper, arXiv 2006.10204); it remains the architecture underneath the current 2025-2026 Pose Landmarker Tasks API.
- on_device: Yes — this IS the MediaPipe Pose Landmarker model; no separate integration path.
- integration: ?
- caveats: Training-data specifics for inversions/handstands are not disclosed in the public paper/blog; the rotation-normalizing detector stage is documented, but no explicit claim was found that training data specifically includes inverted/handstand poses at meaningful volume.
- url: https://research.google/blog/on-device-real-time-body-pose-tracking-with-mediapipe-blazepose/
### Meta Sapiens / Sapiens2
- what: Meta's foundation-model family for human-centric vision (2D pose, segmentation, depth/normals, and in Sapiens2: pointmaps, human matting), pretrained on hundreds of millions to 1 billion human images, native 1K-resolution inference. Sapiens2 ships in six sizes from 0.1B to 5B parameters.
- why: Represents the state-of-the-art accuracy ceiling and is worth knowing about, but is NOT viable for real-time on-device mobile inference in this app family — flagging explicitly so the team doesn't chase it.
- license: 'Sapiens2 License' — a Meta custom license, NOT a standard OSS commercial-friendly license (original Sapiens used a similarly restrictive Meta research license in past history); must be read carefully
- maturity: Sapiens (original) released 2024; Sapiens2 released ~April 2026 (arXiv 2604.21681), very recent, research-grade release.
- on_device: Marketed as scaling 'from mobile to high-end hardware' with 0.1B/0.4B/0.8B as the smaller tiers, but even 0.1B parameters is enormous relative to MediaPipe's ~3-30MB lite/full/heavy pose bundles — realistically a server-side or high-end-device-only o
- integration: ?
- caveats: Treat 'edge-capable' marketing claims skeptically for this app family's real-time voice-coaching-in-the-frame-loop requirement; no independent mobile fps benchmarks found. License terms need explicit legal review before any use.
- url: https://huggingface.co/facebook/sapiens2
### MediaPipe Hand Landmarker (MediaPipe Hands)
- what: 21 hand-knuckle 3D landmarks per hand, two-stage palm-detector + landmark model, part of the same MediaPipe Tasks Vision family as Pose Landmarker.
- why: Directly relevant to Ostinato (cello bow-hand/finger posture coaching) and potentially JabLab (fist/guard hand shape) — confirmed still actively maintained, not deprecated, as of the 2026 documentation check.
- license: Apache 2.0.
- maturity: Actively maintained; docs last updated May 2026 per search snapshot; still labeled part of 'MediaPipe Solutions Preview' (same early-release caveat as Pose Landmarker). A related 'Holistic Landmarker'
- on_device: Yes, same Tasks Vision runtime as Pose Landmarker; can run alongside pose landmarker but doubles inference cost — evaluate combined frame budget for Ostinato's real-time voice-coaching loop.
- integration: Same native bridge pattern as Pose Landmarker (Android AAR / iOS pod via Tasks Vision, exposed to Flutter over platform channel).
- caveats: No official fps numbers found for running hand+pose landmarkers simultaneously on mid-range phones — this is an unverified combined-cost risk for Ostinato specifically and should be benchmarked early.
- url: https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker
### QuickPose.ai (iOS/Android SDK wrapper)
- what: A commercial third-party SDK (built atop underlying pose models) offering prebuilt exercise/measurement primitives (rep counters, form-check plugins) for iOS, Android, and React Native.
- why: Represents the 'buy vs. build' option — could accelerate JabLab/Gravita rep-counting logic, but adds a paid dependency and a black-box model whose inversion-robustness is unverified.
- license: Proprietary commercial SaaS SDK with tiered pricing (Personal/Launch/Scale/Agency) — not open-source; requires ongoing commercial licensing rather than a one-time embed.
- maturity: Actively shipping in 2026 (new PushUp Rep Counter sample released January 2026 per their news page); claims 1M+ workouts powered.
- on_device: Marketed as on-device but the underlying model and its handling of inverted poses/handstands is not disclosed publicly.
- integration: Native iOS/Android SDKs + React Native support explicitly mentioned; no official Flutter SDK found — would need a native bridge same as the other options, undermining the 'quick' value proposition for a Flutter-first codebase.
- caveats: No technical documentation found on their underlying model, license terms for on-device redistribution, or inversion-case behavior — treat as an unverified black box; probably not worth the recurring cost given the team is already building native Kotlin/Swift bridges anyway.
- url: https://quickpose.ai/products/ios-sdk/


# ==== flutter-integration ====

## SUMMARY
The 2025-2026 Flutter real-time camera+ML landscape confirms the Yula Motion family's planned architecture is the right call: there is still no official Google-maintained Flutter plugin for MediaPipe's vision tasks (pose/hand landmarkers) — only an official mediapipe_genai package scoped to on-device LLM tasks — so low-latency 30fps pose coaching realistically requires native Kotlin (CameraX + MediaPipe Tasks Vision or ML Kit) and native Swift (AVFoundation + the same), with results bridged to Flutter via Pigeon-generated type-safe channels rather than routing raw camera frames through Dart. The Dart-side shortcuts — google_mlkit_pose_detection (community-maintained, not Google-sponsored) and tflite_flutter (TensorFlow-org fork, self-described work-in-progress with ~100 open issues but real GPU/NNAPI/CoreML/XNNPACK delegate support) — are usable for prototyping or non-realtime screens but carry maintenance/perf risk for an always-on coaching loop. Flutter's official camera plugin, now backed by camera_android_camerax, remains the right base capture layer even in a native-bridge design, and Impeller (default renderer since 2026) has documented rough edges specifically around heavy PlatformView/texture usage that must be benchmarked early since it directly affects the camera-preview UI every app needs. For voice coaching, flutter_tts (OS-native TTS, no cloud cost, adequate but not premium quality) paired with the audio_session package (real ducking/audio-focus support on both platforms, coarser control on iOS) is the pragmatic on-device, cost-free default; a pre-recorded neural-voice library could be layered in later for premium tiers without breaking the on-device promise. A handful of open-source Flutter pose/fitness repos (fitnessPipe's swappable-backend interface, ai-workout-assistant's angle-threshold state machine, pose-detection-flutter's overlay-rendering boilerplate) offer useful design patterns to study, though none were verified first-hand and should be read directly before reuse. No dedicated Flutter package addresses camera-session battery/thermal management — that will require custom native thermal-state monitoring and graceful-degradation logic per app.

## RECOMMENDATIONS
- Commit to the native-bridge architecture as researched: run camera capture + pose/landmark inference entirely in native Kotlin (CameraX ImageAnalysis) and native Swift (AVCaptureVideoDataOutput), using MediaPipe Tasks Vision (BlazePose) or platform-native ML Kit SDKs directly (not through google_mlkit_pose_detection's Dart plugin) for the lowest per-frame latency; there is no official Flutter/MediaPipe vision plugin in 2026, so this is confirmed as the only low-latency, low-risk path.
- Use Pigeon to define the native↔Dart contract: a HostApi to start/stop a camera+inference session per app, and a FlutterApi (or Pigeon event-channel pattern) for the native side to push landmark/state-machine results to Dart — but throttle what crosses the channel (e.g., push state-machine transitions and a decimated ~10-15fps overlay skeleton, not every 30fps raw landmark frame) to avoid channel overhead and Impeller-related PlatformView/texture jank.
- Keep TFLite/tflite_flutter and google_mlkit_pose_detection (Dart-side) as fallback/prototyping tools only — good for fast iteration and non-realtime app screens (e.g., a one-off 'assess my flexibility' capture in Lissom that doesn't need continuous 30fps), but move to native inference for any always-on real-time coaching loop.
- Implement movement state machines as native Kotlin/Swift code close to the landmark source (angle thresholds, rep-stage transitions like reevald/ai-workout-assistant's Down/Up pattern), keeping Dart focused on UI, TTS triggering, and program/state persistence — this matches the family's 'no real-time LLM in the frame loop' rule and minimizes cross-boundary chatter.
- Use audio_session + flutter_tts as the default voice-coaching stack (fully on-device, zero marginal cost, adequate latency); consider pre-recording a neural-TTS coach voice library (build-time, not real-time) for a premium tier later, with flutter_tts remaining the fallback for dynamic/numeric cues that can't be pre-scripted.
- Build a replay/fixture test harness at the native-result boundary: record the JSON/struct landmark-stream payloads that cross the Pigeon channel during real sessions, then replay them as fixtures to drive Dart-side state-machine and coaching-cue unit/widget tests without needing a live camera — this keeps CI fast and deterministic per the family's stated replay/fixture testing requirement.
- Before shipping, explicitly perf-test each app's live camera+overlay screen under Impeller on a mid-tier Android device (API 29+) and an older iPhone, since 2026 sources flag PlatformView/heavy-texture regressions as a known Impeller rough edge relevant to a continuous camera-preview UI.

## RISKS
- MediaPipe has no official Flutter vision plugin as of mid-2026 — betting on native Kotlin/Swift MediaPipe Tasks Vision integration is correct architecturally but means solo-founder-maintained native code on two platforms with no cross-platform abstraction layer to lean on; budget real native-dev time, not just Dart time.
- google_mlkit_pose_detection and tflite_flutter (the two most tempting 'fast path' Dart-side options) are both community/semi-official maintained with real bus-factor risk (mlkit plugin explicitly disclaims Google sponsorship; tflite_flutter repo self-describes as still 'work in progress' with ~100 open issues) — do not treat either as a long-term dependency for the always-on real-time inference loop; fine for prototyping or non-realtime screens only.
- Impeller (default renderer since 2026) has documented weak points specifically around heavy PlatformView/texture usage, which is precisely the camera-preview-plus-overlay UI pattern all 5 apps need — this needs hands-on device benchmarking early, not late, since a renderer-level regression is expensive to work around after the UI is built.
- GPU/NNAPI/CoreML delegate behavior for TFLite (and MediaPipe's own GPU delegate) is device- and SoC-fragmented; 'supports delegate X' claims from package docs do not guarantee consistent speed/accuracy across the low-to-mid-range Android devices a solo-founder fitness app audience likely uses — always benchmark on a real device spread, not just flagship test phones.
- iOS audio ducking control is coarser than Android's (per Apple Developer Forums discussion) — cannot finely tune duck depth on iOS, which may make the 'trainer speaking over your music' experience feel less polished on iOS than Android without extra native audio-session tuning.
- Foreground camera+ML sessions are a real battery/thermal risk on longer sessions (a boxing or dance session could run 20-40+ minutes) — no dedicated Flutter package solves this; it requires native-side thermal-state monitoring (Android PowerManager thermal APIs / iOS ProcessInfo.thermalState) and a fallback plan (e.g., drop inference resolution/frame rate) that must be custom-built per app.
- Several open-source example repos (fitnessPipe, ai-workout-assistant, pose-detection-flutter) were surfaced via search snippets only and not verified by direct repo inspection in this pass — confirm license terms, current maintenance activity, and actual code quality before treating any of them as more than design/pattern inspiration.

## ITEMS (name | license | on_device | url)
### camera (official Flutter plugin) + camera_android_camerax
- what: flutter.dev's official camera plugin; on Android the endorsed federated implementation is now camera_android_camerax, backed by Google's CameraX library. Supports preview, capture, video, and startImageStream() for streaming CameraImage buffers to Dart.
- why: This is the base capture layer every app in the family needs regardless of whether inference runs in Dart or native code. 2025-2026 releases added FPS/bitrate control and NV21 streaming format support on Android, which matters for feeding frames into
- license: BSD-3-Clause
- maturity: Official flutter/packages monorepo, actively released through 2026; camera_android_camerax is the default Android impl for camera ^0.11.0.
- on_device: Yes — this is the local camera capture layer, no cloud involved.
- integration: Use as the base Flutter-side camera; for the family's chosen pattern (native Kotlin/Swift camera+inference with results bridged to Flutter) you'd bypass camera's Dart-side ImageStream and instead run CameraX (Android) / AVFoundation (iOS) natively an
- caveats: startImageStream() CameraImage buffers on Android are YUV420 planar and require manual conversion (or NV21 format now) before feeding a Dart-side TFLite/ML Kit call; this conversion is a well-known perf bottleneck if done on the UI isolate.
- url: https://pub.dev/packages/camera
### tflite_flutter (tensorflow/flutter-tflite)
- what: Official-ish TensorFlow Lite Dart bindings using dart:ffi directly against the TFLite C API. Supports GPU delegate + NNAPI on Android, Metal + CoreML delegates on iOS, XNNPACK on desktop.
- why: Primary path if you want to run custom TFLite models (e.g., a cello-technique classifier for Ostinato, or a custom boxing-punch classifier for JabLab) directly from Dart rather than through platform channels.
- license: Apache-2.0
- maturity: Repo is the TensorFlow-org maintained fork of the old am15h/tflite_flutter_plugin; pub.dev listing shows updates as recent as October 2025; still has ~100 open GitHub issues and describes itself as wo
- on_device: Yes, fully on-device; FFI binding is low-latency and supports running inference in a background isolate to avoid UI jank.
- integration: dart:ffi based Flutter plugin; import directly, run interpreter in isolate via compute()/Isolate.run with TransferableTypedData for zero-copy buffer transfer.
- caveats: Because it's Dart-side, you still pay a platform-channel-free but Dart-isolate marshalling cost per frame; for true 30fps native camera+inference (the family's stated pattern) the native-bridge approach below is generally preferred over pulling frames into Dart for TFLite. Delegate availability (GPU
- url: https://github.com/tensorflow/flutter-tflite
### google_mlkit_pose_detection (google_ml_kit family)
- what: Community-maintained Flutter plugin (platform channels) wrapping Google's native ML Kit Pose Detection API (33 body landmarks, base/accurate models) for Android and iOS.
- why: Turnkey pose landmark extraction for Gravita (handstand), Lissom (mobility), JabLab (boxing), Choreia (dance) without training/shipping a custom model — Google ML Kit's pose model does the person + 33-keypoint detection, your app supplies the rule-en
- license: Apache-2.0 (check exact LICENSE file; ML Kit native SDK itself is Google's proprietary-but-free-to-use SDK, so check Google's ML Kit terms for commercial redistribution — generally allowed, on-device,
- maturity: Explicitly NOT sponsored/maintained by Google — 'authors are developers … that wanted to expose Google's native APIs to Flutter.' Actively updated on pub.dev with regular version bumps; widely used (l
- on_device: Yes, fully on-device pose inference (part of ML Kit's on-device APIs, distinct from ML Kit cloud APIs).
- integration: Uses Flutter platform channels (MethodChannel-based), consuming CameraImage from the camera plugin's image stream. 64-bit only (no armv7/i386 support).
- caveats: Community-maintained (not Google) — bus-factor risk; platform-channel marshalling per-frame has overhead vs. a pure-native pipeline. For the family's committed pattern of native Kotlin/Swift camera+inference, you'd likely reimplement pose detection natively (ML Kit has native Android/iOS SDKs) and b
- url: https://pub.dev/packages/google_mlkit_pose_detection
### MediaPipe official Flutter plugin — status: NO first-class official plugin (Vision tasks)
- what: Google's MediaPipe has official native SDKs for Android, iOS, Python, Web (Pose Landmarker etc.) but as of 2026 there is still no official Google-maintained Flutter binding for MediaPipe Vision tasks (pose/hand/face landmarkers). There IS an official 'mediapipe_genai' Flutter package, but that's for on-device GenAI/LLM tasks, not pose/vision.
- why: Confirms the family's binding architecture decision (native Kotlin/Swift camera+inference bridged to Flutter) is the pragmatic choice — MediaPipe's much-lauded low-latency BlazePose landmarker is only reliably accessible from Flutter by writing nativ
- license: Apache-2.0 (MediaPipe)
- maturity: mediapipe_genai is Google-official but GenAI-scoped only (on-device LLM/Gemma tasks); no equivalent official package exists for MediaPipe Tasks Vision (pose/hand landmarker) in Flutter as of mid-2026.
- on_device: Yes for native MediaPipe Tasks Vision SDKs (Android/iOS), fully on-device, GPU-delegate accelerated.
- integration: Native-only: add MediaPipe Tasks Vision to the native Android/iOS layer of each app's native camera module, run BlazePose/hand landmarker there, serialize landmark results (e.g., a compact float array or JSON) and stream them to Dart via a Pigeon-gen
- caveats: Third-party community wrappers exist (e.g., ThinkSys's open-source mediapipe-flutter plugin, and a Medium writeup on Flutter Web + MediaPipe) but they are unofficial, narrower in platform coverage (the ThinkSys one launched iOS-first in 2024), and carry real maintenance risk — treat as reference/ins
- url: https://pub.dev/documentation/mediapipe_genai/latest/
### Pigeon (official flutter/packages codegen)
- what: Google/Flutter-team-maintained code generator that produces type-safe platform channel (Kotlin/Swift/Dart) bindings from a single Dart interface definition, including support for streaming/event APIs and Flutter platform views (splitting a 'factory API' for creating a native camera instance from an 'instance API' for per-instance control, exactly as the official camera plugin itself does internall
- why: This is the concrete mechanism for the family's binding architecture: native Kotlin/Swift camera+ML session sends 30fps landmark/pose-state results to Flutter (audio-coaching + UI layer) without hand-writing brittle raw MethodChannel code.
- license: BSD-3-Clause
- maturity: Official, actively maintained inside flutter/packages monorepo; camera_android_camerax itself is built on Pigeon internally, proving the pattern at production scale.
- on_device: N/A — it's a codegen/bridging tool, not an inference engine.
- integration: Define an event-channel-style API in Pigeon (FlutterApi for native→Dart callbacks streaming landmark frames/state-machine events), implement HostApi in Kotlin/Swift to start/stop the native camera+MediaPipe/ML-Kit session; Dart side just implements t
- caveats: For true 30fps continuous streaming, prefer batching/throttling landmark payloads (e.g., send only on state-machine transitions or at a capped UI-relevant rate like 10-15fps for UI overlay, keeping the full 30fps loop entirely native) rather than pushing every frame across the channel — platform cha
- url: https://pub.dev/packages/pigeon
### flutter-embedding-native-views pattern (native PlatformView + SurfaceTexture/Texture)
- what: Flutter's documented approach for embedding a fully-native camera preview (AndroidView/UiKitView or the lower-level Texture widget backed by a native SurfaceTexture/CVPixelBuffer) directly in the widget tree, with the native side owning capture+inference and only exposing a texture handle + Pigeon result stream to Dart.
- why: This is literally the architecture the family has already committed to (native camera/ML bridge). Distinguishes two integration options: (1) PlatformView — embeds a real native camera UIView/View in the tree (simplest, but historically had performanc
- license: N/A (pattern/technique, not a package)
- maturity: Documented Flutter-team pattern used by the official camera plugin itself; well-established since Flutter 1.x, still the recommended approach in 2026.
- on_device: Yes — native camera + native inference, only landmark/audio-cue results cross into Dart.
- integration: Native Kotlin (CameraX ImageAnalysis use-case → MediaPipe/ML Kit/TFLite inference → Pigeon event stream) / native Swift (AVCaptureVideoDataOutput → MediaPipe Tasks Vision/CoreML → Pigeon event stream); Dart owns UI chrome, voice coaching triggers, an
- caveats: Impeller (now default renderer on iOS and Android API 29+ as of 2026) has documented rough edges with heavy PlatformView/texture usage — 'heavy PlatformView or texture usage can still perform worse on Impeller in some cases'; benchmark camera-preview-heavy screens specifically on real target devices
- url: https://blog.codemagic.io/working-with-native-elements/
### audio_session
- what: Flutter package (by the ryanheise / just_audio ecosystem author) wrapping AVAudioSession (iOS) and AudioManager/AudioFocus (Android) to configure category/mode, request audio focus, and handle ducking/interruption event streams.
- why: Directly covers the family's 'real-time voice coaching while music plays' requirement (relevant especially to Ostinato's microphone+coaching-voice overlap, JabLab/Choreia workout-music ducking, and general TTS-over-music UX) — supports AUDIOFOCUS_GAI
- license: MIT
- maturity: Mature, widely used (companion to just_audio/flutter_tts ecosystem), actively maintained with recent changelog entries.
- on_device: N/A — system audio session/focus management, inherently local.
- integration: Configure an AVAudioSessionCategory (playAndRecord for Ostinato's mic+coaching-voice case; playback with duckOthers for the rest) once at app start; listen to becomingNoisyEventStream / interruption events to pause/resume; call flutter_tts speak() in
- caveats: Ducking level/granularity on iOS is somewhat fixed by the OS (limited developer control over exact duck amount per a 2026 Apple Developer Forums thread) — you get 'ducked' or 'not ducked', not fine dB control. Android gives more control via AudioFocusRequest.Builder but behavior still varies slightl
- url: https://pub.dev/packages/audio_session
### flutter_tts
- what: Flutter plugin wrapping each platform's native TTS engine (Android TextToSpeech API, iOS AVSpeechSynthesizer) — no bundled voices, relies entirely on OS-provided voices, so quality/latency is essentially whatever the phone's stock TTS engine provides.
- why: Cheapest, fully-offline, zero-marginal-cost path to real-time voice coaching across all 5 apps ('like having a trainer next to you') with no per-utterance cloud cost or latency, critical for a solo-founder budget and for the on-device-only architectu
- license: BSD/MIT-style (check package LICENSE — permissive, commercial use allowed)
- maturity: Long-established, widely used Flutter plugin (well past 1.0), still actively maintained; used across thousands of published apps.
- on_device: Yes, 100% on-device (delegates to OS TTS engine, which itself runs locally on modern Android/iOS).
- integration: Direct Dart plugin call from the coaching-cue trigger (state-machine event → speak('Straighten your left leg')); wrap calls in audio_session focus request for ducking; pre-warm/cache short phrase queue to avoid TTS-engine cold-start latency on the fi
- caveats: Quality and available voices are entirely OS-dependent and NOT competitive with 2025-2026 neural cloud TTS (ElevenLabs, CosyVoice2, etc.) — stock Android TTS voices in particular can sound robotic on some OEM skins/older devices. Given the on-device-only, cost-sensitive, real-time-latency constraint
- url: https://pub.dev/packages/flutter_tts
### jinzishuai/fitnessPipe
- what: Open-source Flutter fitness app built around MediaPipe pose detection, explicitly designed with an abstract PoseDetector interface so the underlying ML backend (MediaPipe vs ML Kit vs custom TFLite) can be swapped.
- why: Directly relevant reference architecture: abstracting the pose-detector interface is exactly what the Yula Motion family needs since different apps (Gravita/Lissom/JabLab/Choreia) may want different landmark sets or even different backends over time 
- license: MIT (per search result — verify in repo)
- maturity: Smaller open-source project; check recent commit activity before relying on it, but architecture pattern (interface abstraction) is the key thing to steal regardless of current maintenance state.
- on_device: Yes, MediaPipe-based on-device pose detection.
- integration: Steal the PoseDetector interface abstraction and its Flutter UI-layer/detection-layer separation; do not necessarily reuse its camera-frame plumbing given the family's native-bridge architecture decision.
- caveats: Not verified firsthand in this research pass (only found via search snippet) — read the actual source before committing to patterns; unclear how recently updated for current MediaPipe Tasks API vs legacy MediaPipe.
- url: https://github.com/jinzishuai/fitnessPipe
### reevald/ai-workout-assistant
- what: Open-source AI workout assistant with pose tracking + rep counter, using configurable per-exercise 'stages' (e.g., Down/Up for push-ups) driven by joint-angle thresholds — i.e., a hand-rolled deterministic state machine on top of pose landmarks.
- why: This is the closest open-source analog to the family's required 'deterministic rule engines + movement state machines' approach (explicitly NOT an LLM-in-the-loop design) — worth reading its stage-transition/angle-threshold logic as a starting refere
- license: Check repo LICENSE file directly (not confirmed in search snippet).
- maturity: Community project; verify current activity/star count and Flutter-vs-other-stack composition directly in-repo before relying on it.
- on_device: Appears to be on-device pose tracking + counting, consistent with typical open pose-counter demos of this kind.
- integration: Steal the angle-threshold state-machine design (Down/Up staging per exercise) as a template for the family's own movement state machines; re-implement in the native (Kotlin/Swift) layer given the family's native-camera-inference architecture rather t
- caveats: Description found via search snippet only, not verified by direct repo read in this pass — confirm tech stack, license, and code quality before using as a dependency or copy-paste base; treat purely as a design reference.
- url: https://github.com/reevald/ai-workout-assistant
### nainarathore/pose-detection-flutter
- what: Real-time Flutter + Google ML Kit pose-detection Android app, 33 landmarks, posture classification (Standing/Sitting/Hands Raised), fully offline.
- why: A clean, minimal reference for wiring google_mlkit_pose_detection to a live camera stream with real-time landmark overlay drawing (CustomPainter over the camera preview) — useful boilerplate to study for the overlay-rendering half of the problem (dis
- license: Check repo LICENSE directly (not confirmed in snippet).
- maturity: Smaller/demo-scale project — good for boilerplate/pattern study, not production-grade.
- on_device: Yes — ML Kit on-device pose detection.
- integration: Steal the CustomPainter landmark-overlay-on-camera-preview rendering code and the ML Kit InputImage-from-CameraImage conversion boilerplate; note this project is Android-only per its description, so iOS conversion code will need to be added/verified 
- caveats: Android-only per description — does not demonstrate iOS ML Kit integration; also uses the Dart-side ML Kit plugin (platform channels per frame) rather than the family's chosen native-bridge pattern, so treat as a UI/overlay reference, not an inference-pipeline template.
- url: https://github.com/nainarathore/pose-detection-flutter


# ==== commercial-sdks ====

## SUMMARY
The 2025-2026 fitness motion-tracking SDK market has a handful of real, actively maintained vendors (QuickPose, Sency/SencyMotion, Kemtai, KinesteX, Exer AI, Asensei) plus one prominent consumer app with no developer SDK (Onyx) and one name ('MyLIVIA') that did not resolve to any identifiable product in this scan. Of the developer-facing SDKs, KinesteX stands out as the most Flutter-friendly (a real published Flutter package plus Swift/Kotlin/React Native/web SDKs) and the most self-serve for custom workout sequencing, making it the strongest V0-prototyping candidate for Yula Motion's Flutter-based apps. QuickPose is MediaPipe-based, confirmed on-device, has a genuine free tier and public GitHub SDK, but is iOS/Android-native only (no Flutter) and routes truly custom exercises through vendor-assisted model training rather than self-serve state-machine authoring. Sency's per-MAU billing (free to 100 users, then pay-as-you-go) is the most transparent pricing found and is explicitly edge/on-device, but its self-serve custom-exercise-authoring capability is unconfirmed. Kemtai, Exer AI, and Asensei read as enterprise/healthcare-oriented or B2B-sales-gated products with opaque pricing and unclear on-device guarantees — costly to evaluate relative to their payoff for a solo founder. Critically, no vendor in this space offers anything close to boxing punch-classification (JabLab) or dance/beat-sync technique judgment (Choreia) — that gap is confirmed by research literature and Roboflow community datasets rather than any commercial product, meaning those two apps carry the most build-your-own risk. Given Yula Motion's hard architectural requirements (raw video never leaves device, deterministic rule engines not LLMs, shared core across 5 apps), the most defensible long-term path is building on Google's free, Apache-2.0-licensed, genuinely on-device MediaPipe Pose Landmarker for skeleton extraction, with all 5 apps' state machines as proprietary shared-core code — while using KinesteX and/or QuickPose as fast, disposable V0 prototyping aids to validate UX (rep-counting feel, form-feedback timing, coaching cadence) before committing engineering time to the custom production pipeline.

## RECOMMENDATIONS
- Buy for V0 prototyping only: KinesteX is the strongest evaluate-first candidate because it has a genuine Flutter package (kinestex_sdk_flutter on pub.dev) plus Swift/Kotlin/React Native/web SDKs, a documented custom-workout-sequencing API, and claims raw pose-data access — spin up a 1-2 day spike on Gravita or Lissom to validate rep-counting/ROM UX and check whether inference is truly on-device before trusting it further.
- QuickPose is the next-best V0 option specifically for iOS-first spikes (free tier up to 100 devices/month, public GitHub SDK, MediaPipe-based so definitely on-device) — use it to fast-prototype Lissom's mobility/ROM assessment screens even though it lacks a Flutter SDK; treat it as a native throwaway harness, not a Flutter dependency.
- For production across all 5 apps, build on raw pose-landmark extraction (Google MediaPipe Pose Landmarker — Apache 2.0, on-device, commercial-use-friendly, free) plus your own deterministic rule engines/state machines per the binding architecture. This avoids per-MAU vendor billing across 5 apps' combined user base, avoids lock-in, and is the only path that guarantees raw video never leaves the device (several vendors' on-device claims — Kemtai, Onyx, Asensei's 'Cloud Coach' — are unconfirmed or explicitly hint at cloud components).
- Sency is worth a pricing/ToS review (their MAU-based billing — free to ~100 users, then pay-as-you-go — is the most transparent and could be cheap at indie scale) but only if their SDK is confirmed to expose raw landmarks for custom exercise logic; if it only returns pre-built assessment outputs, it fails the 'define our own exercises' requirement and isn't worth the integration cost.
- JabLab (boxing) and Choreia (dance/beat-sync) have no viable commercial SDK match — no vendor in this scan offers punch-classification or dance-technique/beat-sync judgment. Budget engineering time to build custom classifiers on top of a generic pose SDK (MediaPipe/QuickPose skeleton output) rather than searching further for a boxing/dance-specific vendor.
- Do not pursue Kemtai, Exer AI, or Asensei for V0 speed — all three read as enterprise/healthcare or B2B-sales-gated products (opaque pricing, no self-serve SDK docs, possible cloud dependency) that would cost founder time in sales calls without a guaranteed on-device or Flutter-compatible outcome.
- Treat Onyx purely as a competitor-UX reference (their natural-language coaching and silhouette-overlay feedback) — it is not a licensable component.
- Confirm 'MyLIVIA' with the founder — it did not resolve to a real, current vendor in this scan; possible name confusion with a different product.

## RISKS
- Lock-in risk (moderate-high) across all commercial SDKs surveyed: none publish an open self-serve API for defining truly custom exercise state machines on raw landmark streams — QuickPose and Asensei explicitly funnel custom exercises through a vendor-services engagement, and Kemtai/Exer are catalog-consumption models. Building production on any of them risks being stuck re-requesting vendor model training for every new exercise across 5 apps.
- On-device claims are unverified for several vendors (Kemtai, Onyx, Asensei's Cloud Coach) — given the hard 'raw video never leaves device' architectural constraint, using any of these in production without direct confirmation from the vendor's engineering docs (not marketing copy) would be a compliance/privacy risk.
- Per-MAU or per-device billing (Sency, KinesteX, QuickPose) compounds awkwardly across a 5-app portfolio sharing a core — a user active in two Yula Motion apps could be double-billed unless the vendor's contract explicitly handles a shared-core/multi-app scenario; this needs to be negotiated, not assumed.
- No commercial vendor covers boxing punch-classification or dance/beat-sync judgment at all — JabLab and Choreia carry outsized custom-ML build risk relative to Gravita/Lissom/Ostinato which can lean on generic pose-fitness SDKs for at least prototyping.
- Vendor pricing pages for KinesteX and QuickPose returned only fragmentary/aggregator-sourced numbers (e.g. the '$0.15/mo' KinesteX figure came from a third-party listing site, not kinestex.com directly) — do not use these figures for budgeting without pulling the vendor's own current pricing page.
- Solo-founder bandwidth risk: several vendors (Kemtai, Exer, Asensei) require a sales conversation to get pricing/API access at all, which costs calendar time disproportionate to their evaluation value for a 5-app indie portfolio — deprioritize unless a specific app's needs (e.g. clinical-grade ROM for a future medical-adjacent feature) demand it.

## ITEMS (name | license | on_device | url)
### QuickPose.ai
- what: Pose estimation/detection SDK wrapping MediaPipe with a library of pre-built fitness/yoga/ROM/joint-angle models (rep counting, form feedback, yoga alignment scoring, ROM assessment for physio/rehab). 2M+ exercises/measurements processed to date.
- why: Directly targets the same rep-counting/form-feedback/ROM problem all 5 Yula Motion apps need, on-device via MediaPipe, with a free tier cheap enough for solo-founder V0 exploration.
- license: Commercial SaaS SDK; GitHub repos are for the client wrapper, not an OSS license for the underlying models — check ToS on video/data handling.
- maturity: Active vendor with public GitHub orgs (quickpose/quickpose-ios-sdk, FitCount demo repo), documented SDK, live pricing page — reads as a real, maintained product as of 2026.
- on_device: On-device (built on MediaPipe pose landmarker); no raw video leaves device for the built-in models.
- integration: Best fit as native iOS/Android modules behind a Flutter platform channel, or purely as a V0 prototyping aid outside Flutter (e.g. quick iOS test harness) while production stays on custom MediaPipe/Kotlin/Swift bridges.
- caveats: No Flutter SDK confirmed; custom exercise definition appears vendor-assisted rather than self-serve, which conflicts with the 'define OUR OWN state machines' requirement unless you go raw MediaPipe instead.
- url: https://quickpose.ai/
### Sency (SencyMotion SDK)
- what: Edge/on-device AI motion-tracking SDK for fitness and health apps — body assessments, workout tracking, form analysis; markets itself as a plug-and-play 'minimal coding' integration (e.g. their Burpee example).
- why: Explicitly edge/on-device processing with transparent per-MAU pricing (free to 100 users) is the closest pricing-model match to a solo founder's budget constraints among all vendors surveyed.
- license: Commercial SDK, proprietary; smkit-sdk GitHub repo likely just client bindings/docs.
- maturity: Real company covered by fitness-tech press (Athletech News), has a public SDK repo and live pricing page — moderately mature vendor.
- on_device: Explicitly edge/on-device: 'all data processing is localized on the device' — no video/photo stored in the cloud, positioned squarely as privacy-first, which matches Yula Motion's raw-video-never-leaves-device requirement.
- integration: Would sit as a native SDK behind a bridge for prototyping; genuine per-MAU billing model is worth benchmarking against build-cost even if not used in production.
- caveats: Could not confirm whether SDK exposes raw pose landmarks for custom exercise logic vs. only pre-built assessment outputs — verify via github.com/sency-ai/smkit-sdk before committing.
- url: https://www.sency.ai/pricing
### Kemtai
- what: Motion Intelligence Platform for physiotherapy/fitness — 111-point body tracking, real-time feedback, large pre-built exercise library (2,000+ exercises/variations), FDA-listed/CE-marked/ISO-certified medical-device-grade compliance (HIPAA/GDPR).
- why: Represents the medical-grade/enterprise end of the market — useful as a pricing/compliance benchmark and a cautionary example of a vendor poorly suited to indie mobile architecture.
- license: Proprietary enterprise SaaS/API; sales-negotiated.
- maturity: Well-established, medical-grade certifications, enterprise healthcare partnerships (health systems) — mature but healthcare/enterprise-oriented, likely priced and scoped for that market rather than in
- on_device: Not clearly on-device; browser-based real-time feedback 'without accessories, sensors or expensive devices' suggests the compute could be device-side but this is unconfirmed vs. cloud API calls — needs direct verification.
- integration: Poor fit for Yula Motion's mobile-native, solo-founder, on-device architecture; closer to a white-label web widget for clinics than an SDK you'd embed inside a Flutter camera pipeline.
- caveats: On-device vs. cloud processing unconfirmed — likely cloud/browser-based given no mention of edge AI (unlike Sency/Exer which explicitly market edge processing). Enterprise price point likely mismatched to solo-founder budget.
- url: https://kemtai.com/api-integration/
### KinesteX
- what: Motion analysis/tracking SDK with ready-made workouts, plans, AI assessments, rep count, calorie burn, ROM, fatigue/fall detection, injury prevention, posture/alignment monitoring; also lets you assemble custom workout sequences (exercise order, reps, durations, rest) via API or admin portal.
- why: The only vendor in this scan with a first-class published Flutter package, directly matching Yula Motion's Flutter+native-bridge stack, plus the most self-serve custom-workout-authoring story found.
- license: Commercial SDK, proprietary; GitHub repos are client-side bindings.
- maturity: Active, multi-repo GitHub org (KinesteX/KinesteX-SDK-*), published Flutter package on pub.dev, live docs site (kinestex.com/docs) — reasonably mature and clearly investing in developer experience acro
- on_device: Uses camera-based computer vision at 30-50fps claimed 95% form-feedback accuracy; search results did not explicitly confirm on-device-only inference vs. some cloud component — verify before committing given the hard on-device requirement.
- integration: Best V0-prototyping candidate for Yula Motion given native Flutter package — could plug directly into Gravita/Lissom/JabLab-style prototypes to validate rep-counting/coaching UX in days rather than weeks, while production state machines stay custom.
- caveats: On-device vs. cloud inference not explicitly confirmed in search results — must verify directly (critical given the raw-video-never-leaves-device requirement). The '$0.15/mo' pricing snippet is from a third-party aggregator, not the vendor page, and should not be trusted without checking kinestex.co
- url: https://www.kinestex.com/docs
### Exer AI / Exer Studio
- what: Clinical/consumer motion-AI platform (Exer Health for MSK/ROM clinical assessment; Exer Studio for real-time metrics/leaderboards in virtual fitness classes) using edge-based AI and computer vision, no wearables/sensors required.
- why: Explicitly markets edge-AI on-device processing matching Yula Motion's privacy requirement, and is a named vendor in the task's must-cover list, but lacks any public self-serve developer SDK.
- license: Unknown/proprietary; would require direct negotiation.
- maturity: Real, VentureBeat-covered company with live consumer apps (Exer Health, Exer Studio) — product is mature but developer self-serve access is unclear.
- on_device: Explicitly edge AI — 'edge-based AI and computer vision... without the need for wearables or sensors,' matching the raw-video-stays-on-device requirement.
- integration: Not currently a practical build-vs-buy option for a solo founder without direct sales contact — flag as 'contact for partnership' rather than an SDK to prototype with this week.
- caveats: No self-serve SDK/API/pricing found — this entry is thinner than the others; treat as a lead to email, not a comparable SDK line item, until verified.
- url: https://www.exer.ai/
### Asensei (ASENSEI.AI SDK / ASENSEI Spark / (APP)ERTURE)
- what: 3D computer-vision movement-recognition and coaching-intelligence SDK (introduced 2021, still active) covering fitness form-tracking, equipment recognition, spatial computing; also has consumer app 'ASENSEI Spark' and cloud offering 'ASENSEI Cloud Coach'; XR extension for AR/VR full-body motion capture.
- why: One of the longest-running movement-recognition SDK vendors and explicitly named in the task's must-cover list; its 3D/equipment-recognition angle is potentially relevant to Gravita's apparatus-based skill coaching.
- license: Proprietary, enterprise B2B SDK license.
- maturity: Long-running (since 2021), still shipping new products in 2025-2026 (Spark app, XR extension) — reasonably mature but developer-facing docs/pricing not publicly indexed, suggesting an enterprise sales
- on_device: Uses phone/tablet camera only for 3D full-body motion capture; on-device vs. cloud split unclear — 'Cloud Coach' branding suggests at least some cloud-side processing/scale layer exists alongside any on-device capture, which needs verification agains
- integration: Same caveat as Exer/Kemtai — worth a sales conversation for V0 exploration but not something to bolt into a prototype this afternoon without contacting them.
- caveats: 'Cloud Coach' name raises a real question about whether raw video/frames are ever sent off-device — must be confirmed directly before any consideration, given Yula Motion's hard on-device-only requirement.
- url: https://asensei.ai/
### Onyx (Fitness & AI Coach)
- what: Consumer app claiming 'world's first 3D motion capture system on your phone' — tracks nearly any exercise (squats, planks, push-ups, kicks, running/jumping in place), silhouette rendering, automatic rep counting, form correction, natural-language coaching (recent 2026 updates).
- why: Named explicitly in the task's must-cover list as a possible SDK vendor; scan confirms it is actually a closed consumer app with no developer program, useful only as competitive UX intelligence.
- license: N/A — consumer app, not a licensable SDK.
- maturity: Established consumer brand (Cure.fit-owned lineage), actively updated through 2026, but no evidence of an open developer/licensing program.
- on_device: Unclear/unconfirmed from search results whether the '3D motion capture' runs on-device or via cloud inference.
- integration: Not actionable as build-vs-buy for Yula Motion — useful only as a competitor-UX reference (natural-language coaching, silhouette overlay) rather than a component to license.
- caveats: Included per task's explicit mention, but this is a rival consumer app, not a vendor with a developer SDK — do not treat as a build-vs-buy candidate, only as competitive UX intel.
- url: https://apps.apple.com/us/app/onyx-fitness-ai-coach/id6758569382
### MyLIVIA
- what: Could not identify a real, current product matching this name in web search results — likely a naming confusion, a very small/regional product, or the name has changed. Related adjacent products surfaced instead: 'AI Fitness' (au.com.aifitness — 2D-to-3D pose estimation with 'Coach AI' rep tracking), AIMUVE, AI Fitness Coach (aifitnesscoach.fit), and Motra (trainfitness.ai, smartwatch-based).
- why: Explicitly named in the task's must-cover list; reporting the negative result (not found) is required for an honest scan rather than fabricating details.
- license: N/A
- maturity: Unconfirmed — do not rely on this entry.
- on_device: N/A — unverified.
- integration: None — flag for the founder to supply a corrected name/URL if this vendor is real; do not proceed on assumption.
- caveats: HONEST GAP: 'MyLIVIA' as specified could not be found via web search. This entry lists the closest adjacent products found instead (AI Fitness AU, AIMUVE, AI Fitness Coach, Motra/trainfitness.ai) as possible matches or alternatives — none confirmed as 'MyLIVIA'. Recommend the founder re-check the na
- url: https://aifitness.com.au/
### Roboflow (custom boxing punch-detection models) + academic boxing CV research
- what: No commercial boxing/shadow-boxing SDK vendor exists (unlike fitness-general SDKs above). Instead the space is DIY/research: Roboflow-hosted boxing punch-detection datasets/models (bounding-box punch-type classification: jab/cross/hook/uppercut), and peer-reviewed work (MDPI/PMC papers) on single-camera punch detection and depth-imagery action recognition, one recent paper reporting 96.3% gesture 
- why: Directly answers JabLab's build-vs-buy question by demonstrating there is no commercial boxing-specific SDK to buy — the honest finding is that this must be built in-house on top of a generic pose SDK.
- license: Roboflow platform ToS + whatever license the specific community dataset carries (verify per-dataset — some Roboflow Universe datasets are restrictive).
- maturity: Research-stage; punch-detection-specific commercial SDKs are essentially nonexistent as of 2026 — this is a genuine white-space/gap.
- on_device: Feasible on-device if you export a Roboflow-trained model to TFLite/CoreML, but this is 'build,' not 'buy' — no turnkey vendor found.
- integration: Confirms JabLab likely needs a custom pose-landmark + velocity/angle rule-engine (using generic pose SDKs like MediaPipe/QuickPose/KinesteX for skeleton extraction) rather than any boxing-specific vendor.
- caveats: This is the clearest 'must build' finding in the scan — do not expect to buy a JabLab-ready punch-classification SDK; budget for training your own lightweight on-device classifier on top of generic pose-landmark output.
- url: https://blog.roboflow.com/boxing-punch-detection-computer-vision/


# ==== gravita-domain ====

## SUMMARY
Research turned up a real, current competitive and scientific landscape for Gravita. On the science/CV side, a 2025 systematic review (Frontiers/PMC) and the classic Kerwin & Trewartha 'wrist strategy' biomechanics paper give a solid, citable basis for what to measure (wrist-vs-hip torque balance, center-of-pressure, joint angles) — but note that camera-only phone capture can't measure torque directly, only approximate it via landmark sway/angle variance, which is a real methodological gap. No handstand-specific open-source CV repo was found; the closest analog is a small kick-detection MediaPipe project, and the broader fitness-CV GitHub ecosystem (dozens of small MediaPipe-based rep-counters) confirms MediaPipe Pose as the de facto on-device landmark backbone to build on, though inverted-body pose accuracy is an unverified risk worth testing early. On competitors, the market splits cleanly into three tiers: (1) pure follow-along/curriculum apps and courses (Thenx, Caliverse, Madbarz, GMB, GymFit TV, Movement Athlete, Handstand Factory) with zero camera feedback, (2) async video-upload scoring apps (Calisthenics AI/Titans Grip, Stickd for competitive gymnastics) that score recorded clips but don't appear to do real-time in-session coaching and may be cloud-based, and (3) exactly one close analog — AI Handstand (Android, Google Play) — that already does real-time on-device pose detection with live voice cues for handstands specifically, which is the most important finding: Gravita's core concept is validated but not yet dominant, appears Android-only, and is narrower in scope than the planned 5-skill camera+voice architecture. The clear gap Gravita fills is real-time, in-the-moment voice coaching during the actual hold/kick-up, on-device, across a broader handstand/calisthenics skill progression — something no found competitor fully combines. For curriculum inspiration, GymnasticBodies, Emmet Louis's Handstand Factory, and the r/bodyweightfitness Recommended Routine all provide structurally sound, well-vetted progression logic (mobility/core-compression before pressing, wall-assist before freestanding) that can inform an original progression graph without copying exercise-by-exercise content.

## RECOMMENDATIONS
- Build the CV stack on Google MediaPipe Pose Landmarker (on-device, Apache 2.0, cross-platform) rather than any single community GitHub repo — none found are handstand-specific or production-grade; treat them as pattern references only.
- Immediately install and test AI Handstand (Android) and Calisthenics AI (iOS) firsthand — they are the two closest competitors and neither's on-device vs. cloud architecture nor real pricing/UX was fully verifiable from search alone.
- Validate MediaPipe (or alternative) pose accuracy on genuinely inverted/upside-down bodies early — this is an unverified technical risk, not an assumption to build a roadmap on.
- Position Gravita's wedge explicitly as 'real-time in-hold voice coaching, on-device, across a full skill progression' — this exact combination was not found fully implemented by any competitor.
- Approximate the wrist-strategy balance concept from Kerwin & Trewartha via landmark-sway/joint-angle-variance proxies (since a phone camera can't measure ground-reaction torque), and be explicit internally that this is an approximation, not a direct replication of the force-plate research.
- Use GymnasticBodies/Handstand Factory/r-bodyweightfitness RR only as structural inspiration (mobility-and-compression-before-pressing, wall-assist-before-freestanding) for an ORIGINAL progression graph — do not copy program names, sequencing, or written content verbatim given their proprietary/community-license status.

## RISKS
- No handstand-specific, actively maintained open-source CV repo exists to adapt from — Gravita will need to build the kick-up/hold/alignment classifiers largely from scratch on top of generic MediaPipe landmarks.
- Inverted-pose accuracy for general-purpose pose models (trained predominantly on upright humans) is unverified and could be a core technical blocker discovered only after prototyping.
- Camera-only capture cannot measure the actual biomechanical variable (wrist/hip torque) that the science says matters most — Gravita's rule engine will rely on proxy metrics whose validity against real biomechanics has not been established.
- At least one direct, already-shipping competitor (AI Handstand) appears to already offer real-time on-device pose + voice coaching for handstands specifically — first-mover advantage on the exact concept may already be gone on Android.
- Several pricing/feature claims in this report are sourced from third-party comparison blogs (e.g., Titans Grip's own content, which has an incentive to favor its own app) rather than verified directly on App Store/Play listings — treat exact prices as approximate pending direct verification.
- The r/bodyweightfitness Recommended Routine wiki URL was not directly fetched/confirmed in this research pass — cite with caution until verified.

## ITEMS (name | license | on_device | url)
### Biomechanical analyses of the handstand: a systematic review (2025)
- what: Systematic review (Frontiers in Sports and Active Living / PMC, 2025) synthesizing handstand biomechanics literature: 31% of included studies analyze balance-control strategies, 57% do kinetic/kinematic analysis, 42% analyze center-of-pressure, 36% analyze joint angles.
- why: Gives Gravita a citable, current evidence base for which joint angles and CoP metrics actually matter for handstand quality — directly informs which landmarks/metrics the rule engine should compute.
- license: Open access article
- maturity: Peer-reviewed 2025 review, freely available PMC full text
- on_device: N/A (research reference, not code)
- integration: Reference only — use as the scientific basis for Gravita's alignment/balance rule engine design; do not copy figures.
- caveats: Secondary review, no code/dataset attached; need to chase primary studies it cites (e.g. Kerwin & Trewartha) for exact joint-angle thresholds.
- url: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12745452/
### Kerwin & Trewartha — Strategies for maintaining a handstand in the anterior-posterior direction (2001, PDF hosted by Circoteca)
- what: Classic biomechanics paper establishing the 'wrist strategy' — gymnasts balance primarily via ankle-like wrist torque adjustments, with hip/shoulder torque contributions increasing as balance quality degrades.
- why: This is the core mental model to encode in Gravita's deterministic rule engine: score handstand quality by how much correction is happening at wrist vs. hip/shoulder — a hip-torque-dominant handstand = 'unstable/compensating' cue.
- license: Academic PDF mirror — cite properly, do not redistribute wholesale
- maturity: Peer-reviewed, foundational, frequently cited (20+ years, still central to 2025 systematic review)
- on_device: N/A (concept reference)
- integration: Translate wrist-vs-hip torque ratio concept into a proxy metric computable from pose landmarks (e.g. shoulder-hip-ankle deviation over time as a stand-in for torque, since camera can't measure force directly).
- caveats: Original study used force plates under the hands — a phone camera cannot measure wrist torque directly; Gravita must approximate with landmark-sway/angle-variance proxies, which is a real methodological gap to flag internally.
- url: https://www.circoteca.cl/wp-content/uploads/2019/08/Strategies-for-maintaining-a-handstand-in-the-anterior-posterior-direction-Revista-Ingles-DAVID-G.-KERWIN-GRANT-TREWARTHA-2001.pdf
### Balance control strategies during perturbed and unperturbed balance in standing and handstand (Royal Society Open Science)
- what: Study comparing balance strategies (ankle/wrist vs. hip) between upright standing and handstand under perturbation.
- why: Useful for understanding how balance strategy differs when a beginner is 'wobbling' vs. a trained handbalancer — informs difficulty-adaptive coaching cues (e.g., different voice cues for a shaky first-timer vs. an advanced athlete drifting slightly).
- license: Open access
- maturity: Peer-reviewed, Royal Society journal
- on_device: N/A
- integration: Reference for state-machine design distinguishing 'stable hold', 'active correction', and 'falling' states.
- caveats: Lab study with instrumented perturbation platforms; camera-based inference of these states will be much noisier.
- url: https://royalsocietypublishing.org/rsos/article/4/7/161018/93310/Balance-control-strategies-during-perturbed-and-unperturbed-balance-in-standing-and-handstand
### pachauriyash/Kick-Detection-and-pose-estimation
- what: Open-source (GitHub) project using MediaPipe pose + YOLOv3 to detect and count 'kicking' vs 'standing' motion phases from video, with a trained classifier.
- why: Closest existing open-source analog to a handstand kick-up detector — same core problem (classify a dynamic leg-swing motion phase from pose landmarks) that Gravita needs for kick-up analysis and rep/attempt counting.
- license: Check repo license before adapting (not stated in search result — verify on GitHub before use)
- maturity: Small hobby repo, unclear stars/last-commit activity (not verified — treat as a pattern reference, not production-ready)
- on_device: MediaPipe pose is On-device-viable on both iOS/Android (Google's MediaPipe Tasks has native mobile runtimes); the YOLOv3 person-detection layer would need to be swapped for a lighter on-device detector or dropped for single-person framing.
- integration: Adapt the phase-classification approach (pose-sequence → binary/multi-class motion-phase classifier) as a Kotlin/Swift-side state machine input, not a literal YOLOv3 port.
- caveats: Unverified maturity/activity — must inspect the actual repo (stars, last commit, license) before committing engineering time; likely a student/portfolio project rather than battle-tested library.
- url: https://github.com/pachauriyash/Kick-Detection-and-pose-estimation
### MediaPipe Pose (Google) — mediapipe-pose GitHub topic ecosystem
- what: Google's MediaPipe Pose Landmarker (33-keypoint 3D pose) is the de facto standard on-device pose backbone used across the fitness-CV open-source ecosystem (Exercise-Counter, GYM-pose-estimation-using-mediapipe, Pose-Estimation-for-Fitness-Exercise-Analysis, etc.).
- why: This is the landmark extraction layer Gravita (and likely all 5 Yula Motion apps) should build on: free, on-device, cross-platform (iOS/Android via native + Flutter plugin wrappers exist), real-time, and the pattern of 'landmarks → joint angles → rul
- license: MediaPipe core is Apache 2.0 (commercial-use friendly); individual community repos vary — check each before adapting code, though the pattern (not the code) is the main value.
- maturity: MediaPipe itself is a mature, actively maintained Google framework; the community repos built on it vary widely in quality — most are small student/portfolio projects, not production libraries.
- on_device: Yes — MediaPipe Tasks Pose Landmarker runs on-device on both iOS and Android (and has a Flutter plugin ecosystem, e.g. google_mediapipe/mediapipe wrappers), which satisfies the raw-video-never-leaves-device constraint.
- integration: Native bridge: Kotlin/Swift MediaPipe Tasks Pose Landmarker feeding landmark streams into a Dart/Flutter-side (or native) deterministic rule engine + state machine, exactly matching Gravita's binding architecture.
- caveats: None of the individual community repos are handstand-specific or vetted for production; they demonstrate the pattern, not a drop-in solution. Inverted-body pose accuracy (upside-down human detection) is a known weak spot for general pose models trained mostly on upright humans — this should be valid
- url: https://github.com/topics/mediapipe-pose
### Calisthenics AI (Titans Grip)
- what: iOS/Android app that scores calisthenics/handstand form 0-100 from uploaded video, gives an AI coach chat, skill progressions, and macro tracking. Free tier = 3 video analyses/week; Premium $19.99/month or $179.99/year.
- why: THE closest direct competitor — the only app found in this research that actually does camera-based video pose scoring for handstand/calisthenics skills specifically. Sets the price ceiling and feature bar Gravita must beat or differentiate from.
- license: N/A (commercial app)
- maturity: Active in 2026 comparison content; standalone app store presence not independently re-verified in this pass (verify listing directly before quoting further).
- on_device: Unknown/likely cloud-based — 'upload video' + 'AI coach chat' phrasing suggests server-side LLM/CV processing, which would be DISQUALIFIED under Gravita's on-device-only, video-never-leaves-device constraint.
- integration: N/A — competitor, not a component
- caveats: Uses async 'upload and score' video review, not real-time in-session voice coaching during the hold/kick-up — this is the concrete gap Gravita's real-time camera+voice loop fills. Pricing/feature claims sourced from a third-party blog post (Titans Grip's own comparison content, which has an obvious 
- url: https://www.titans-grip.com/blog/best-calisthenics-app-2026/
### AI Handstand (Google Play)
- what: Android app: real-time on-device pose detection for handstand practice, live audio cues ('Lock your arms', 'Stack your hips', 'Perfect, hold!'), imported-video frame-by-frame skeleton analysis, 3 difficulty tiers (Amateur/Fitness/Olympics), Pro progress dashboard.
- why: This is the single most direct existing competitor to Gravita's exact concept (real-time on-device pose + voice coaching for handstands) found in this research — essentially a proof that the concept works and has market demand, but appears Android-on
- license: N/A (commercial app)
- maturity: Listed on Google Play; download/rating numbers and last-update date not confirmed in this pass — verify directly on the store listing.
- on_device: Yes, per listing copy ('advanced on-device AI') — this is the one competitor that appears to already meet the on-device constraint.
- integration: N/A — direct competitor to study closely (install and test) before finalizing Gravita's differentiation.
- caveats: No iOS version found in this research pass — potential opening for Gravita on iOS. Voice-cue phrasing and skeleton-overlay UI described are exactly the kind of feature Gravita should study firsthand (install + test) rather than assume from store-copy description alone. No pricing was surfaced in sea
- url: https://play.google.com/store/apps/details?id=com.aihandstand.android&hl=en_US
### Stickd: Gymnastics AI Coach
- what: iPhone/iPad app using 60fps pose detection to score competitive gymnastics routines (beam/floor/vault/bars) against FIG/USAG Code of Points, detects specific form deductions, prescribes corrective drills. $4/gymnast/month, 7-day free trial.
- why: Adjacent-market proof point: shows camera-based, joint-level, rule-based (Code-of-Points) scoring is viable on-device at consumer smartphone framerates and cheap price points — validates the technical approach even though it targets competitive gymna
- license: N/A (commercial app)
- maturity: Active app with App Store listing (id6759934909) as of 2026
- on_device: Ambiguous — 60fps capture + 'pose detection to build data the AI needs to score' language doesn't confirm on-device vs cloud inference; needs direct verification.
- integration: N/A — analog/adjacent competitor for pricing and rule-engine-against-codified-standard pattern reference.
- caveats: Targets club/team gymnasts and coaches (roster management), not solo hobbyist handstand practice — different buyer, but same underlying CV pattern worth studying.
- url: https://stickd.app/
### The Movement Athlete
- what: App covering 9 fundamentals + advanced calisthenics skills (planche, front lever, handstand, muscle-up) with an 'AI coach' that personalizes progression based on initial assessment + logged performance data over time — but assessment appears to be self-reported/logged, not camera-analyzed.
- why: Represents the dominant existing model in this space: algorithmic progression planning WITHOUT camera-based form analysis — the gap Gravita's camera+voice loop is built to close.
- license: N/A (commercial app)
- maturity: Established app, multi-year presence, active App Store/Play listings
- on_device: N/A — no camera/CV component identified
- integration: N/A — competitor
- caveats: Exact subscription price not confirmed in this research pass (pricing page URL found but content not retrieved) — verify before quoting a number.
- url: https://themovementathlete.com/pricing/
### GymFit TV / GymnasticBodies Handstand Series
- what: Video-lecture-based handstand curriculum (Foundation series + dedicated 3-level Handstand Series) by Christopher Sommer; no app, no camera feedback — pure follow-along video + written material. Handstand Series: $99.99/level or $275 for all three; GymFit TV plans ~$225 each or $99 for short series.
- why: Represents the 'YouTube-follow-along' category at the premium end — expensive, no feedback loop, purely instructor-led video. Also the strongest CURRICULUM inspiration source: emphasizes building shoulder/wrist mobility and core compression BEFORE pr
- license: Proprietary curriculum content — DO NOT copy exercise sequencing/naming verbatim; use only as conceptual inspiration for an original progression graph.
- maturity: Long-established (10+ years), well-known in gymnastics-strength community
- on_device: N/A
- integration: N/A — curriculum inspiration only
- caveats: No camera analysis of any kind, confirming the market gap. Pricing sourced from a third-party comparison blog (Titans Grip), not GMB's own site directly — worth a direct confirmation.
- url: https://www.gymnasticbodies.com/handstand-progressions-train-your-pace/
### Emmet Louis / Handstand Factory
- what: Handbalancing-specific curriculum (10 programs from beginner freestanding handstand through one-arm handstand) blending circus hand-balancing tradition with modern biomechanics/sport-science research; one-time purchase, lifetime access. Also offers 1:1 online coaching at €300/month (6-month minimum commitment).
- why: Strongest curriculum-authority source for Gravita specifically because Louis explicitly grounds his method in biomechanics research (same literature base as the CV thread above) rather than pure gymnastics tradition — good structural inspiration for 
- license: Proprietary — inspiration only, no copying of program structure or written material
- maturity: Established, well-regarded specialist coach in the handbalancing niche (circus/calisthenics crossover community)
- on_device: N/A
- integration: N/A — curriculum inspiration; also a potential future advisor/partnership contact given his explicit biomechanics orientation
- caveats: €300/month coaching price shows how expensive live expert handstand coaching is — reinforces the value proposition of an affordable AI camera+voice alternative.
- url: https://emmetlouis.com/handstand-factory/
### r/bodyweightfitness Recommended Routine (RR)
- what: Community-standard free bodyweight program including a handstand skill-work block (pike stands, planks, kick-ups, assisted/wall handstands) alongside a 3-pair strength circuit.
- why: Represents the free, community-driven baseline that most self-taught handstand practitioners already follow — Gravita's original progression graph should be at least as sound as this widely-vetted free resource, and can reference its general skill-bl
- license: Community wiki content — inspiration only, do not reproduce verbatim
- maturity: Long-running, community-vetted (years of iteration), free
- on_device: N/A
- integration: N/A — curriculum inspiration
- caveats: The exact r/bodyweightfitness wiki URL was not directly fetched/verified in this pass (search engine paraphrase used instead) — confirm the live wiki page before citing specifics.
- url: https://www.reddit.com/r/bodyweightfitness/wiki/kb/recommended_routine (exact wiki page not directly fetched — see search summary)


# ==== lissom-domain ====

## SUMMARY
Research across three threads for Lissom (mobility/flexibility/yoga assessment app). (1) Science/tech: smartphone-as-goniometer apps are moderately-to-well validated for some joints (shoulder flexion strong, ankle dorsiflexion more variable, ICC 0.53-0.91 depending on app/protocol) but that literature is mostly phone-held-against-limb inclinometer apps, not full markerless camera pose estimation. The best direct precedent for camera-based mobility assessment is Amazon's peer-reviewed Halo Movement study (5-exercise battery vs 3D mocap + 13 standard functional tests, moderate-strong correlations, discontinued for business reasons not tech failure) — a strong template to emulate. MediaPipe Pose (BlazePose, Apache 2.0, on-device, actively maintained by Google) is the clear open-source backbone choice satisfying the on-device constraint; Yoga-82 is the standard yoga-pose classification benchmark (Xception ~82.5%/92.4%) but its commercial-use license needs verification and it's static-image classification, requiring Lissom to add its own temporal/rule-engine layer for real-time coaching. Pose2Sim is a useful open-source algorithmic reference for landmark→joint-angle conversion, though not mobile-deployable as-is. A 2026 JMIR paper on camera positioning effects on pose-estimation accuracy should directly inform Lissom's camera-setup onboarding UX. (2) Competitors: GOWOD is the closest direct rival, with an existing ~10-12 min guided mobility test → personalized score → daily program loop, but its public marketing pages do not disclose whether the test is CV-scored or self/visual-rated — this is an open gap requiring a hands-on account walkthrough. StretchIt/Pliability(ROMWOD)/Bend and Down Dog/Alo Moves are confirmed to be instructor-led video libraries with no measurement component, at ~$15-20/mo or ~$160-180/yr — clear pricing benchmark and clear white space for CV-measured assessment. Zenia is a real cautionary precedent (early real-time CV yoga feedback app) that appears to have been abandoned by 2022, though no confirmed shutdown reason was found — evidence is genuinely thin here and flagged as such. Exakt Health, despite being named in the brief as a CV competitor, shows no strong evidence of camera-based assessment in available sources (it reads as PT-content-driven); Exer AI surfaced instead as a more plausible CV-assessment adjacent player worth a follow-up look. (3) Assessment protocols: FMS and the Overhead Squat Assessment both have good rater reliability (ICC/kappa ~0.7-0.85) but real, well-documented validity criticisms — FMS's injury-prediction validity is genuinely contested across studies, and OHS is explicitly criticized as subjective/rater-dependent and 2D-limited despite the movement itself being 3D. Amazon Halo Movement's battery literally includes the overhead squat, reinforcing it as a strong, precedented movement for Lissom's own battery — with CV-based objective scoring pitched as the fix for OHS's core documented weakness (rater subjectivity). FDA general-wellness guidance is clear that avoiding diagnostic/disease-specific language is what keeps a wellness score exempt from device regulation — this should become a concrete copywriting checklist item.

## RECOMMENDATIONS
- Build the core CV stack on MediaPipe Pose Landmarker (Apache 2.0, on-device, native Android/iOS bindings) rather than training a bespoke model from scratch — it is the most mature, free, commercially-usable, on-device-viable option found, and underlies most comparable open-source projects surveyed.
- Design Lissom's assessment battery (5-8 movements) directly modeled on the Amazon Halo Movement protocol (single-leg stance, lunge, overhead squat, overhead reach, squat) since it's the only peer-reviewed precedent for exactly this concept, then run Lissom's own small validation study (even n=20-30 vs a manual goniometer/known-good reference) before making any 'measures your mobility' claim.
- Explicitly position CV-based objective scoring as solving the FMS/OHS literature's documented weakness (rater subjectivity, inconsistent injury-prediction validity) in marketing copy — this is a defensible, literature-backed differentiation angle, not just a feature claim.
- Do a hands-on (not web-only) teardown of GOWOD's actual mobility test flow via a real account signup to resolve whether it's CV-scored or self-rated — this is the single most important open competitive-intel question and materially changes how differentiated Lissom's tech actually is.
- Keep all in-app score/report language in 'general wellness' territory per FDA guidance: no disease/condition names, no diagnostic verbs, no injury-prediction claims, standard 'not a substitute for professional assessment' disclaimer — bake this into a copy-review checklist before launch.
- Treat ankle dorsiflexion and any 2D-only overhead/squat-type assessment as lower-confidence measurements in-app (wider score bands / qualitative framing) given literature shows more measurement variability there than for shoulder flexion; don't imply equal precision across all measured joints.
- Verify Yoga-82's license terms explicitly before any commercial training use; if restrictive, use it only as an accuracy benchmark and source Lissom's own labeled data or use a lighter architecture (MobileNet-class) fine-tuned for on-device commercial deployment.

## RISKS
- GOWOD's exact test mechanism (CV vs self-rated) is unresolved from public sources — Lissom's competitive positioning claims could be wrong in either direction until this is verified hands-on.
- Zenia's failure reasons are unconfirmed (thin evidence) — treating it as a clear cautionary tale risks drawing the wrong lesson (could have failed on funding/business model, not on-device CV feasibility).
- Published ROM validation studies mostly test phone-as-inclinometer apps, not markerless multi-joint camera pose estimation — Lissom cannot cite this literature as direct proof its own camera-based system will hit the same accuracy; independent validation is required.
- FMS's contested injury-prediction validity is a real, unresolved scientific debate — any implication that Lissom's assessment predicts injury risk needs its own evidence, not borrowed authority from FMS/OHS literature.
- 2D single-camera CV inherits the OHS literature's documented 2D-vs-3D limitation (e.g., can't reliably capture internal hip rotation) — this is a real technical ceiling for any single-phone-camera assessment, not just a UX problem to solve with better camera-placement coaching.
- FDA general-wellness exemption depends entirely on avoided claims/language — a single overreaching in-app phrase (e.g., naming a condition, or claiming to 'detect' an impairment) could push Lissom into regulated-device territory or trigger App Store medical-app review requirements; this needs actual legal review before launch, not just this research summary.

## ITEMS (name | license | on_device | url)
### Smartphone goniometer apps (Clinometer-class ROM validation studies)
- what: Cluster of published validation studies comparing smartphone inclinometer/goniometer apps to universal goniometer gold standard for joint ROM (ankle dorsiflexion, shoulder flexion, cervical, lower extremity).
- why: Directly answers the science question: smartphone-based angle measurement (not full CV pose, but phone-as-inclinometer) is reasonably validated for SOME joints. Shoulder flexion shows excellent agreement; ankle dorsiflexion is more mixed (ICC 0.53–0.
- license: N/A (research literature)
- maturity: Multiple peer-reviewed studies, ongoing through 2024-2025
- on_device: N/A — informs calibration targets, not a library to integrate
- integration: Use as accuracy benchmark/citation for marketing + internal QA thresholds (e.g. target ICC>0.8 vs a manual goniometer on a validation set before claiming 'measures ROM')
- caveats: These studies mostly test single-plane inclinometer apps (phone held against limb), not markerless video pose estimation — different tech than what Lissom will likely use (camera-at-distance CV). Do not conflate the two when citing 'validated ROM measurement.'
- url: https://pmc.ncbi.nlm.nih.gov/articles/PMC12121316/
### Ankle dorsiflexion smartphone goniometer reliability study (PMC8464192)
- what: Reliability study of a smartphone goniometer app for weight-bearing lunge ankle dorsiflexion ROM.
- why: Ankle dorsiflexion is one of the three joints explicitly named in the task; shows intra-rater ICC 0.72–0.82, inter-rater ICC 0.73, i.e. moderate-good but not gold-standard — useful caveat for any ankle mobility score Lissom ships.
- license: N/A
- maturity: Peer-reviewed, published
- on_device: N/A
- integration: Cite in internal validity documentation / avoid overclaiming precision for ankle dorsiflexion test in-app copy
- caveats: Small clinical sample, weight-bearing lunge protocol only — not directly transferable to markerless full-body camera capture.
- url: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8464192/
### Overhead squat markerless motion capture concurrent validity study
- what: Deep-learning markerless motion capture system validated against optical/marker-based 3D motion capture during the overhead squat, measuring systematic bias per joint angle.
- why: Closest published analog to what Lissom needs for squat-depth/overhead-squat style assessments — shows markerless single/few-camera systems can get mean bias <10° for most joints, which is a realistic accuracy bar to design toward and to NOT overclai
- license: N/A
- maturity: Peer-reviewed 2024/2025 publication
- on_device: System described runs deep-learning pose model, feasible on-device with a lighter model but original study used a research-grade setup — treat as accuracy ceiling reference, not a drop-in SDK
- integration: Reference for setting internal QA/validation bar for Lissom's squat-depth and overhead-reach assessment modules; do not cite as 'clinically validated' without running Lissom's own validation
- caveats: Uses 'Ergo' system with own camera setup, not consumer single-phone-in-hand; bias figures won't directly transfer to a handheld/tripod smartphone setup with variable lighting.
- url: https://pmc.ncbi.nlm.nih.gov/articles/PMC11603033/
### JMIR mHealth: Evaluation of Smartphone Camera Positioning on AI Pose Estimation Accuracy for Exercise Detection
- what: 2026 observational study on how smartphone camera angle/positioning affects pose-estimation accuracy for exercise detection.
- why: Extremely relevant practically — tells Lissom's onboarding/camera-setup UX design what positioning constraints (distance, angle, height) matter most for measurement accuracy, straight from a 2026 study.
- license: N/A
- maturity: Just-published (2026), observational study
- on_device: Directly informs on-device camera-setup coaching flow
- integration: Use findings to script the app's guided camera-placement calibration screen (a UX/accuracy lever independent of the pose model itself)
- caveats: Read the full paper before citing specific angle/distance numbers — only the abstract-level summary was retrieved here.
- url: https://mhealth.jmir.org/2026/1/e82412
### Validation of Amazon Halo Movement (npj Digital Medicine, 2022)
- what: Peer-reviewed validation of Amazon's discontinued Halo Movement feature: front-camera smartphone computer vision assessing movement health via 5 exercises (single-leg stance, forward lunge, overhead squat, overhead reach, feet-together squat), benchmarked against 3D motion capture and 13 standard functional movement tests on 150 participants.
- why: This is the single best public precedent for exactly what Lissom is trying to build — a phone-camera CV movement/mobility assessment with peer-reviewed validation. It also proves the concept was commercially viable enough for Amazon to ship it (then 
- license: N/A (research); the product is dead, no code released
- maturity: Published Sept 2022, peer-reviewed, well-cited; product itself discontinued when Amazon shut down Halo line in 2023
- on_device: Ran on-device via phone camera + on-device/cloud hybrid ML (Amazon didn't publish exact split); proves architecture is feasible for consumer phones
- integration: Model Lissom's own validation study design directly on this protocol (5 defined movements vs multi-instrument gold standard); also justifies the 'test battery' structure
- caveats: Exact on-device vs cloud processing split for Halo Movement not confirmed in available sources — Lissom's binding constraint is 100% on-device, so architecture must be independently verified, not assumed identical.
- url: https://www.nature.com/articles/s41746-022-00684-9
### Yoga-82 dataset + Xception/hierarchical CNN yoga pose classification
- what: 82-class, 28.4k-image, 3-level hierarchical yoga pose dataset; Xception model achieves 82.52% top-class accuracy (92.42% on 6 superclasses); hierarchical DenseNet variants ~79%.
- why: Standard academic benchmark/dataset for yoga pose classification — relevant if Lissom does yoga pose recognition/correction; shows realistic accuracy ceiling (~80-92%) for fine-grained pose classification from images, and that hierarchical (coarse-to
- license: Dataset released for research use — check exact Yoga-82 license terms before any commercial training use (typically academic/non-commercial by default; must verify)
- maturity: CVPR workshop 2020 paper, dataset still actively used/cited in 2024-2025 follow-on work
- on_device: Trained models (Xception etc.) are heavy for on-device; would need distillation/quantization (e.g. MobileNet variant, which the same paper also benchmarks) for real-time on-device inference
- integration: Use as pretraining/fine-tuning data source (if license permits commercial use) or as an accuracy benchmark target for Lissom's own yoga pose classifier; MobileNetV2 variants in follow-up literature are more appropriate for on-device deployment than X
- caveats: Static single-pose classification (photos), not continuous real-time video coaching with voice feedback — Lissom needs temporal/frame-loop rule engine on top, not just per-frame classification. Verify Yoga-82's commercial-use license explicitly before use — original CVPRW datasets are frequently res
- url: https://arxiv.org/pdf/2004.10362
### MediaPipe Pose (BlazePose) / MediaPipe Tasks Pose Landmarker
- what: Google's on-device pose estimation model (33 body landmarks), runs real-time on mobile CPU/GPU, available via native Android/iOS/Flutter bindings.
- why: The most mature, free, commercially-usable on-device pose backbone available today for exactly this family's binding constraint (on-device only, single camera). It's the de facto standard underlying nearly all the open-source fitness/mobility repos f
- license: Apache 2.0 — permits commercial use
- maturity: Actively maintained by Google (part of MediaPipe/Google AI Edge), production-grade, used in thousands of apps
- on_device: Purpose-built for on-device real-time inference on mobile; this is the strongest on-device viability option for the whole Motion family, not just Lissom
- integration: Native Android (Kotlin) + iOS (Swift) MediaPipe Tasks bindings, or a Flutter plugin wrapper calling into native MediaPipe — matches the stated Flutter UI + native Kotlin/Swift camera/ML bridge architecture exactly
- caveats: Gives 2D (and rough 3D/z-depth-estimated) landmarks only from a single RGB camera — true joint-angle ROM accuracy depends heavily on camera placement/perspective (see JMIR 2026 paper above) and needs Lissom's own calibration/validation layer on top, not just raw landmark angles.
- url: https://github.com/google-ai-edge/mediapipe
### Pose2Sim (open-source markerless kinematics)
- what: Open-source Python toolkit converting 2D pose estimation (including MediaPipe/BlazePose) into 3D OpenSim-compatible kinematics from consumer cameras.
- why: Concrete open-source reference implementation for turning single/multi-camera 2D pose into biomechanically meaningful joint angles — useful as an algorithmic reference (not a mobile SDK) for how to convert raw landmarks into clinically-styled ROM num
- license: Check repo (typically BSD/MIT-family for these academic toolkits — verify exact LICENSE file)
- maturity: Active open-source project, research-community maintained
- on_device: Not designed for mobile on-device execution (Python/OpenSim desktop pipeline) — useful as an algorithm/method reference to reimplement in Kotlin/Swift, not to embed directly
- integration: Study its angle-calculation and calibration methodology as a spec for Lissom's native rule-engine that converts MediaPipe landmarks into joint-angle ROM scores
- caveats: Desktop/offline oriented; would need a from-scratch native reimplementation of its angle math for real-time on-device mobile use.
- url: https://github.com/perfanalytics/pose2sim
### GOWOD (mobility test + daily program) — direct competitor
- what: Mobility & stretching subscription app with an in-app 'mobility test': ~10-12 minute guided assessment across shoulders/overhead, thorax, hips, posterior chain, ankles, producing a mobility score that personalizes daily 10-30 min routines; retested periodically to track score change over time (app claims 18% mobility gain in 60 days for daily Premium users).
- why: This is Lissom's most direct competitor and the one the task explicitly flags — 'their mobility test!' It already ships the assessment→personalized-program loop Lissom is aiming for. Test methodology (self-guided movement + presumably self/visual-rat
- license: N/A — competitor product
- maturity: Established indie/scaleup product, live in App Store/Play Store, active marketing site, promotional pricing seen (up to 30-35% off, base price not published on the fetched page)
- on_device: Unknown — not disclosed whether GOWOD uses on-device CV or manual/visual self-scoring; this is the single biggest unresolved competitive-intel gap and should be closed via an actual account signup + trying the test flow (hands-on teardown), not just 
- integration: N/A — competitor to differentiate against
- caveats: Flagged explicitly: pricing page redirects to premium.gowod.app and did not surface a concrete number; and the core mechanism (CV-measured vs self-rated) is unconfirmed from public marketing pages — needs a real account walkthrough to verify before making competitive claims.
- url: https://www.gowod.app/how-it-works
### StretchIt / Pliability (formerly ROMWOD) / Bend — video-library flexibility apps
- what: Subscription stretching/mobility video-class libraries. StretchIt $19.99/mo or $160/yr; Pliability $17.95/mo or $179.95/yr (7-day free trial); Bend has one free starter flow then subscription for the rest (exact price not found).
- why: Establishes the competitive pricing band (~$15-20/mo, ~$160-180/yr) Lissom should benchmark against, and confirms these apps are instructor-led video libraries rather than CV-measured assessment tools — a clear differentiation opportunity for Lissom'
- license: N/A — competitors
- maturity: Established, live products (Pliability is the rebrand of ROMWOD)
- on_device: None known — no camera-based measurement claimed by any of the three in sources found
- integration: N/A — pricing/positioning benchmark only
- caveats: Did not independently verify Bend's exact price point; sourced via a Pliability-owned comparison article (potential competitor bias) — cross-check with Bend's own site before using in a pricing deck.
- url: https://pliability.com/stories/bend-vs-stretchit
### Down Dog / Alo Moves — algorithmic/curated video yoga apps (no measurement)
- what: Down Dog generates algorithmically-varied yoga sessions from user-selected style/level/duration/focus-area settings; Alo Moves is a curated pre-recorded class library across yoga/strength/pilates/meditation.
- why: Confirms neither app measures flexibility/ROM or uses camera-based assessment — they personalize by user-selected preference, not by measured capability. Reinforces that essentially the entire yoga-app category is video-library/preference-based, leav
- license: N/A — competitors
- maturity: Both established, widely-used commercial apps
- on_device: None — no CV/measurement component found
- integration: N/A — positioning contrast only
- caveats: Search-based summary, not a hands-on teardown of either app's current (2026) feature set — worth a quick hands-on check before finalizing competitive claims, since app feature sets change.
- url: https://blog.alomoves.com/most-popular-1/how-to-do-downward-dog-3e75x
### Zenia — historical AI yoga feedback app (cautionary precedent)
- what: Billed as 'world's first virtual assistant using AI to give real-time feedback on yoga practice' via computer vision/motion tracking; by 2022 user reviews reported the app broken ('just loads a blank screen') with no developer response, suggesting effective abandonment; no independent confirmation of a formal shutdown announcement was found.
- why: Directly named in the task as a cautionary history — an earlier attempt at almost exactly Lissom's concept (real-time CV yoga feedback) that appears to have failed/been abandoned. Important precedent to study for failure-mode lessons (technical relia
- license: N/A
- maturity: Defunct/abandoned as of available evidence (last clear signal 2022); could not confirm exact shutdown date or stated reason
- on_device: Unknown — marketing described 'machine learning, computer vision, and motion tracking' but no technical/architecture detail found on device vs cloud split
- integration: N/A — historical cautionary case study
- caveats: Evidence is thin: no official shutdown announcement, postmortem, or news article found confirming why Zenia failed (technical failure vs funding vs pivot) — flagged explicitly per task instructions; worth a deeper targeted search (Crunchbase/LinkedIn last-activity check) before drawing firm lessons.
- url: https://justuseapp.com/en/app/1483602673/yoga-for-beginners-zenia-app/reviews
### Exakt Health / Exer AI — CV-based movement/PT assessment (adjacent competitor)
- what: Exakt Health: PT-reviewed running/rehab plans app (running plans, mobility & strength, injury rehab) — no strong evidence of computer-vision movement scoring in sources found. Exer AI (separate company, surfaced in same search) explicitly offers 'Validated Evaluation Modules' for camera-based movement assessment.
- why: Adjacent-market competitive intel: confirms Exakt Health is PT-content-driven rather than CV-measurement-driven (contrary to the task's assumption it might be a CV competitor), while surfacing Exer AI as a separate, more relevant CV-movement-assessme
- license: N/A — competitors
- maturity: Exakt Health: established consumer app; Exer AI: appears to be a B2B/clinical-facing movement-assessment platform, maturity unconfirmed
- on_device: Unconfirmed for both — Exer AI's 'validated' framing suggests possible clinical-grade cloud processing rather than on-device; needs direct verification
- integration: N/A — competitive landscape mapping only
- caveats: Original task named 'Exakt Health' specifically as a camera/CV competitor to check — available evidence does NOT support that framing; this may indicate the task brief was working from outdated or incorrect info, or Exakt Health has a CV feature not surfaced in these searches. Recommend a direct han
- url: https://www.exer.ai/product/modules
### FMS (Functional Movement Screen) — validity/reliability + criticism
- what: 7-test movement screen (deep squat, hurdle step, inline lunge, shoulder mobility, active straight-leg raise, trunk stability push-up, rotary stability) scored 0-3 per test. Meta-analysis: intra/inter-rater ICC ~0.81 (good reliability); injury-prediction validity is contested — some studies find 2.74x odds ratio at cutoff ≤14, others find no predictive validity at all; reviewers note both internal 
- why: Primary 'inspiration + criticism' reference the task asked for. Key lesson for Lissom's own test battery: reliability (consistency) and validity (does it predict/mean anything) are separate properties — FMS nailed the former, is contested on the latt
- license: FMS itself is a proprietary certified system (Functional Movement Systems) — Lissom must NOT reuse FMS's exact named tests/scoring/branding, only draw structural inspiration
- maturity: Long-established clinical tool (2000s), extensively studied, meta-analyses through 2020s
- on_device: ?
- integration: Use as a structural template (multi-region composite score, standardized 0-3-style scoring bands) but build an original, differently-named test battery to avoid IP/trademark issues and to sidestep FMS's specific validity criticisms
- caveats: Mixed injury-prediction evidence across studies is a genuine open scientific question, not just 'old tool needs updating' — Lissom should avoid claiming its own battery predicts injury risk without doing its own validation.
- url: https://journals.sagepub.com/doi/abs/10.1177/0363546516641937
### Overhead Squat Assessment (OHS) — validity/reliability + criticism
- what: Single-movement compensatory-pattern screen (arms overhead squat, observed for knee valgus, forward lean, heel rise, etc.). Intrarater reliability ~0.60-0.76 (avg 0.70); interrater Fleiss kappa ~0.69-0.70 (substantial). Explicitly criticized as subjective/rater-dependent, validated mainly in 2D while the actual movement compensation is 3D (e.g., internal hip rotation), and studies note lack of rat
- why: Second structural inspiration/criticism source. Directly useful because it's literally one of the 5 movements in the Amazon Halo Movement validation battery — strong signal this specific movement pattern is a good, well-precedented candidate for Liss
- license: General movement-screening concept is not proprietary in the way FMS is, but NASM's specific branded protocol/scoring criteria should not be copied verbatim
- maturity: Well-studied clinical/S&C screening tool, part of NASM curriculum
- on_device: ?
- integration: Strong candidate movement for Lissom's core assessment battery; explicitly pitch CV-based objective scoring as solving the rater-subjectivity criticism found in the literature
- caveats: 2D observation criticized for missing 3D compensations (e.g., internal hip rotation) — a single-camera CV system inherits this same 2D limitation unless Lissom adds a second view/angle or infers 3D via model — worth flagging as a known open technical gap, not a solved problem.
- url: https://pubmed.ncbi.nlm.nih.gov/27834577/
### FDA general wellness guidance vs regulated medical device
- what: FDA policy: products/software that support a healthy lifestyle without referencing diagnosis/treatment/cure/mitigation/prevention of a specific disease or condition qualify as low-risk 'general wellness' products, exempt from FDA device regulation. What matters is the claims made, not the underlying technology.
- why: Directly governs the language constraint the task calls out. Lissom must never claim to 'diagnose,' 'treat,' or reference a named medical condition (e.g., can't claim to detect a rotator cuff tear or assess 'hypermobility syndrome' diagnostically) — 
- license: N/A — regulatory guidance
- maturity: Established, current FDA policy area; cited source notes a Jan 2026 guidance update
- on_device: N/A
- integration: Bake into copywriting/legal review checklist: avoid disease/condition names, diagnostic verbs ('diagnose,' 'detect [condition]'), and injury-prediction claims in all Lissom in-app score/report language; add a standard 'not a substitute for profession
- caveats: This is general regulatory guidance, not legal advice specific to Lissom — recommend an actual App Store Guideline 1.4.1 (medical apps) check plus light legal review of final in-app copy before launch, not just relying on this summary.
- url: https://pmc.ncbi.nlm.nih.gov/articles/PMC9280986/


# ==== jablab-domain ====

## SUMMARY
Research turned up a cluster of 2024-2025 academic boxing-pose datasets (BoxingVI, BoxMAC, MPOSE2021's boxing subset, a hierarchical transformer+3D-CNN punch classifier) that converge on the same 6-punch taxonomy (jab/cross/lead+rear hook/lead+rear uppercut) JabLab should use, all built on pose-keypoint pipelines (AlphaPose/OpenPose/PoseNet) rather than raw pixels — directly supporting a deterministic, landmark-driven rule engine. However every dataset found is small, academic, and of unverified license/maturity (BoxMAC's arXiv submission was even withdrawn), so none is a turnkey resource; they're best used to calibrate/validate JabLab's own fixture-based replay tests. MediaPipe Pose Landmarker (Apache 2.0, Google-maintained, genuinely production-grade and on-device) is the clear, low-risk pose backbone choice — no boxing-tuned alternative was found to be more mature. On speed estimation, motion-blur literature (mostly from baseball-pitch pose research, not boxing-specific) confirms that fast-action keypoint accuracy degrades exactly during peak velocity at ~30fps, which is genuine — if indirect — supporting evidence for JabLab's D2 gate requiring speed to be derived from phase durations rather than pixel deltas. Competitively, the shadow-boxing app space splits into hardware-dependent trackers (FightCamp, PunchLab, Boxx's optional Punch Pods) and audio-led scripted follow-along apps (Shadow Boxing Workout, generic 'boxing fitness' apps) — no competitor found does real-time, camera-only, on-device punch-type CV coaching without hardware, which is a genuine white-space for JabLab as scoped, though this is based on review-blog summaries rather than hands-on teardown. Curriculum research confirms a very standard, well-documented beginner progression (stance → 1 → 1-2 → 1-1-2 → 1-2-3) and a consistent, independently-repeated coach error taxonomy (dropped guard hand, telegraphing, elbow flare, stance/weight errors) usable directly as the seed rule-set for JabLab's technique-judgment state machine.

## RECOMMENDATIONS
- Use MediaPipe Pose Landmarker (Apache 2.0, on-device, cross-platform) as the pose backbone; it is production-grade and free for commercial use — no evidence a boxing-specific alternative is more mature.
- Do NOT estimate punch/hand speed from frame-to-frame pixel/landmark displacement at 30-60fps — motion blur research (baseball pitch pose work, general fast-action pose literature) confirms partial-body motion blur degrades keypoint accuracy precisely during the fastest phase of a strike, which is exactly when speed matters most. Deriving speed from phase durations (time between deterministic state-machine transitions: guard->extension->impact->retraction) sidesteps this failure mode and is consistent with how the academic detect-then-classify pipelines (transformer/3D-CNN work) separate event timing from per-frame classification. This is genuine supporting evidence for the D2 gate, though no paper explicitly validates 'phase-duration-based speed for boxing' — the support is inferential from the motion-blur literature, not a direct citation.
- For punch typing, use a 6-class taxonomy (jab, cross, lead hook, rear hook, lead uppercut, rear uppercut) — this is the taxonomy BoxingVI and the hierarchical-pipeline paper both converge on, and matches classic coach numbering (1-6) found in beginner curricula.
- Treat BoxMAC as unusable/unverified pending direct confirmation — the arXiv submission was reportedly withdrawn.
- Build JabLab's own small labeled fixture set (recorded landmark sequences with known ground truth) rather than depending heavily on any single external dataset — all identified boxing pose datasets are small, academic, and of uncertain license/maturity; this matches the replay/fixture testing approach already specified in the architecture.
- Competitively, JabLab's phone-camera-only, no-hardware, real CV (not scripted follow-along) positioning is differentiated: FightCamp and PunchLab both lean on physical hardware (trackers/bag straps) for their real metrics, Boxx is admittedly 'a cardio app with a boxing theme' with hardware-optional Punch Pods, and general 'Shadow Boxing Workout' apps are largely audio-led follow-along without real punch-type CV. No competitor found in this pass does phone-camera-only, on-device, real-time punch-type CV coaching without hardware.
- Base the original rule-set on the canonical numbered-punch curriculum (1=jab, 2=cross, 3=lead hook, 4=rear hook, 5=lead uppercut, 6=rear uppercut) plus the widely-repeated coach error taxonomy: dropping the guard hand on extension/retraction, telegraphing (pulling the hand back before throwing), elbow flaring, and stance/weight-distribution errors — these appear consistently across multiple independent coaching sources.

## RISKS
- The academic 'detect-then-classify' punch-recognition pipelines cited (transformer+3D-CNN) are too heavy for real-time on-device mobile inference as published; JabLab must design a much lighter deterministic approximation, and no evidence was found that the accuracy of a lightweight rule-based approach matches these heavy models — this is a real technical risk, not just an engineering translation task.
- No boxing-specific, production-grade, open-source, on-device pose+punch-classification reference app was found (as of this search) — JabLab would be closer to the research frontier than to adapting an existing proven mobile implementation, unlike more saturated categories (e.g. general rep-counting fitness apps).
- Dataset license status is unverified for every boxing-specific dataset found (BoxingVI, BoxMAC, serp-ai repo, MPOSE2021 boxing subset) — do not assume commercial-use rights without checking each repo/paper's license directly before any training/fine-tuning use.
- The 'phase-duration not pixel-delta' speed gate has indirect (motion-blur-literature) support but no paper was found that directly validates this exact design choice for boxing punch speed at 30-60fps — flag this to the team as inferred-supported, not proven-in-literature.
- Competitor landscape research is a single pass of web search summaries (not hands-on app teardown) — pricing and feature claims (e.g., PunchLab $18/mo mention, Boxx £39.99/year) come from third-party review blogs, not verified directly against the App Store/Play Store listings or the vendors' own pricing pages, and should be re-verified before using in JabLab's competitive positioning deck.

## ITEMS (name | license | on_device | url)
### BoxingVI (multi-modal boxing action recognition benchmark)
- what: 6,915 finely segmented, labeled punch clips (Cross, Jab, Lead Hook, Lead Uppercut, Rear Hook, Rear Uppercut) from 20 YouTube videos, with frame-wise 2D human pose estimation (via AlphaPose) for the primary boxer plus raw RGB + temporal segmentation.
- why: Directly gives JabLab a 6-class punch taxonomy + pose-labeled clips usable to validate/fine-tune a rule engine or lightweight classifier against real footage instead of hand-tuning blind.
- license: Not explicitly stated in search snippet — check arXiv paper / repo for license before use.
- maturity: Published Nov 2025 (arXiv), single benchmark paper, not a maintained repo with releases.
- on_device: Not a runtime model — it's a labeled dataset; useful offline for tuning/testing thresholds and for building fixture-based replay tests, not shipped on-device.
- integration: Offline pipeline: use as ground-truth to calibrate JabLab's deterministic pose-angle/velocity thresholds and to build the replay/fixture test suite (recorded landmark sequences -> expected labels).
- caveats: Small (20 source videos) — good for qualitative calibration/testing, not for training a heavy model from scratch. License/access terms unverified.
- url: https://arxiv.org/html/2511.16524
### BoxMAC — A Boxing Dataset for Multi-label Action Classification
- what: 60,000+ annotated frames / 2,314 clips from 15 professional boxers, 13 action labels, multi-label (both boxers' actions per frame) annotated with an expert coach.
- why: Larger-scale labeled corpus for punch/action recognition than BoxingVI; multi-label framing models real sparring/bag footage where partner + guard states co-occur — useful for JabLab's shadow-boxing single-person case as a source of technique-error e
- license: Unclear — the arXiv submission itself was reportedly withdrawn (co-author disagreement, needs revision), so treat cautiously and verify current status/license before relying on it.
- maturity: Withdrawn arXiv preprint (Dec 2024) — flagged as needing significant revision; not a stable, citable release.
- on_device: Dataset only, not a model; not directly deployable on-device.
- integration: If accessible, offline calibration/fixture source only.
- caveats: CONFIRMED uncertain status — paper was withdrawn per search result. Do not cite as validated research; verify directly before using any numbers from it.
- url: https://arxiv.org/abs/2412.18204
### Fine-Grained Punch Recognition Pipeline (Dual-Stream Spatio-Temporal Transformer + 3D CNN)
- what: A hierarchical pipeline: a transformer detects punch events, then a 3D CNN classifies into 6 punch types (jab, cross, lead/rear hook, lead/rear uppercut), built on AlphaPose keypoints.
- why: Shows state-of-the-art academic approach uses two-stage detect-then-classify architecture on pose keypoints (not raw pixel deltas) — supports JabLab's design of separating phase/event detection from classification, and reinforces that punch typing fr
- license: Academic paper — no code license implied; would need reimplementation.
- maturity: Peer-reviewed workshop/conference chapter (2025), research-grade, not shipped as open-source production code per search snippet.
- on_device: Transformer + 3D CNN stack is heavy for real-time mobile; the architecture is a design reference, not something to embed directly — JabLab's deterministic state machine should be a lighter-weight proxy for the same detect-then-classify idea.
- integration: Architectural inspiration for a two-stage (phase-detector then classifier) design; not a drop-in library.
- caveats: Did not verify reported accuracy numbers via full text (search snippet only) — treat any specific accuracy claim as unverified until the source PDF is read directly.
- url: https://link.springer.com/chapter/10.1007/978-3-031-93688-3_19
### MPOSE2021_Dataset (includes boxing action clips)
- what: Open dataset for short-time pose-based Human Action Recognition; includes a boxing.zip subset processed with OpenPose v1.6.0 and PoseNet keypoints.
- why: Ready-made pose-sequence (not raw video) boxing samples — lower friction for quick fixture/testing use than raw-video datasets requiring your own pose extraction.
- license: Check repo (typically research-use datasets on GitHub carry their own LICENSE file — verify commercial-use terms before use).
- maturity: Established academic HAR benchmark repo, moderately maintained, widely cited in pose-HAR literature.
- on_device: Pose-sequence data only; not itself a runtime component.
- integration: Offline: seed fixture/replay tests with pre-extracted keypoint sequences for boxing-adjacent actions.
- caveats: "Boxing" subset here is likely general action-recognition style (KTH/UT-interaction-like), not fine-grained punch-type-labeled — check before assuming jab/cross/hook granularity.
- url: https://github.com/PIC4SeR/MPOSE2021_Dataset
### serp-ai/boxing-punch-recognition-dataset
- what: Community open-source project explicitly aiming to build 'the first truly open, comprehensive boxing dataset' starting with punch recognition/classification.
- why: Direct, permissively-framed open dataset effort targeting exactly JabLab's need (punch type classification) rather than a byproduct of a research paper.
- license: Check repo LICENSE file directly — not confirmed via search.
- maturity: Community project; maturity/activity level (stars, last commit, dataset size) not confirmed by search — verify directly before relying on it.
- on_device: Dataset, not runtime.
- integration: Offline dataset/fixture source if maturity checks out.
- caveats: Unverified scope and completeness — search snippet only; must inspect repo directly before committing engineering time.
- url: https://github.com/serp-ai/boxing-punch-recognition-dataset
### MediaPipe Pose (Pose Landmarker)
- what: Google's open-source, Apache 2.0, on-device ML framework giving up to 33 3D body landmarks from RGB video in real time on Android/iOS/embedded.
- why: This is the most likely concrete on-device pose backbone for JabLab (single phone camera, on-device only, cross-platform, free for commercial use) — landmark coordinates/angles feed the deterministic rule engine/state machine per JabLab's binding arc
- license: Apache 2.0 — explicitly free for commercial use.
- maturity: Production-grade, widely deployed (Google-maintained), large ecosystem, actively updated as of 2025-2026.
- on_device: Excellent — purpose-built for real-time on-device mobile inference; this is the standard building block for exactly this class of app (multiple fitness-rep-counting apps cited use it, e.g. RepDetect on Android via MLKit).
- integration: Native bridge: MediaPipe Tasks Pose Landmarker via Kotlin/Swift camera pipeline, landmarks passed to Flutter via platform channel for the deterministic rule engine/state machine layer described in JabLab's architecture.
- caveats: Search did not surface a boxing-specific MediaPipe reference app in wide production use — boxing-specific real-time feedback apps appear to still be research/hobby-project stage, meaning JabLab would be building the punch-classification layer itself on top of MediaPipe's generic landmarks, not reusi
- url: https://blog.roboflow.com/what-is-mediapipe/


# ==== ostinato-domain ====

## SUMMARY
Across audio, competitors, CV, and data, the clearest theme is that permissive-vs-copyleft licensing is the single biggest practical constraint for Ostinato's solo-founder, closed-source mobile build — the most 'famous' open-source audio libraries (aubio, TarsosDSP, Essentia) are GPL/AGPL, while a strong MIT alternative exists on iOS (AudioKit) and a very new, promising, small neural model (SwiftF0, Aug 2025 preprint) looks like the best long-term bet for cross-platform real-time pitch tracking pending license confirmation and cello-specific validation. SoundTouch (LGPL) is a safer choice for tempo/metronome alignment. On the competitive-landscape side, the incumbents (Yousician, Simply family, Trala, Tonara, Modacity, SmartMusic, MuseScore) collectively confirm that string-instrument coverage today is either shallow (Yousician's violin lessons, tuner-only for cello) or audio-only with no camera/posture layer (Trala explicitly cannot give nuanced bowing/posture feedback per its own reviewers) — this is genuine, evidenced whitespace for Ostinato's camera+audio combination, though it should be reconfirmed with a live store audit before external claims. For bow/instrument detection, MediaPipe's Object Detector + Model Maker is the best-supported, Apache-2.0, officially mobile-deployable path, while the AGPL-default Ultralytics YOLO family and Apache-2.0 RT-DETR/D-FINE are the main alternatives with their own license and mobile-maturity tradeoffs respectively; a specific, directly relevant academic precedent exists in erhu bowing-detection research (2020 HCI paper, 2025 MDPI Sensors follow-up) that validates the general feasibility of YOLO-style bow+hand tracking for bowed-string technique feedback, though not on cello specifically and not proven on-device. On data, URMP is the one existing multi-modal (audio+video) string-instrument dataset with cello coverage and note-level ground truth, but its commercial-use license status is unconfirmed and must be clarified with the maintainers before any production use.

## RECOMMENDATIONS
- Audio pipeline: avoid GPL/AGPL libraries (aubio, TarsosDSP, Essentia) for a closed-source commercial app unless you get an explicit commercial relicense in writing; default recommendation is a permissively-licensed hybrid — AudioKit (MIT) for iOS-native pitch tracking, plus either your own from-scratch pYIN/YIN implementation in Kotlin for Android, or a shared Apache/MIT-licensed C++ DSP core (build one in-house or evaluate newer permissive libs) compiled via NDK for both platforms to keep iOS/Android behavior consistent.
- Pilot SwiftF0 (arxiv 2508.18440, github.com/lars76/swift-f0) early as the most promising 2025 neural pitch tracker for real-time mobile, but first confirm its license file and run your own cello-frequency-range accuracy test before betting the architecture on it — it is very new and unproven at production mobile scale.
- For onset/tempo, pair a permissively-licensed pitch engine with SoundTouch (LGPL-2.1, commercially safe via dynamic linking) for tempo/metronome alignment rather than aubio's onset detector, to avoid mixing GPL code into the audio pipeline.
- Competitive positioning: no existing music-practice competitor combines audio pitch/rhythm assessment with camera-based bowing/posture analysis for any bowed string instrument — Trala (violin, audio-only, explicitly no bowing/posture feedback per reviews) and the erhu-bowing YOLO research are the two closest reference points on either side (product vs. academic CV) of the gap Ostinato is positioned to fill. This differentiation claim should be the core of Ostinato's positioning, and it is supported by the evidence gathered, not merely aspirational.
- For instrument/bow detection, treat this as the highest-uncertainty technical thread: start with MediaPipe Object Detector + Model Maker (Apache-2.0, official mobile support, easiest legal path) using a custom-collected cello+bow dataset, but budget for the likely need to track bow-tip and bow-frog as two keypoints (a pose/keypoint approach) rather than a single bounding box, since thin elongated objects are a known weak point for standard detectors — this mirrors the erhu-research approach of tracking bow + hand as related objects.
- If YOLO-family tooling proves meaningfully better in practice, price out Ultralytics' Enterprise license explicitly (confirm current terms at ultralytics.com) versus using Apache-2.0 RT-DETR/D-FINE/RF-DETR with more DIY mobile-export effort — do not default to AGPL YOLO without a licensing decision made explicitly by the founder.
- For data, request explicit commercial-use clarification from the URMP dataset maintainers (bochen.li@rochester.edu) before using it for anything beyond internal research/prototyping; in parallel, plan to collect Ostinato's own labeled cello+bow video dataset early, since no existing open dataset was found that is both (a) confirmed commercially licensable and (b) camera-angle/framing-matched to a phone-based practice-coach use case.

## RISKS
- Licensing risk is the dominant risk across both audio (GPL/AGPL: aubio, TarsosDSP, Essentia) and CV (AGPL: default Ultralytics YOLO) threads — a naive 'just use the most popular open-source library' choice would put Ostinato in the same copyleft-license bind as many indie audio apps before them; this needs an explicit founder/legal decision before writing production code.
- Cello-specific validation gap: nearly all pitch-tracking benchmarks found (CREPE, SwiftF0, pYIN comparisons) are evaluated primarily on speech/voice or generic-instrument datasets, not specifically on cello's wider dynamic range, lower fundamental frequencies, and vibrato-heavy technique — real accuracy on cello audio is unverified from search alone and needs hands-on benchmarking.
- Bow-tracking feasibility is genuinely unproven at the fidelity Ostinato likely needs — the closest academic precedent (erhu bowing YOLO research) is on a different (though related) instrument, was not shown to run on-device/real-time on a phone, and its code/dataset availability could not be confirmed as public — this is a build-it-and-see risk, not a solved problem.
- URMP and most academic string-performance datasets are gated behind access-request forms with unclear/likely non-commercial default licensing — relying on them without written commercial-use permission is a legal risk if any model trained on that data ships in a paid commercial app.
- Market risk is comparatively low but not zero: while no direct camera+audio bowed-string competitor was found, the search depth here relied on WebSearch summaries rather than exhaustive App Store/Play Store audits — a live store search (not done in this research pass) is recommended before finalizing the 'no one does this' claim publicly.

## ITEMS (name | license | on_device | url)
### aubio
- what: C library for audio labelling: pitch tracking (multiple algos incl. YIN/YINFFT), onset detection, tempo/beat tracking, note onset/offset segmentation.
- why: Covers audio thread (1): pitch+onset+tempo in one small C lib, causal/low-latency algorithms usable in real-time practice-coach loop for cello note/rhythm tracking.
- license: GPL-3.0 (copyleft) — GitHub repo confirms GPLv3
- maturity: Long-lived project (since ~2003), stable but slow-moving; C core, Python bindings; used inside TarsosDSP's YIN reference implementation.
- on_device: Yes — written for real-time/low-delay causal use, runs on ARM; needs a Flutter/Kotlin/Swift FFI bridge (C core, no official Dart/Flutter package).
- integration: Native bridge: compile aubio C sources into Android NDK (Kotlin JNI) and iOS (Swift/ObjC) targets, expose pitch/onset/tempo via platform channel to Flutter UI.
- caveats: GPLv3 is copyleft — for a closed-source commercial app this typically requires either (a) isolating aubio behind a process/IPC boundary reviewed by counsel, (b) a commercial relicense (not publicly advertised by aubio maintainers — would need direct contact), or (c) avoiding aubio and using LGPL/MIT
- url: https://aubio.org/
### TarsosDSP
- what: Java/Android real-time audio processing library: YIN & MPM pitch detectors, onset detection, tempo estimation, time-stretching.
- why: Native Android-side pitch/onset engine; author explicitly ported/validated against aubio's YIN implementation, giving a second implementation choice for the mobile bridge.
- license: GPL-3.0 (per TarsosDSP readme, referencing aubio GPL heritage) — same copyleft caveat as aubio.
- maturity: Actively documented, Android-compatible since v2.0, used in published academic tools (Tarsos pitch-tracking research project).
- on_device: Yes, designed for real-time Android use with low CPU footprint.
- integration: Android native module (Kotlin/Java) → Flutter platform channel; iOS would need separate Swift-native pitch engine since TarsosDSP is JVM-only.
- caveats: GPL license — same commercial-use concern as aubio; also JVM-only so does not solve iOS side, meaning Ostinato would need two separate native pitch engines (or a shared Rust/C++ core) unless a permissively-licensed cross-platform library is chosen instead.
- url: https://github.com/JorenSix/TarsosDSP
### CREPE / TinyCREPE (Convolutional Representation for Pitch Estimation)
- what: CNN-based monophonic pitch tracker trained on raw waveform; 'tiny' variant is a smaller model intended for lower-resource inference.
- why: State-of-the-art (2018-era) accuracy baseline for tuner-grade pitch tracking that mobile-oriented models (SwiftF0) now benchmark against; TinyCREPE / TFLite ports are a path to on-device neural pitch tracking for cello (which has more inharmonicity/v
- license: MIT (marl/crepe repo)
- maturity: Widely cited (ICASSP 2018), many community TFLite/CoreML ports exist but are third-party, uneven maintenance.
- on_device: Full CREPE model is too heavy for smooth real-time mobile inference; TinyCREPE is more viable but still CPU-heavier than classic DSP pitch trackers or SwiftF0 — needs on-device benchmarking (TFLite/CoreML conversion) before committing.
- integration: Convert to TFLite (Android) / Core ML (iOS) once, run via native ML runtime, feed frequency stream to Flutter via platform channel.
- caveats: No first-party official mobile export exists; conversion is DIY and accuracy-vs-latency must be validated for cello's lower fundamental range (cello C2≈65Hz down to C string) which CREPE's original training range may or may not cover well — verify frequency range coverage before choosing over pYIN.
- url: https://github.com/marl/crepe
### SwiftF0
- what: 2025 lightweight CNN (STFT front-end + small 2D-CNN, ~95.8K parameters) for fast monophonic F0/pitch estimation, explicitly optimized for real-time/resource-constrained deployment.
- why: Directly answers 'tuner-app-grade pitch tracking state of the art' — claims ~42x faster than CREPE on CPU and beats CREPE accuracy by >12pp at 10dB SNR, i.e. a strong 2025/2026 candidate for real-time on-device cello pitch tracking.
- license: Check the GitHub repo (lars76/swift-f0) directly for the LICENSE file before use — not confirmed from search snippets; likely permissive given research-code norms but MUST be verified.
- maturity: Very new (Aug 2025 preprint), single-author research repo, no known production mobile deployments yet — early-stage, unproven at scale.
- on_device: Explicitly designed for CPU real-time use; small parameter count (~96K) suggests strong TFLite/CoreML conversion viability, but no official mobile export/benchmark published yet.
- integration: Would require converting the PyTorch/TF model to TFLite and Core ML yourself and building the native inference + platform-channel bridge — DIY integration risk given its newness.
- caveats: Confirm license explicitly (github.com/lars76/swift-f0) before adopting; being a brand-new single-author repo, do not treat published benchmarks as independently verified — pilot-test cello audio specifically since benchmarks are likely voice/generic-instrument focused.
- url: https://arxiv.org/abs/2508.18440
### AudioKit / AudioKitEX (AKFrequencyTracker)
- what: iOS/macOS audio synthesis & DSP framework in Swift with a built-in real-time frequency/pitch tracker node (AKFrequencyTracker), used by several published tuner apps.
- why: Gives Ostinato an iOS-native, permissively licensed, production-proven pitch-tracking building block (used in App-Store tuner apps like 'Pitch'), reducing iOS-side build risk versus GPL C libraries.
- license: MIT
- maturity: Mature, long-running open-source project, Apple-featured app built on it ('Pitch' tuner), active GitHub org with AudioKitEX as the DSP-core companion repo.
- on_device: Yes — purpose-built for real-time on-device iOS audio analysis; proven in shipped tuner apps.
- integration: Swift native module on iOS, bridged to Flutter via platform channel/method channel; still need a separate Android-side pitch engine (AudioKit is Apple-platform-only).
- caveats: iOS-only — solves half the cross-platform problem; Android side still needs its own engine (e.g. a from-scratch Kotlin YIN/pYIN implementation to avoid GPL, or a permissively licensed C++ core shared via CMake/NDK across both platforms for consistency).
- url: https://github.com/AudioKit/AudioKit
### pYIN / SoundTouch (for tempo/time-stretch, not pitch)
- what: pYIN = probabilistic YIN pitch algorithm (Vamp plugin, from the Sonic Annotator ecosystem) with typically MIT/permissive licensing on many reimplementations; SoundTouch = classic open-source audio time-stretch/pitch-shift library used for tempo alignment / metronome features.
- why: pYIN is the classical non-neural accuracy benchmark CREPE/SwiftF0 compare against; SoundTouch is the standard component for tempo detection/adjustment and click-track alignment used broadly in DAWs and mobile apps (e.g., bilibili/ijkplayer Android po
- license: SoundTouch: LGPL-2.1 (commercially usable via dynamic linking without releasing your own app source, per FOSSA/LGPL guidance) — much safer for Ostinato than GPL aubio/TarsosDSP.
- maturity: SoundTouch is long-established (used in many commercial audio/video products, e.g. VLC-adjacent ecosystems, Android ports exist e.g. bilibili/soundtouch fork).
- on_device: Yes, C++ core with existing Android build forks; iOS integration is straightforward via CocoaPods/manual build.
- integration: Native C++ module shared across iOS/Android via CMake, for tempo/BPM alignment and metronome click-track features; combine with a separate pitch engine for full audio pipeline.
- caveats: SoundTouch is about tempo/time-stretch, not pitch detection or onset detection — must be paired with a pitch/onset library; LGPL still requires you to allow relinking of the LGPL component (e.g. dynamic linking) to stay compliant — consult counsel for exact mobile build implications.
- url: https://codeberg.org/soundtouch/soundtouch.git
### Essentia
- what: C++ open-source library for audio analysis / music information retrieval (pitch, onset, rhythm, MIR features), with iOS/Android/Web build targets and real-time-capable algorithms.
- why: Broadest MIR toolkit mentioned in the brief (pitch+onset+tempo+more) with existing mobile build targets, potentially reducing the number of separate libraries needed.
- license: AGPL-3.0 (or commercial dual-license available from the Essentia/UPF team for a fee — historically MTG-UPF has sold commercial licenses)
- maturity: Long-running academic project (UPF Music Technology Group), well documented, cross-platform builds confirmed (Linux/macOS/Windows/iOS/Android/Web).
- on_device: Yes, explicitly built with computational-speed/real-time optimization and cross-mobile build support.
- integration: C++ core via NDK (Android) and manual/CocoaPods (iOS) build, single shared codebase reduces platform divergence versus AudioKit(iOS)+TarsosDSP(Android) split.
- caveats: AGPL-3.0 is even stricter than GPL for a closed commercial mobile app (network-use clause too) — using it in Ostinato without buying UPF's commercial license would almost certainly require legal review; budget for a paid license inquiry to MTG-UPF if this route is chosen.
- url: https://essentia.upf.edu/
### Yousician
- what: Multi-instrument gamified practice app (guitar/bass/ukulele/piano/voice as core; violin lessons added but 'not as in-depth', tuner sub-tool GuitarTuna covers violin/viola/cello) using real-time audio pitch/rhythm listening — no camera/posture assessment.
- why: Direct competitor precedent showing incumbent strings coverage is shallow (violin only, cello effectively absent as a core instrument) and purely audio-based — confirms the camera+audio combined-coaching gap for Ostinato.
- license: N/A (commercial SaaS, not open-source)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Pricing and exact current cello support not independently confirmed beyond violin-lesson mentions and GuitarTuna's tuner covering cello — verify current in-app instrument list directly in-store before quoting to stakeholders.
- url: https://yousician.com/company
### Simply Piano / Simply Guitar (JoyTunes 'Simply' family) + 'Simply Tuner'
- what: JoyTunes' flagship apps are piano and guitar; search surfaced a separate 'Simply Tuner - Violin, Cello' App Store listing, suggesting JoyTunes/adjacent developers cover string tuning but not full audio-assessed string-instrument lesson coaching under the core Simply brand.
- why: Confirms the 'Simply' family's core practice-assessment product does NOT extend real-time performance coaching to violin/cello — only a basic tuner utility exists for strings, reinforcing the competitive gap for Ostinato.
- license: N/A (commercial App Store apps)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Could not confirm from search whether 'Simply Tuner' is officially a JoyTunes product or a separate developer trading on similar branding — verify publisher identity on the App Store listing before citing this as a JoyTunes fact.
- url: https://apps.apple.com/de/app/app/id1300058854
### Trala (Learn Violin)
- what: Violin-only app with AI-driven real-time pitch/rhythm listening, lesson curriculum, and marketed 'posture' feedback trend, but confirmed by review sources to NOT replicate nuanced bowing/posture feedback (audio-only assessment, no camera analysis) — acquired by Learnfield GmbH (maker of Skoove piano app).
- why: The single closest existing competitor to Ostinato's instrument category (bowed string, real-time listening coach) — its explicit lack of camera-based bowing/posture feedback is the clearest evidence of Ostinato's differentiation opportunity.
- license: N/A (commercial app)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Pricing figures ($9.99/mo, $119.99/yr) came from a third-party review aggregator, not Trala's own site/App Store listing — re-verify current pricing directly before using in any external-facing material; also violin-only, no cello, no Android confirmed in search results (verify Android availability 
- url: https://apps.apple.com/us/app/trala-learn-violin/id1143205265
### Tonara
- what: AI-powered classroom/practice tracking app with metronome-led tracks, gamified XP/badges, and score-following (historically known for real-time sheet-music page-turning via audio listening) — audio-based, teacher/classroom oriented, no camera/posture assessment found.
- why: Represents the 'practice tracking + audio score-following' competitor category adjacent to but distinct from Ostinato's per-note technique coaching; shows no camera-based analysis in this space either.
- license: N/A (commercial SaaS)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Primary source is a 2013 TechCrunch article plus a 2026 aggregator blurb — current (2026) feature set not independently verified via Tonara's own site; treat feature claims as indicative, not current-state confirmed.
- url: https://techcrunch.com/2013/11/23/tonara-score-sync/amp/
### Modacity
- what: 'Deliberate Practice System' — practice planning, session recording (audio/video self-recording for reflection), and progress tracking across any instrument; not an automated pitch/rhythm grading engine, more a structured practice-log + recorder tool.
- why: Shows a different competitor model: practice management/reflection rather than real-time automated assessment — Ostinato's automated rule-engine coaching is differentiated from this manual-reflection category too.
- license: N/A (commercial, iOS + Android per Play Store listing found)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Pricing ($12.99/mo or $129/yr per one review source) not cross-verified against Modacity's own site; confirm before quoting.
- url: https://apps.apple.com/us/app/modacity-pro-music-practice/id1351617981
### SmartMusic
- what: School/institutional practice-assessment platform with microphone-based note/rhythm accuracy scoring (green/red note feedback) and accompaniment tracks; broad instrument coverage including strings, geared to school music education market rather than consumer solo learners.
- why: Established precedent that real-time audio-only note-accuracy scoring for strings (including presumably cello) is a solved, shipped feature in the institutional-education segment — useful reference for what 'good enough' audio assessment looks like, 
- license: N/A (commercial, institutional licensing model, owned by MakeMusic/Peaksware)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Cited review source is from 2014 — SmartMusic has likely evolved significantly since; re-verify current feature set and whether it now includes any camera-based feedback via MakeMusic's own current site before relying on this as current-state.
- url: https://tonaldiversions.com/2014/08/19/review-smartmusic
### MuseScore (practice-adjacent tooling)
- what: Free/open-source notation software with MIDI playback; explicitly noted in search results to lack built-in student management, progress tracking, or automated performance assessment — it's a notation tool, not a practice coach.
- why: Rules out MuseScore as a direct competitor for real-time coaching; relevant mainly as a possible sheet-music/notation interoperability reference (MusicXML) if Ostinato ever needs to import score data.
- license: GPL-3.0 for MuseScore's own codebase (not relevant to Ostinato unless importing/exporting MusicXML, which is an open standard, not GPL-encumbered)
- maturity: ?
- on_device: ?
- integration: ?
- caveats: Not a real 'competitor' for real-time coaching — included per task instructions but low relevance; do not over-weight in competitive analysis.
- url: https://tonaldiversions.com/2014/08/19/review-smartmusic
### YOLO family (YOLOv8/v10/v11/v12, Ultralytics)
- what: Widely used real-time single-stage object detectors; recent Ultralytics releases (YOLO11/YOLOv12) are dual-licensed AGPL-3.0 / paid Enterprise license.
- why: The most mature, best-tooled mobile-object-detection family (huge community, existing mobile export paths to TFLite/CoreML/ONNX) — but its AGPL default licensing is the key commercial-viability question for detecting cello+bow on-device.
- license: AGPL-3.0 by default for Ultralytics YOLO releases; commercial/Enterprise license required to ship closed-source (per search summary — verify exact current terms and pricing directly on ultralytics.com
- maturity: Extremely mature ecosystem, best mobile tooling/export support of any detector family (TFLite/CoreML/ONNX/NCNN exporters maintained), huge community and pretrained-model zoo.
- on_device: Excellent — YOLOv8/v10-nano and similar variants are explicitly designed for real-time mobile/edge inference and are used in production mobile apps broadly.
- integration: Train/fine-tune a nano-sized custom model on cello+bow images, export to TFLite (Android) and Core ML (iOS), run via native ML runtime (e.g. Ultralytics' own mobile SDKs or TFLite/CoreML directly), bridge to Flutter.
- caveats: Confirm current Ultralytics licensing/pricing directly — AGPL is commercial-use-disqualifying for a closed-source app unless the Enterprise license is purchased; for an indie/solo budget this is a real cost to price out, or choose an Apache-2.0 alternative (RT-DETR/D-FINE/RF-DETR) instead.
- url: https://www.ultralytics.com/blog/the-best-object-detection-models-of-2025
### RT-DETR / RT-DETRv2 and D-FINE
- what: Transformer-based real-time object detectors (DETR lineage) that avoid YOLO's NMS post-processing step; D-FINE is described as currently leading this family via an optimized decoder training strategy.
- why: Apache-2.0-licensed alternative to YOLO for cello/bow detection — directly solves the commercial-license concern the brief raised, at some cost in mobile tooling maturity versus YOLO.
- license: Apache 2.0 (per search summary: 'All DETR architectures are released under the permissive Apache 2.0 License') — verify per specific repo (RT-DETR is Baidu/PaddlePaddle-origin, D-FINE is a separate re
- maturity: RT-DETR is a published, reasonably adopted model (2023-2024); D-FINE is newer (2024-2025) and positioned as SOTA within this real-time-DETR family per the source blog.
- on_device: Real-time-oriented by design, but DETR-family models are generally heavier/less mobile-optimized than YOLO-nano variants historically — mobile export tooling (TFLite/CoreML) is less mature/community-tested than for YOLO; must be validated with an act
- integration: Export to ONNX then to TFLite/CoreML; expect more manual conversion work than YOLO given less mobile-first tooling.
- caveats: Mobile-deployment maturity is the biggest open question — the search results describe these mainly in server/GPU benchmark contexts; no direct evidence found of production on-device mobile deployment of RT-DETR/D-FINE at Ostinato's target frame rate. Needs a hands-on feasibility spike before committ
- url: https://blog.roboflow.com/best-object-detection-models/
### MediaPipe Object Detector + Model Maker (custom-trained)
- what: Google's on-device vision pipeline with an official Object Detector task and Model Maker workflow for retraining a pre-built detector on custom object classes (e.g., 'cello', 'bow') via transfer learning, exporting to TFLite for on-device Android/iOS/Web inference.
- why: Most officially-supported, Google-maintained path to a lightweight custom on-device detector, with first-party mobile deployment support (the exact 'thin line-like object tracking' use case would need bow-specific data since bows are thin/low-texture
- license: Apache 2.0 (MediaPipe/Google AI Edge framework)
- maturity: Actively maintained by Google (Google AI Edge team), first-party mobile support (Android/iOS/Web), transfer-learning workflow explicitly documented and lowers required training-data volume — best-supp
- on_device: Best-in-class — purpose-built for on-device mobile deployment with quantization support (32-bit→16-bit float, or full-int8) documented.
- integration: Collect/label a small custom dataset of cello+bow frames, retrain via MediaPipe Model Maker (Colab/Python), export TFLite model, run through MediaPipe Tasks Object Detector API natively on Android/iOS, bridge results into Flutter.
- caveats: Thin, low-texture, fast-moving objects like a bow are historically a hard case for bounding-box detectors (motion blur, low bounding-box IoU value for thin elongated objects) — the erhu-bow-YOLO research (see below) is the closest existing proof this is feasible, but expect to need line/keypoint-sty
- url: https://developers.google.com/edge/mediapipe/solutions/customization/object_detector
### Bowing Detection for Erhu Learners Using YOLO Deep Learning Techniques (Lu et al., HCI Int'l 2020) + follow-up 'A Posture Training System Based on Therblig Analysis and YOLO Model' (Sensors 2025)
- what: Academic CV research directly analogous to Ostinato's bow-tracking need: uses YOLO object detection to track a bowed-string instrument's bow + the player's bowing hand in video, evaluating bow-stroke levelness/straightness; the 2025 Sensors follow-up builds a full computerized erhu-bowing posture-training system from this YOLO-OD approach.
- why: This is the single most directly transferable piece of academic prior art for Ostinato's core CV problem (bow-tracking for technique feedback) — it proves bow+hand YOLO detection is feasible for real-time-ish bowed-string posture/technique training, 
- license: N/A — academic paper (open access on MDPI Sensors, CC-BY typically for MDPI journals — verify exact reuse terms on the article page); not software to integrate, but a methodology/feasibility reference
- maturity: Published, peer-reviewed (MDPI Sensors 2025 is the most current entry in this line of research; original erhu-YOLO work dates to a 2020 HCI International conference paper), indicates an active, still-
- on_device: Not directly on-device mobile — described as a training-system prototype (likely PC/workstation-based in the papers); provides methodology (bow+hand as separate detected objects, straightness/level scoring) that Ostinato would need to re-implement an
- integration: Use as methodology reference: replicate the 'detect bow + detect bowing-hand as separate objects, derive trajectory/angle metrics' approach with your own MediaPipe/YOLO-nano custom model and rule-engine layer, rather than reusing any code (none indic
- caveats: Erhu is bowed similarly to but not identical to cello (different hold, different bow-string geometry, erhu is played vertically resting on the leg vs. cello between the knees) — treat as strong methodological precedent, not a plug-and-play solution; also could not confirm from search whether code/da
- url: https://www.mdpi.com/1424-8220/25/3/674
### URMP (University of Rochester Multi-modal Music Performance) Dataset
- what: 44 classical chamber pieces, 115 single-source tracks across 13 monophonic instruments (including violin and cello), providing synchronized audio + video + musical score + frame/note-level ground-truth transcription per instrument track.
- why: Directly answers thread (4) — one of very few existing multi-modal (audio+video) string-instrument performance datasets with cello coverage and note-level ground truth, useful for pretraining/validating audio pitch models and potentially bootstrappin
- license: Access requires filling out a Google form request to the Rochester AIR lab (contact bochen.li@rochester.edu per search result) — exact reuse/commercial-license terms NOT found in search snippets; hist
- maturity: Well-established academic dataset (created ~2016, described in a widely cited paper 'Creating a Multi-track Classical Music Performance Dataset for Multi-modal Music Analysis'), still actively referen
- on_device: N/A — it's a dataset for training/eval, not a runtime component; any model trained on it would need separate mobile export/optimization work.
- integration: Use for offline model pretraining/validation of audio pitch-tracking or (with more effort) bow/posture CV heuristics using its video tracks; NOT a drop-in mobile SDK.
- caveats: MUST explicitly verify the license terms before any commercial (non-academic) use — search results only confirm an access-request form, not commercial redistribution/training rights; treat as academic-research-use-only until Ostinato's team gets written confirmation from the URMP maintainers that co
- url: https://labsites.rochester.edu/air/projects/URMP/URMP_doc.pdf


# ==== choreia-domain ====

## SUMMARY
Research across the four threads found solid directional signal but thin production-ready tooling — consistent with this being a genuine white-space opportunity for Choreia. (1) TECH: DTW-based skeleton sequence comparison is the clear academic and practitioner consensus for dance/motion scoring (multiple 2025 papers, e.g. the QAQA anomaly-aware DTW paper and the JPSS/JASS joint-angle similarity scoring paper), but robustness to body proportions requires normalizing to joint angles or bone-length-scaled skeletons before running DTW — raw-coordinate DTW is explicitly documented as proportion-sensitive. No mobile-ready, well-maintained open-source dance-scoring library was found; the closest repos (motion-tracker, DanceVision, QAQA-main) are research/hobbyist grade and should be used only as algorithmic references for an in-house native (Kotlin/Swift) implementation. (2) BEAT/MUSIC: librosa has no direct mobile equivalent; the real mobile-native options are aubio (C, cross-compilable) and TarsosDSP (pure Java/Android), both GPL-licensed — a real licensing blocker for a closed-source commercial app — plus Essentia (AGPL, even stricter) and BeatNet (state-of-the-art but Python/PyTorch research code, heavy to port). The pragmatic recommended path is a metronome/royalty-free-beat-library V1 with known beat grids, upgrading later to one-time offline BPM analysis (far more tractable than continuous real-time tracking) rather than live beat detection of arbitrary user tracks; Superpowered SDK is a clean-license paid alternative if live detection is required. (3) COMPETITORS: STEEZY is confirmed video-playback-only with a webcam mirror (no feedback, no scoring) at ~$149.99/yr; Everdance differentiates on feedback but delivers it via asynchronous human instructor video review, not real-time AI; Just Dance's 2025-2026 Camera Controller adds real ML-based motion scoring but is a console game with no voice coaching and no personal-app framing; Apple Fitness+/Peloton offer dance content without camera-based form feedback. No competitor combines real-time on-device pose scoring with real-time voice coaching for dance — supporting Choreia's differentiation. (4) LEGAL: Choreography copyright is real but narrow (individual steps and social/line dances are not protectable; original composed sequences can be) per multiple legal sources, meaning named-dance teaching content needs case-by-case caution rather than a blanket yes/no; music licensing sources consistently warn that a user owning music personally does not license an app to process/redistribute it, reinforcing the default-to-own-music-playback-only plus built-in royalty-free/metronome content strategy the task hypothesized.

## RECOMMENDATIONS
- TECH: Do NOT do raw-coordinate DTW. Normalize skeleton first (bone-length/torso-scale normalization, or convert to joint angles per JPSS/JASS-style scoring), then run windowed/banded DTW per key joint-angle time series. This is the single most important correctness step for body-proportion robustness.
- TECH: Build the scoring engine in-house (native Kotlin/Swift) using published formulas (DTW + JPSS/JASS-style angle scoring) rather than depending on any of the found GitHub repos directly — none are mobile-ready, license-clear, or actively maintained enough to embed as a dependency. Use them as algorithmic references only.
- BEAT/MUSIC: Avoid GPL/AGPL native audio libraries (aubio, TarsosDSP, Essentia) for a closed-source commercial app unless you get explicit legal clearance or a commercial license — this is a real ship-blocking risk, not a nitpick.
- BEAT/MUSIC: Prefer the 'offline/batch BPM analysis + cached beat grid' architecture over continuous real-time beat tracking of arbitrary user music. It is both more accurate and sidesteps most of the latency/robustness problems of live tracking — reserve live detection only as a stretch goal.
- BEAT/MUSIC: Ship V1 with a built-in metronome + a small licensed/royalty-free beat-track library where BPM and beat-grid are known ahead of time (zero detection risk, zero licensing risk). This directly matches the task's suggested fallback design and should likely be the actual V1, not just a fallback.
- BEAT/MUSIC: If real on-device detection of the user's own music is required, evaluate Superpowered SDK (paid, clean commercial license, mobile-native) before any GPL/AGPL option — confirm current pricing directly, it wasn't available in this research pass.
- COMPETITORS: The camera+voice-feedback gap is real and confirmed: STEEZY (video-only, webcam mirror but no scoring/feedback), Everdance (differentiates on feedback but via async instructor video review, not real-time camera+voice AI), Just Dance (has ML camera scoring as of 2025-2026 but no voice coaching, and it's a console/TV game not a personal dance-teaching app), Apple Fitness+/Peloton (dance content but no camera-based form feedback in the way Tempo Move or Peloton Guide provide for strength). No competitor found combines real-time on-device pose scoring + real-time voice coaching for dance specifically — this supports Choreia's core differentiation thesis.
- LEGAL: Default Choreia to user's-own-music-as-private-consumption plus a built-in royalty-free/licensed beat library — do not build any feature that streams, redistributes, or publicly plays back a user's copyrighted track through app infrastructure (e.g., server-side processing/mixing) without a sync/mechanical license.
- LEGAL: Named public choreography (e.g., a specific K-pop routine or 'the TikTok dance') carries real copyright risk if you reproduce the exact original choreographer's sequence as licensed teaching content — treat as unclear/case-by-case, avoid explicitly branding lesson content as 'learn [Artist]'s official choreography' without licensing, and prefer teaching generic step vocabulary/technique or original in-house choreography.
- LEGAL: Get a real IP/entertainment lawyer review before any launch decision involving copyrighted commercial music playback or named-choreography content — this research is directional, not a legal opinion.

## RISKS
- Confirmed named open-source repos are mostly research/hobbyist-grade (unmaintained, unclear licenses, not mobile-packaged) — treat every GitHub link found as inspiration/reference, not a drop-in dependency, and re-verify license + activity status directly on GitHub before any integration decision.
- aubio, TarsosDSP, and Essentia all carry GPL/AGPL-family licenses which are generally incompatible with shipping in a closed-source commercial app without a separate commercial license or careful legal isolation (e.g., separate GPL process/IPC) — this is a genuine legal risk, not hypothetical, and needs explicit resolution before dependency selection.
- No verified production mobile app combining real-time on-device DTW pose-scoring with real-time voice coaching for dance was found — Choreia's exact feature combination appears to be genuine white space (upside) but also means there is no proven mobile reference architecture to copy; expect nontrivial R&D risk on latency and battery/thermal from running pose ML + audio analysis + TTS/voice concurrently.
- Precise, current 2026 pricing for STEEZY, DanceFitMe, and Just Dance Now subscriptions was only partially confirmed (STEEZY ~$149.99/yr found; DanceFitMe and Just Dance Now pricing not independently confirmed in this pass) — verify directly on App Store/Play Store listings before using in competitive pricing decisions.
- Choreography copyright is genuinely murky per multiple legal sources (individual steps/social dances not copyrightable, but composed original sequences can be) — do not treat this research summary as legal clearance; a named-dance teaching feature specifically needs case-by-case legal review, especially for anything resembling a specific commercial artist's official choreography.
- The 'DanceDTW' body-proportion-compensating variant name could not be traced to a single definitive primary-source paper — verify before citing it as an established named technique in any technical spec or academic reference.

## ITEMS (name | license | on_device | url)
### DTW on skeleton sequences for dance scoring (core technique)
- what: Dynamic Time Warping compares a learner's joint-angle/keypoint time-series to a reference choreography, warping along time to give a similarity/distance score robust to tempo drift.
- why: This is the core scoring algorithm class for Choreia — temporally aligns learner pose sequence to reference regardless of learner speed variance.
- license: N/A — algorithm, not a licensed library
- maturity: Active academic area 2025-2026, multiple papers; not a single dominant library
- on_device: DTW itself is cheap (O(n*m) per joint or with banding much less) — very feasible on-device in real time with a sliding window
- integration: Implement DTW (or FastDTW/windowed DTW) natively in Kotlin/Swift over MediaPipe/BlazePose landmark buffers; no third-party ML needed
- caveats: Raw DTW on absolute joint coordinates is NOT robust to body proportions/camera distance — must normalize to joint angles or bone-length-normalized skeleton first (see JPSS/JASS below).
- url: https://arxiv.org/pdf/2503.19917
### Anomaly-Aware DTW for Skeleton-Based Action Quality Assessment (QAQA)
- what: 2025 MDPI paper (Sensors) proposing anomaly-aware DTW optimization for skeleton-based action/sports quality assessment, with open-source code.
- why: Directly addresses scoring quality/technique of a skeleton sequence vs reference for sports/dance education — closest published open-source match to Choreia's core scoring need.
- license: Check repo (typically MIT/Apache on MDPI-associated code, verify before use)
- maturity: 2025 paper, GitHub code available (github.com/waHAHJIAHAO/QAQA-main), research-grade not production
- on_device: Algorithm is DTW-based, lightweight enough for on-device use after adaptation; needs re-implementation off Python for mobile
- integration: Use as an algorithmic reference to port core anomaly-aware DTW logic into Kotlin/Swift; do not depend on the Python repo directly
- caveats: Verify current license and code quality directly on GitHub before porting — paper-associated repos vary widely in maintenance.
- url: https://www.mdpi.com/1424-8220/25/23/7160
### Joint Position/Angular Similarity Score (JPSS/JASS) — pose evaluation for dance learning
- what: ACM paper defining Joint Position Similarity Score and Joint Angular Similarity Score, evaluating 8 key joint regions via angle differences for dance pose scoring, body-proportion-invariant.
- why: Gives a concrete, proportion-robust scoring formula (angle-based, not raw coordinate distance) — solves the exact 'robust to body proportions' requirement in the task.
- license: N/A — reimplement formula from paper
- maturity: Academic (2020, still cited/used in 2025 follow-ups), no official open-source release found
- on_device: Trivial compute (joint-angle math), ideal for real-time on-device use
- integration: Reimplement angle-based scoring per limb (shoulder/elbow/hip/knee etc.) directly in native code operating on MediaPipe/BlazePose 3D landmarks
- caveats: No maintained reference implementation found publicly — must be built in-house from the paper's formulas.
- url: https://dl.acm.org/doi/pdf/10.1145/3410530.3414402
### DanceDTW (body-proportion-compensating DTW variant)
- what: A DTW variant referenced in 2025 dance-synchronization research that explicitly compensates for inter-participant physical (body proportion) differences before/during alignment.
- why: Named specifically to solve body-proportion robustness, matching Choreia's requirement almost exactly.
- license: N/A — technique
- maturity: Cited within recent (2025) academic literature; treat as a technique/pattern, not a packaged library
- on_device: Feasible on-device — same complexity class as standard DTW plus a normalization pre-step
- integration: Normalize skeleton (bone-length/torso-scale normalization) before running DTW distance in the mobile scoring pipeline
- caveats: Exact original source paper for 'DanceDTW' name wasn't independently isolated in search results beyond secondary citations — treat name as a technique label, verify primary source before citing academically.
- url: https://www.mdpi.com/1424-8220/25/23/7160
### motion-tracker (Apple Silicon real-time motion tracking incl. dance coaching, DTW)
- what: Open-source GitHub project: real-time human motion tracking/analysis for posture correction, fitness training, and dance coaching, using DTW for tempo/timing-invariant comparison, 33-keypoint pose tracking.
- why: Closest working open-source reference implementation combining pose tracking + DTW dance comparison in a single repo.
- license: Check repo license before reuse (not confirmed in search)
- maturity: Recent repo, optimized specifically for Apple Silicon (M4) — desktop-oriented, not mobile-ready out of the box
- on_device: Built for on-device (Apple Silicon) inference — architecture directly informative for iOS on-device design; would need porting for Android/mobile ARM
- integration: Study architecture and DTW implementation as a reference; not directly embeddable into a Flutter/mobile bridge without rework
- caveats: Verify current activity/license — description implies desktop/Mac-optimized tooling, not iOS/Android mobile SDK.
- url: https://github.com/MindDock/motion-tracker
### TikTok Dance Challenge Automated Scoring (Medium writeup)
- what: Practitioner writeup of building an automated TikTok-dance scoring system using pose estimation + comparison metrics.
- why: Practical, real-world worked example of the exact 'Just Dance-style scoring' problem outside academia, useful for implementation patterns.
- license: Unknown/not stated
- maturity: Hobbyist/blog-level project, not production library
- on_device: Not stated as on-device — likely built with Python/cloud pose estimation; principles transferable, code isn't
- integration: Reference only for scoring-pipeline design, not a drop-in dependency
- caveats: Treat as inspiration/pattern reference, not a vetted production technique.
- url: https://shawntng.medium.com/automated-scoring-for-tiktok-dance-challenge-2ba43532ae65
### DanceVision — AI-Driven Dance Proficiency Assessment (MediaPipe)
- what: Open-source GitHub project doing dance pose estimation and proficiency prediction with MediaPipe and various ML models, with keypoint playback for feedback.
- why: Direct open-source example of MediaPipe-based dance assessment matching Choreia's camera+ML-bridge architecture.
- license: Check repo — likely permissive but unverified
- maturity: Student/portfolio-level project, unclear maintenance status
- on_device: Uses MediaPipe (which does run on-device on mobile) but this specific repo appears to be a Python/desktop research project
- integration: Use as an architectural reference (MediaPipe landmark extraction -> ML/rule-based proficiency scoring), not a direct dependency
- caveats: Not mobile-packaged; would require full reimplementation of pipeline in Kotlin/Swift with MediaPipe Tasks SDK.
- url: https://github.com/zin288/DanceVision-AI-Driven-Dance-Proficiency-Assessment
### aubio — cross-platform audio/beat/onset analysis library (C, with bindings)
- what: Open-source C library for audio and music analysis: onset detection, tempo/BPM estimation, pitch tracking; designed for real-time causal (low-latency) use.
- why: A genuine C library (unlike librosa which is Python-only) that can be cross-compiled into iOS/Android native code for on-device BPM/beat detection of the user's own music.
- license: GNU GPLv3 (aubio core) — IMPORTANT: GPL is NOT simply 'commercial use allowed' for a closed-source indie app; must review LGPL exception status or use alternative for closed-source commercial shipping
- maturity: Long-running open-source project (since ~2003), stable, widely used; last major activity ongoing per aubio.org docs
- on_device: Yes — pure C, causal/real-time algorithms explicitly designed for low-delay live use; BPM estimate accurate roughly 40-250 BPM range per docs
- integration: Compile aubio as a native library, wrap via JNI (Android) and a Swift/Obj-C bridge (iOS), or find/adapt an existing Flutter FFI plugin
- caveats: License is the major blocker — verify current aubio license terms carefully (some distributions/versions differ) before shipping in a closed-source commercial app; a GPL native dependency can force full app source disclosure.
- url: https://github.com/aubio/aubio
### TarsosDSP — Android/Java real-time audio processing (beat/onset/pitch)
- what: Pure-Java audio processing library with practical onset detection (complex-domain, spectral flux) and beat induction (based on Simon Dixon's BeatRoot algorithm), plus YIN/MPM pitch detection.
- why: Directly usable on Android (pure Java/Kotlin-compatible, no native compile step) for on-device beat detection of user-selected music.
- license: GPL-3.0 — same closed-source commercial caveat as aubio; check for any LGPL/commercial exception before shipping
- maturity: Long-running (since ~2011), actively referenced in 2025 discussions, used in real Android DJ/BPM apps (BPM-Touch-Android)
- on_device: Yes — designed for real-time Android audio processing
- integration: Add as Android module (Kotlin bridge) for the beat-tracking layer of Choreia; iOS side would need a separate library (AudioKit or custom)
- caveats: GPL licensing is a real blocker for an indie closed-source commercial app without careful legal review or dynamic-linking/separate-process strategies.
- url: https://github.com/JorenSix/TarsosDSP
### Superpowered SDK — commercial low-latency BPM/beat/key detection for iOS+Android
- what: Commercial cross-platform (iOS/Android) native audio SDK offering BPM detection, key detection, bar detection, and beat detection optimized for mobile real-time use.
- why: A paid-but-clean-license alternative to aubio/TarsosDSP that sidesteps the GPL problem entirely and is purpose-built for mobile real-time beat detection — a strong pick for Choreia's on-device BPM detection of user's own music.
- license: Commercial/proprietary — paid license required (pricing not confirmed in search, contact vendor)
- maturity: Commercial product, actively maintained, used across many shipped mobile audio apps
- on_device: Yes — purpose-built for mobile on-device real-time analysis
- integration: License SDK, integrate native binaries via platform channel / FFI bridge in Flutter
- caveats: Solo/indie budget consideration — must check current pricing directly with Superpowered before committing; unconfirmed in this research pass.
- url: https://superpowered.com/bpm-detection-key-detection-bar-detection-beat-detection-android-ios
### BeatNet — real-time joint beat/downbeat/tempo/meter tracking (CRNN + particle filter)
- what: State-of-the-art research system (ISMIR 2021) for real-time and offline joint beat, downbeat, tempo, and meter tracking using a CRNN + particle filtering.
- why: Represents the current academic state of the art for beat tracking that the task explicitly asked to compare against; useful as an accuracy benchmark even if not directly embeddable.
- license: Check repo (research code, verify before any use)
- maturity: Research-grade Python implementation (PyTorch-based), ISMIR 2021 paper, actively cited through 2025
- on_device: Not mobile-ready as-is — Python/PyTorch model; would need conversion (e.g., to TFLite/CoreML) and significant engineering to run on-device in real time
- integration: Too heavy for a solo-founder mobile app without a dedicated ML engineer to convert/quantize the CRNN; more realistic to use as an offline benchmark for evaluating simpler on-device methods
- caveats: High accuracy but high integration cost — likely overkill vs. aubio/TarsosDSP/Superpowered for solo-budget mobile shipping.
- url: https://github.com/mjhydri/BeatNet
### Essentia — MTG audio analysis library (RhythmExtractor2013, BeatTrackerMultiFeature)
- what: C++ open-source audio analysis library from the Music Technology Group (UPF) with mature rhythm/beat-tracking algorithms (RhythmExtractor2013, BeatTrackerMultiFeature, BeatTrackerDegara).
- why: A well-established, more accurate alternative to aubio for BPM/beat detection, mentioned explicitly in the task's comparison list.
- license: Essentia core is dual-licensed AGPLv3 / commercial license from MTG — same closed-source concern as aubio/TarsosDSP, arguably stricter (AGPL)
- maturity: Long-running academic-grade library (UPF/MTG), mature, well-documented (via DeepWiki and official docs)
- on_device: C++ core is portable/compilable for mobile, but Essentia is heavier and less commonly deployed in shipped consumer mobile apps than aubio
- integration: Would require building Essentia for iOS/Android (nontrivial build system) and bridging via native code; higher integration cost than TarsosDSP
- caveats: AGPL is the strictest copyleft license relevant here — almost certainly requires a commercial license from MTG for closed-source app distribution; budget for licensing cost or avoid.
- url: https://essentia.upf.edu/reference/streaming_BeatTrackerDegara.html
### Metronome-only fallback design pattern (no third-party beat-tracking dependency)
- what: Design approach: instead of detecting the beat of arbitrary user music (technically and legally complex), offer a built-in metronome / royalty-free beat library with known, pre-analyzed BPM and beat-grid timestamps.
- why: This is the pragmatic, low-risk V1 path the task explicitly asks to evaluate — sidesteps licensing risk (see LEGAL thread) and the real-time beat-detection accuracy/latency problem entirely for a solo-founder MVP.
- license: N/A (architecture pattern); pair with royalty-free music library licenses
- maturity: Not a product — an architecture recommendation grounded in aubio's own real-time-analysis capabilities as an optional 'detect BPM of user track once, then generate a beat grid' offline step rather tha
- on_device: Fully on-device and simplest to implement reliably: precompute or let user tap-tempo, or use offline analysis once per track instead of continuous real-time detection
- integration: V1: bundle royalty-free beat tracks + metronome; V1.5: run one-time offline BPM analysis on user-selected tracks (using aubio/TarsosDSP in offline/batch mode, which is far more forgiving than real-time streaming mode) to build a beat grid, cache it, 
- caveats: Offline/batch BPM analysis is significantly more tractable and accurate than continuous real-time streaming beat tracking on mobile — recommended as the primary technical path rather than live beat-tracking.
- url: https://aubio.org/manual/latest/


# ==== voice-coach ====

## SUMMARY
The voice layer for Yula Motion's 5 apps should be a hybrid, not a single technology choice. (1) Fixed/common coaching lines (the ~80% of cues that repeat: "great extension," "keep your chin up," "nice tempo," rest-timer prompts) should be pre-rendered ONCE per app offline using a commercial cloud TTS vendor (ElevenLabs for best expressiveness, or OpenAI TTS as a cheaper first-party-ToS alternative) and shipped as bundled audio assets — this gives professional voice-actor-quality audio with zero runtime latency, zero network dependency, and no on-device inference cost, fully compatible with the 'raw video never leaves device' constraint since only synthesized audio output (not sensitive input) is involved. (2) Dynamic/variable content (rep counts, hold-duration seconds, personalized numbers, adaptive phrasing your rule engine generates at runtime) must use real on-device TTS since it can't be pre-recorded — on iOS that's the free system AVSpeechSynthesizer, on Android the system TextToSpeech API, both zero-cost with no licensing question but inconsistent voice quality (especially Android across OEMs) and no cross-platform voice-brand consistency. (3) For a more premium and *consistent* dynamic voice across both platforms, bundle an open neural model (Kokoro-82M, Apache-2.0, or Piper voices — mind Piper's Oct-2025 GPL-3.0 relicensing fork) via the sherpa-onnx runtime, which has an official Flutter plugin and runs offline on phone CPUs on both iOS and Android; this is the only path to a unified, licensable, offline, brand-owned coach voice for numbers/dynamic text. (4) Engineering: ducking is a solved, well-documented pattern on both platforms — iOS via AVAudioSession category .playback/.playAndRecord with .duckOthers (or .interruptSpokenAudioAndMixWithOthers for voice-prompt-style ducking), activated only for the duration of each cue and deactivated immediately after; Android via AudioManager.requestAudioFocus with AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK (Android O+ can auto-duck). Real-time voice-agent literature suggests a ~200ms target latency for conversational feel and up to ~500ms before it feels broken, with pre-caching/warm buffers (40–120ms client buffer) as standard mitigation — for a movement-cue use case (not full conversational turn-taking), this is a soft target: pre-rendered assets have effectively zero playback latency, and on-device TTS for numbers should be pre-warmed (synthesizer kept "hot," short numeric phrases pre-cached where predictable, e.g., common rep-count ranges) to stay well under that budget.

## RECOMMENDATIONS
- Adopt the hybrid pattern as the binding architecture for all 5 apps: pre-rendered cloud-TTS voice pack for fixed lines + on-device system/neural TTS for dynamic numbers — do not attempt full real-time cloud TTS in the coaching loop (adds network dependency, cost-per-session, and violates the indie/offline-first posture).
- For the pre-rendered voice pack: budget and record through OpenAI TTS or ElevenLabs ONE canonical 'Yula Motion coach' voice used consistently across all 5 apps (shared line library where phrasing overlaps — 'great job,' 'rest 30 seconds,' generic encouragement — plus a smaller per-app specific set for domain terms like boxing combos or cello bowing cues). This amortizes both cost and voice-consistency work across the family instead of paying 5x.
- Read ElevenLabs' actual current Commercial Terms/ToS directly (not just aggregator blog summaries) before finalizing budget for the voice-pack render, given all sourcing above for the 'perpetual commercial rights' claim came from third-party legal-explainer sites, not the primary document.
- For on-device dynamic TTS, standardize on AVSpeechSynthesizer (iOS) + Android TextToSpeech (Android) for V1 — it's free and ships today; evaluate bundling sherpa-onnx + Kokoro-82M as a V2 upgrade once you've validated real coaching-session UX, to get consistent cross-platform voice branding for numbers/dynamic phrases.
- If you pursue Piper voices at any point, pin the archived rhasspy/piper MIT-licensed release explicitly and do NOT adopt the OHF-Voice/piper1-gpl (GPL-3.0) successor without legal review, since GPL-3.0 in a closed-source paid app raises real copyleft questions.
- Implement audio ducking as a shared native module (one Kotlin + one Swift implementation, reused across all 5 apps via your shared native bridge layer) rather than reimplementing per-app: iOS AVAudioSession .duckOthers activated only around each cue; Android AudioManager transient-ducking focus request with the same activate/deactivate-per-cue discipline.
- Pre-cache short, high-frequency dynamic phrases (small integers, common rep ranges, countdown numbers) as tiny synthesized-and-cached audio clips on first use per session to avoid repeated synthesis latency, rather than calling the synthesizer fresh every time.
- Explicitly rule out Apple's Personal Voice API for this product — it is accessibility/AAC-scoped by OS policy and cannot be used as a general commercial coach-voice mechanism.

## RISKS
- Language coverage risk: Kokoro/Piper voice quality and language coverage claims found here are largely from secondary blog/review sites, not verified first-party benchmarks in Turkish or other target languages your apps may need — do an actual listen-test before committing engineering time.
- Piper licensing is in flux (Oct 2025 MIT→GPL-3.0 fork) — using the wrong fork could create real copyleft obligations for a closed-source commercial app; needs explicit verification/legal sign-off, not assumption.
- ElevenLabs/PlayHT commercial redistribution terms summarized here come mostly from aggregator/legal-explainer sites rather than the vendor's current primary ToS page — verify directly before locking budget, especially since PlayHT's commercial platform status is reported as disrupted post-Meta-acquisition (2025), making it an unreliable choice regardless.
- Android TTS quality fragmentation across OEMs is a real, well-documented risk for brand consistency — do not assume a Pixel-tested voice line experience generalizes to budget Android hardware; this is the strongest argument for eventually bundling a neural engine via sherpa-onnx rather than relying solely on system TTS.
- No first-party, apples-to-apples cost model was found for '500–2000 lines × 5 apps' — cost estimation had to be derived from general per-character pricing tiers (ElevenLabs ~$0.06–$0.12/1K chars API, or monthly character-quota plans) rather than a documented case study of a project at this exact scale; treat any total-dollar figure as your own estimate to compute (avg. line length × line count × 5 apps × per-character rate), not a benchmarked number from research.

## ITEMS (name | license | on_device | url)
### Apple AVSpeechSynthesizer (iOS/iPadOS/macOS built-in)
- what: System on-device TTS framework, ships free with every iOS install. Uses Apple's neural voices (multiple quality tiers: Compact/Enhanced/Premium, downloadable per-voice) with zero network dependency; personal-audio-session control via AVAudioSession.
- why: Zero-cost, zero-integration-risk baseline for dynamic voice lines (numbers, rep counts, adaptive coaching text) on iOS. No licensing question at all — it's a system API, not a third-party SDK.
- license: Apple system framework — no separate license, but usage is bound by standard App Store review guidelines. Not redistributable/bundleable; it's an OS call, always on-device, always free.
- maturity: Extremely mature, part of iOS since iOS 7 (2013), actively maintained through iOS 18/26. Streaming input is NOT supported — full text string required before synthesis starts (relevant to latency budge
- on_device: Fully on-device, all quality tiers (real hardware). Quality varies a lot by installed voice tier — default Compact voices sound robotic; users must download Enhanced/Premium voices from Settings for near-natural quality, which the app cannot force. R
- integration: Native Swift/Obj-C API call from the native camera/ML bridge layer (or via a small Flutter platform channel / plugin like flutter_tts) — trivial integration.
- caveats: Personal Voice (Apple's own voice-cloning accessibility feature) is EXPLICITLY OFF LIMITS for a coaching app: it's scoped to AAC/accessibility apps only, can't be captured/recorded, and is not a general commercial TTS option — do not plan around it.
- url: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer
### Android TextToSpeech API (Google TTS / OEM engines)
- what: System TTS API (android.speech.tts.TextToSpeech) that defers to whatever engine is installed — usually Google Text-to-Speech (Google's neural WaveNet-derived voices) but can vary per OEM/device.
- why: Android-side equivalent of AVSpeechSynthesizer for dynamic coaching lines; free, in-box, no license negotiation.
- license: System API, free, no redistribution question — Google's engine itself isn't bundled by you, it's whatever is on the device.
- maturity: Mature but fragmented — quality is inconsistent across OEMs ('passable on Pixel, embarrassing on budget OEM phone' per developer reports). No token-by-token streaming support.
- on_device: On-device once the offline voice pack for the target language is downloaded (Settings > Speech). Without the local pack, Google TTS streams through Google's servers, which breaks the 'raw audio never leaves device' framing (note: this streams synthes
- integration: Native Kotlin call or Flutter flutter_tts plugin.
- caveats: Because Android TTS quality/voice availability varies wildly by device and Google TTS isn't guaranteed to be present or offline-capable, Android is the platform where a bundled neural engine (Piper/sherpa-onnx/Kokoro) matters most for a consistent brand voice.
- url: https://developer.android.com/reference/android/speech/tts/TextToSpeech
### sherpa-onnx (k2-fsa)
- what: Open-source, cross-platform (Android/iOS/embedded) inference toolkit wrapping ONNX Runtime; provides ASR, TTS (VITS/Piper/Kokoro/Matcha models), speaker diarization, VAD — fully offline. Has an official Flutter plugin (sherpa_onnx on pub.dev) plus native Kotlin/Swift/Dart/C++ bindings.
- why: This is the practical bridge that lets you run Piper- or Kokoro-family neural voices natively inside a Flutter app on both iOS and Android with one shared codepath — solves the 'bundle a consistent neural coach voice across both OSes' problem.
- license: Apache-2.0 for the sherpa-onnx runtime itself. The BUNDLED MODEL's license governs the voice — check each model individually (Piper voices vary by voice/license, Kokoro is Apache-2.0, VITS models vary
- maturity: Actively developed (k2-fsa/Next-gen Kaldi team), broad platform support, real production use (e.g., VoxSherpa Android app ships it as a system TTS engine). Not a big-name commercial vendor but is the 
- on_device: Fully offline/on-device by design, CPU-only inference, works down to embedded/Raspberry Pi class hardware — comfortably runs on any modern phone CPU. Flutter package: https://pub.dev/packages/sherpa_onnx
- integration: Flutter plugin via pub.dev (sherpa_onnx, sherpa_onnx_ios, sherpa_onnx_android) — bundle .onnx voice model as an asset, load via Dart API. Straightforward for a Flutter-UI + native-bridge architecture like yours.
- caveats: Voice model file sizes (60–300MB per voice/tier) add to app binary size — for 5 apps you likely want ONE shared voice model bundled once via a shared package/module rather than duplicated per-app.
- url: https://github.com/k2-fsa/sherpa-onnx
### Kokoro-82M (via sherpa-onnx or standalone ONNX runtime)
- what: 82M-parameter open TTS model (StyleTTS2 lineage) — ranked highly on public TTS-quality arenas for an open model, small footprint (~327MB weights), CPU-runnable including WASM/mobile.
- why: Best current open-source 'neural quality on a phone CPU' option for a bundled, brand-consistent coach voice usable for BOTH pre-rendered lines and any dynamic on-device synthesis fallback, across iOS+Android via sherpa-onnx.
- license: Apache-2.0 — permissive, explicit commercial use, redistribution, and modification allowed, no royalties.
- maturity: Released 2024/2025, rapidly growing community adoption through 2026 (per multiple review sites), but it is a community model, not a vendor-backed product — no SLA, no support contract, and language/ac
- on_device: Yes — explicitly designed for edge/mobile/WASM deployment, CPU-only, real-time-capable on modern phone SoCs. 54 voices across 8 languages reported by third-party writeups (verify per your target language list — Turkish coverage in particular needs ch
- integration: Bundle Kokoro ONNX weights as a shared asset consumed by sherpa-onnx across all 5 Flutter apps.
- caveats: Multiple secondary sources report the same specs (82M params, Apache-2.0, ~327MB) — worth an independent listen-test on real target-language coaching phrases before locking in, since 'quality' claims are largely from third-party blog aggregators, not a first-party benchmark you've run.
- url: https://huggingface.co/hexgrad/Kokoro-82M
### Piper TTS
- what: Fast, small, CPU-only neural TTS (VITS-based) originally by rhasspy, widely used for offline voice assistants; long-standing option before Kokoro's popularity.
- why: Mature, widely-used offline TTS with existing per-voice trained models in many languages (useful for Turkish/EN coverage) — a fallback/alternative to Kokoro, also runnable via sherpa-onnx.
- license: IMPORTANT LICENSE CHANGE (2025): the original rhasspy/piper repo (MIT) was archived read-only in October 2025; active development moved to OHF-Voice/piper1-gpl, which is GPL-3.0. GPL-3.0 on the *infer
- maturity: Very mature/widely deployed historically, but the license fork in Oct 2025 is a meaningful governance disruption — flagged explicitly per the source's own analysis.
- on_device: Yes, purpose-built for fast local/CPU inference, tiny footprint, no internet required.
- integration: Via sherpa-onnx (same plugin pathway as Kokoro) using the archived MIT piper voices, OR direct native Piper binaries.
- caveats: Do NOT casually adopt current 'Piper' assuming MIT — verify which fork/commit you're pinning and get explicit legal sign-off if using the GPL-3.0 successor in a closed-source paid app.
- url: https://github.com/OHF-Voice/piper1-gpl
### ElevenLabs (offline pre-render pipeline)
- what: Cloud neural TTS/voice-cloning API — used here NOT at runtime, but as an offline authoring tool: generate all fixed coaching lines once, ship the resulting audio files as app assets.
- why: Best-in-class voice quality/expressiveness for the ~80% of coaching lines that are fixed phrases ('great extension', 'chin up', 'nice tempo') — record once per app, ship as static asset, zero runtime cost/latency/network dependency.
- license: Paid plans include a commercial license — audio output is yours to use/distribute perpetually in apps, even after subscription ends, provided compliance with ToS/Prohibited Use Policy. Free-tier outpu
- maturity: Market-leading commercial TTS vendor, very actively used for this exact pre-render-and-ship pattern across apps/games/audiobooks.
- on_device: N/A (offline authoring only) — the rendered .mp3/.wav files ARE shipped as on-device assets and played locally at runtime, satisfying the 'raw video never leaves device' constraint (audio output isn't the sensitive data path anyway).
- integration: One-time offline batch generation (script your ~500–2000 lines per app through the API once), store outputs as bundled audio assets, play via standard Flutter/native audio player (AVAudioPlayer/AudioTrack) with the ducking/session logic below.
- caveats: Terms.law and other secondary legal-explainer sites (not ElevenLabs' own ToS page) are the primary sources here for the 'perpetual commercial rights' claim — for a shipped commercial product across 5 apps, read ElevenLabs' actual current ToS/Commercial Terms directly before committing budget, since 
- url: https://elevenlabs.io/creative
### OpenAI TTS API (gpt-4o-mini-tts / tts-1)
- what: Cloud TTS API, alternative/backup pre-render source to ElevenLabs; also usable for cheap dynamic cloud rendering if you ever allow an online mode.
- why: Cheaper per-character than ElevenLabs at scale, no plan-tier restriction on commercial use, straightforward for batch-rendering the fixed-phrase voice pack.
- license: Commercial use/redistribution allowed under OpenAI's standard API usage policies, no separate 'commercial plan' gate. Key obligation: must disclose to end users that the voice is AI-generated, and mus
- maturity: Mature, stable pricing/API, backed by OpenAI directly (first-party ToS, lower legal-ambiguity risk than aggregator-sourced ElevenLabs claims above).
- on_device: N/A — cloud-only API, same offline pre-render pattern as ElevenLabs (render once, ship the file).
- integration: Same batch-render-once-and-bundle pattern as ElevenLabs.
- caveats: Voice expressiveness/character generally regarded as a notch below ElevenLabs for emotive coaching delivery, but adequate and meaningfully cheaper — good candidate for the bulk of lines, reserving ElevenLabs (if budget allows) for hero/flagship lines per app.
- url: https://developers.openai.com/api/docs/guides/text-to-speech


# ==== datasets-fixtures ====

## SUMMARY
Across the five Yula Motion domains, the strongest, most clearly usable public assets are AIST++'s Google-released CC BY 4.0 dance motion data (Choreia), InfiniteRep's synthetic fitness-rep videos (explicitly framed as commercial-usable, useful for Gravita/JabLab/Lissom threshold work), and Google's MediaPipe/BlazePose Pose Landmarker itself (Apache 2.0, on-device, and the natural backbone of a self-recorded fixture-library protocol). Most of the other domain-specific academic datasets found — Fit3D, FLAG3D, Motion-X/IDEA-400, Yoga-82, 3D-Yoga/3DYoga90, ShadowPunch, BoxingVI, FineDance, PhantomDance, URMP — are valuable as methodology references, taxonomy sources, or threshold sanity-checks, but carry research-only, non-commercial, share-alike, or unconfirmed licenses that make them risky to fine-tune a shipped commercial model on without direct clearance from the authors. No dataset specifically covering handstand/inversion technique was found, which is a genuine gap best filled by synthetic generation (Unity Perception's Synthetic Humans toolkit, or a Blender/SMPL-X pipeline informed by BEDLAM's and RePoGen's rare-pose methodology) combined with careful in-house recording. For an indie, camera-only, on-device-inference architecture, the most robust and lowest-risk data strategy is to make self-recorded video → MediaPipe landmark extraction → hand-labeled JSON fixtures the primary pipeline for every app, using open datasets narrowly and only where their license is confirmed safe, for calibration and edge-case coverage rather than as the primary training corpus.

## RECOMMENDATIONS
- Adopt a two-track data strategy: (1) self-recorded fixtures via MediaPipe/BlazePose landmark extraction as the PRIMARY source of truth for every app (cheapest, license-clean, exactly matches your production pipeline), supplemented by (2) select open datasets ONLY for threshold sanity-checking and edge-case coverage where self-recording is impractical (e.g., professional-level dance/boxing technique, rare handstand variants).
- For Gravita/handstand coverage gaps, do not rely on finding a ready-made open handstand dataset (none was found) — instead use Unity Perception (or a Blender+SMPL-X pipeline modeled on BEDLAM's/RePoGen's approach) to synthetically generate rare inversion poses with exact ground-truth angles, since this is the cleanest commercially-safe route.
- For Lissom, treat Yoga-82 as reference-only (its non-commercial license blocks shipped-model training) and instead prioritize verifying the license of 3D-Yoga/3DYoga90 directly with the authors, since its built-in quality scores are unusually well-suited to your assessment engine.
- For JabLab, pursue ShadowPunch and BoxingVI license clarification directly with the authors before relying on them — both are new/small releases with unconfirmed formal licenses; supplement heavily with self-recorded shadow-boxing footage across skill levels.
- For Choreia, AIST++'s Google-released CC BY 4.0 motion/keypoint data (distinct from the more restrictive original AIST video database) is your strongest, most clearly-licensed foundation; layer FineDance/PhantomDance in only after confirming their GitHub repo license files.
- For Ostinato, URMP is a reasonable audiovisual reference for cello ensemble footage but is too narrow (chamber-music focus, not pedagogical technique errors) to calibrate technique thresholds alone — plan for a larger self-recorded cello-technique fixture set as the primary source, using URMP mainly for A/V-sync validation.
- Before any fine-tuning (not just fixture/threshold use) of a shipped on-device model on Motion-X/IDEA-400, get legal review of the CC BY-SA share-alike implications, since it could create obligations on your model artifact.
- Budget real founder/contractor time for the self-recording protocol (record → MediaPipe extract → hand-label → JSON fixture) across all 5 apps — it is the only fully commercially-clean, architecture-matched data source found in this research, and every strong open dataset either has license friction (research-only, non-commercial, unconfirmed) or a narrow domain mismatch.

## RISKS
- Several of the most topically relevant datasets (Fit3D, FLAG3D, Motion-X, 3D-Yoga, ShadowPunch, BoxingVI, FineDance, PhantomDance, URMP) have licenses that are either explicitly research/non-commercial, gated behind a commercial-license request, or simply unconfirmed in available documentation — using any of them for shipped-model fine-tuning without direct written confirmation from the authors is a legal risk for a commercial indie product.
- AIST++ has two license layers (Google's CC-BY-4.0 derived motion data vs. the original AIST Dance Video Database's own more restrictive terms) that are easy to conflate — pulling the wrong artifact could inadvertently violate the source video license.
- No open dataset was found that specifically covers handstand/inversion technique at the granularity Gravita needs — this is a genuine data gap that synthetic generation (Unity Perception / Blender+SMPL-X) or careful self-recording must fill; do not assume Kinetics or generic gymnastics footage covers this (search did not surface a usable handstand-specific subset).
- Synthetic-data licensing (BEDLAM in particular) can be more complex than it first appears because the dataset license and the underlying purchased 3D/environment asset licenses (Unreal Marketplace, Evermotion, etc.) are separate and some explicitly forbid neural-network training use — treat BEDLAM as a methodology reference, not a drop-in commercial data source.
- YouTube-sourced datasets (BoxingVI) typically distribute annotations/URLs rather than re-hosted video, so long-term reusability depends on source videos remaining available and on compliance with YouTube's own ToS when re-downloading.

## ITEMS (name | license | on_device | url)
### Fit3D
- what: 3M+ RGB frames with synchronized 3D mocap ground truth (25-joint 3D skeletons + SMPL/SMPLX fits) of 13 subjects (1 certified fitness instructor + trainees) performing 47 exercises across warm-up, barbell, dumbbell and equipment-free categories, filmed multi-view in a mocap studio.
- why: Directly usable for Gravita/Lissom/JabLab-style resistance/calisthenics rep and form-quality ground truth; instructor-vs-trainee pairing is useful for threshold tuning ('correct' vs 'incorrect' form) and rule-engine calibration.
- license: Research-only via IMAR/Sminchisescu terms; commercial use requires separate license (email licenses@imar.ro, subject '[SC3D Commercial Use]' per IMAR's related terms page). Treat as NOT cleared for co
- maturity: Academic release (CVPR/journal lineage, IMAR/Sminchisescu lab), actively linked via GitHub tools repo, used in multiple 2023-2025 papers (AIFit, canonical-domain pose papers).
- on_device: Not a runtime component — it's training/eval data; landmarks can be reprojected to 2D and used to derive angle thresholds usable inside a lightweight on-device rule engine.
- integration: Offline: download (access request), extract joint-angle thresholds/exercise state machines, bake resulting numeric thresholds into the app; do not ship raw dataset assets in the app.
- caveats: Access requires an application/registration to IMAR; exact current gating process unconfirmed by direct site fetch (only indirect search snippets reviewed). Commercial-license cost/terms not found — must contact IMAR directly before relying on it for a commercial product.
- url: https://fit3d.imar.ro/
### InfiniteRep
- what: ~1,000 synthetic videos of diverse rendered avatars performing multiple reps of common exercises across 7 unique synthetic home-workout 3D scenes, varied lighting/camera angles, normal body-type and skin-tone distribution, released by Infinity AI.
- why: Explicitly built for rep-counting, pose-estimation and form-correction CV — matches JabLab/Gravita/Lissom rep-counting and threshold-calibration needs almost exactly; being synthetic+diverse also helps de-bias fixture libraries (varied body types) ch
- license: Explicitly stated by the publisher as available for BOTH academic and commercial use — one of the few fitness pose datasets with that framing (verify exact license text/version on the download page be
- maturity: Small-team synthetic-data startup (Infinity AI) release, used as a benchmark in a 2025 Springer paper (YOLOv8 + DTW rep analysis); dataset card on Papers-with-Code (https://paperswithcode.com/dataset/
- on_device: N/A (training/threshold data), but its synthetic landmark ground truth maps directly onto MediaPipe/BlazePose-style 33-point skeletons commonly used on-device.
- integration: Use as replay fixtures directly (recorded synthetic sequences → convert to your landmark JSON schema) and/or for threshold calibration of rep-counting/form rule engines; low risk for limited fine-tuning given commercial license claim.
- caveats: Verify the actual license file/version at time of download — startup-blog claims of 'commercial use OK' should be reconfirmed against the dataset's formal terms before production reliance.
- url: https://medium.com/infinity-ai/infiniterep-an-open-source-synthetic-dataset-for-remote-fitness-and-pt-applications-906946643e74
### InfiniteForm
- what: 60k synthetic images (companion/earlier release from the same Infinity AI 'Pixelate' synthetic pipeline) labeled with 9 image-level fitness-relevant labels, designed as a 'minimal bias' dataset for fitness computer vision (varied body types).
- why: Useful for de-biasing detection/segmentation stages (person/pose detection robustness across body types) that sit upstream of your exercise-specific state machines.
- license: Not conclusively confirmed by search (Infinity AI markets itself as open-source-friendly like InfiniteRep, but no explicit commercial-use license text was found) — flag as UNCONFIRMED, verify on offic
- maturity: arXiv paper (2021) from Infinity AI; smaller and older than InfiniteRep, less directly rep/video-oriented (image dataset, not video).
- on_device: N/A, training-time only.
- integration: Secondary/backup dataset behind InfiniteRep and Fit3D for detector robustness testing.
- caveats: License unconfirmed — treat as research-only until verified.
- url: https://arxiv.org/pdf/2110.01330
### MM-Fit
- what: Multimodal dataset of ~20 full-body workout sessions: time-synchronized IMU (accelerometer/gyroscope/heart-rate from smartphones, smartwatches, earbuds) plus multi-viewpoint RGB-D video with 2D/3D pose estimates, covering common gym exercises with rep annotations.
- why: Good secondary source for rep-counting/exercise-recognition threshold validation, and useful if any Yula Motion app later fuses wearable IMU with camera (not in current binding architecture, but useful for hybrid rule-engine robustness testing).
- license: Zenodo hosting generally implies an open license (commonly CC BY or similar) — exact license field should be checked on the specific Zenodo record page before use; not independently confirmed here.
- maturity: Published ACM IMWUT 2020 (Strömbäck, Huang, Radu); data hosted on Zenodo (https://zenodo.org/records/7607736, https://zenodo.org/records/7672767); still cited in 2024 multimodal-HAR papers (e.g., MuJo
- on_device: N/A, offline dataset only; RGB-D + skeleton data is a reasonable stand-in for replay fixtures if your engine ever needs depth-informed thresholds.
- integration: Use for cross-validating rep-counting algorithms against IMU ground truth; not a primary fixture source since it lacks the specific exercises (handstand/yoga/boxing/dance/instrument) most Yula Motion apps need.
- caveats: Camera-only binding architecture means the IMU modality is not directly usable in-app; only the RGB-D/pose slice is relevant.
- url: https://mmfit.github.io/
### FLAG3D
- what: Large-scale 3D fitness activity dataset: 180K sequences across 60 exercise categories, captured with a 24-camera VICON mocap system + 77 markers, paired with detailed professional language instructions describing correct execution, plus video from mocap render, smartphone, and other sources.
- why: The paired natural-language instruction + high-fidelity 3D pose is directly useful for building rule-engine 'correct form' templates and for the coaching-voice-line content (e.g., deriving what verbal cue corresponds to what joint-angle deviation) fo
- license: Academic/research release; exact commercial terms not directly confirmed in search results — check the CVF/project page license section before commercial fine-tuning.
- maturity: CVPR 2023 paper (Tang et al.), extended in 2025 as FLAG3D++ (adds language-guided repetition counting and action-quality assessment — very close to your exact use case). Actively maintained research l
- on_device: N/A, training/reference data only.
- integration: Mine the language instructions + 3D pose pairs to hand-author or bootstrap rule-engine thresholds and coaching scripts; use mocap sequences as replay fixtures for form-quality testing.
- caveats: License terms not independently verified — likely research-only pending confirmation; FLAG3D++'s L-AQA/L-RAC tasks are conceptually almost identical to your JabLab/Gravita quality-assessment problem and worth reading closely even if data itself isn't reusable.
- url: https://arxiv.org/abs/2212.04638
### Motion-X / IDEA-400
- what: Motion-X is a large-scale 3D whole-body (SMPL-X, incl. hands+face) motion dataset aggregated from many sources; IDEA-400 is its curated subset of ~13K sequences across 400 daily human actions (overlapping with NTU-RGB+D 120), covering some sport/exercise/dance-adjacent actions.
- why: Whole-body (hands+face) motion capture is useful for Ostinato (hand/arm/posture at an instrument) and general pose diversity/augmentation for fine-tuning pose-adjacent models; broad action coverage helps negative/background-class fixtures.
- license: Dual-licensing: Motion-X itself is CC BY-SA 4.0 for the IDEA-400 subset, BUT the full aggregated dataset requires a non-commercial-use request form AND compliance with every underlying source dataset'
- maturity: NeurIPS 2023 paper, actively extended (Motion-X++ arXiv 2025), well-maintained GitHub with DeepWiki docs.
- on_device: N/A, training-time only.
- integration: Use narrowly — pull only the IDEA-400 CC BY-SA subset for augmentation/fine-tuning, and satisfy share-alike (any model checkpoint trained substantially on it may need share-alike consideration — consult counsel if fine-tuning a shipped model on it).
- caveats: CC BY-SA share-alike could be a real constraint for a closed-source commercial model; verify per-clip source-dataset license before use, since Motion-X aggregates many independently licensed motion sources.
- url: https://github.com/IDEA-Research/Motion-X
### Yoga-82
- what: ~28,478 in-the-wild images of yoga poses labeled with a 3-level hierarchy down to 82 fine-grained pose classes (body-position, category, pose name), sourced from web images (not mocap).
- why: Direct relevance to Lissom for yoga-pose classification/assessment name-space and as a source of reference imagery for pose-name taxonomy design, though it's 2D web imagery not clean landmark ground truth.
- license: Explicitly NON-COMMERCIAL, research/education only; metadata (labels) released as CC0 but underlying images retain original copyright and must be checked individually for any reproduction — NOT usable
- maturity: CVPR Workshop 2020 paper (Verma et al.), widely cited baseline in yoga-pose-classification literature through 2024-2025.
- on_device: N/A.
- integration: Use only for taxonomy reference / internal threshold-tuning sanity checks (visually eyeballing what 'correct' vs 'incorrect' looks like), never for shipped model training given the non-commercial clause.
- caveats: Hard license blocker for commercial fine-tuning — do not train a shipped model on Yoga-82 images without separate rights clearance.
- url: https://sites.google.com/view/yoga-82/home
### 3D-Yoga / 3DYoga90
- what: 3D-Yoga: 3,792 action samples / 16,668 RGB-D key frames from 22 subjects across 117 yoga poses, captured with two RGB-D cameras (skeleton + pose label + quality score per sample), enabling both classification and action-quality-assessment tasks. 3DYoga90: a related hierarchical dataset with 90 poses, RGB video + 3D skeleton sequences, one of the largest open yoga skeleton sets.
- why: 3D-Yoga's built-in 'quality score' per pose is unusually well-matched to Lissom's mobility/flexibility assessment use case — closest thing found to ready-made ground truth for form-quality thresholds.
- license: Not confirmed in search — typical for ACCV/academic pose datasets to be research-only; must check project page directly before any commercial use.
- maturity: ACCV 2022 (3D-Yoga) and arXiv 2023 (3DYoga90, https://arxiv.org/abs/2310.10131) — both fairly recent, moderate citation so far, smaller academic labs.
- on_device: N/A.
- integration: High-value for threshold calibration if license permits (its per-pose quality scores could directly seed your rule-engine's scoring function); otherwise use only as a design reference.
- caveats: License unconfirmed — flag as likely research-only pending direct verification; the quality-score labeling methodology itself (how they derived scores) may be more valuable to read than the raw data if commercial license isn't available.
- url: https://3dyogabsu.github.io/
### ShadowPunch
- what: Open dataset for fast-action video event spotting in shadow-boxing: high-frame-rate video with frame-level annotations of punch types (jab/hook/uppercut/etc.) plus pose-keypoint annotations.
- why: Closest direct match found for JabLab — purpose-built for shadow-boxing punch detection/spotting, which is exactly JabLab's core loop.
- license: UNCONFIRMED — no explicit license text found; must check the OpenReview submission or contact authors directly before use.
- maturity: Recent OpenReview benchmark paper; GitHub/download location and formal license not surfaced in search — appears to be a newer, less-established release than Fit3D/AIST++.
- on_device: N/A, training/eval only, but frame-level punch-type + keypoint annotations translate well to a rule-engine's punch-classification and timing thresholds.
- integration: If license permits: use directly as fixtures for punch-type classification thresholds and combo-timing calibration; otherwise use only to benchmark your own self-recorded fixture design against a published methodology.
- caveats: Could not confirm license or a stable public download link — highest-uncertainty item in the boxing category; verify before relying on it.
- url: https://openreview.net/forum?id=Jq8HYNZG9s
### BoxingVI
- what: Multi-modal boxing benchmark built from 20 unedited YouTube videos of shadow boxing, punching-bag work, and boxing tutorials, with fine-grained temporal segmentation/labeling of jab, cross, hook, uppercut, plus frame-wise 2D pose estimation.
- why: Second strong JabLab-relevant dataset; YouTube-sourced 'in the wild' footage is useful for testing robustness of your rule engine against non-lab conditions (lighting, camera angle, clothing) that self-recorded lab fixtures may not cover.
- license: YouTube-derived data typically ships as annotation-only (URLs + labels, not re-hosted video) due to platform ToS — expect to need to re-download source videos yourself; check paper for exact terms.
- maturity: Very recent (Nov 2025 arXiv), sponsored by Ministry of Youth Affairs and Sports (Bangladesh) — new benchmark, unclear community adoption yet.
- on_device: N/A, training/eval only.
- integration: Use for building a held-out 'wild footage' validation fixture set separate from your self-recorded lab fixtures, to sanity-check generalization of JabLab's punch-classification thresholds.
- caveats: Being YouTube-sourced, re-usability may degrade over time as videos get taken down; annotation-only distribution is likely, requiring your own scraping/download step (check ToS compliance).
- url: https://arxiv.org/pdf/2511.16524
### AIST++ / AIST Dance Video Database
- what: AIST++ is a large 3D dance motion dataset (Google) reconstructed from the AIST Dance Video Database: 1,408 sequences, 30 dancers, 10 dance genres, with paired music, SMPL 3D keypoints/motion, and multi-view camera calibration, built specifically for music-conditioned 3D dance generation.
- why: The single best-fit public dataset for Choreia — it is literally music+3D-dance paired data at genre-diverse scale, useful for both fixture-based testing of a beat-sync/technique engine and for threshold/style calibration.
- license: AIST++ annotations/derived motion data are released under CC BY 4.0 by Google (commercial use allowed with attribution) — but the underlying AIST Dance Video Database (source videos) themselves are pr
- maturity: Google Research release (2021), extremely widely used/cited baseline in 3D dance-generation literature through 2025-2026 (dozens of derivative papers: DiffDance, GCDance, InterDance, etc.).
- on_device: N/A, training/fixture data only.
- integration: Strong candidate for both (a) replay fixtures (music-synced 3D pose sequences directly drive automated tests of Choreia's beat-sync judgments) and (c) light fine-tuning/threshold calibration of movement-quality scoring; verify you're using the CC-BY 
- caveats: Double-check which artifact you're pulling (Google's derived AIST++ vs. original AIST video database) since their licenses differ materially; original AIST video license terms not independently confirmed here.
- url: https://google.github.io/aistplusplus_dataset/
### FineDance
- what: 14.6 hours of finely-annotated music-dance paired 3D motion data spanning 22 dance genres, with fine-grained hand motion and posture accuracy, presented at ICCV 2023; largest genre-diverse music-dance dataset in its class as of publication.
- why: Complements AIST++ for Choreia with more genre diversity and finer hand-motion detail (useful if Choreia ever scores arm/hand styling, not just gross body beat-sync).
- license: Not explicitly confirmed in search results — GitHub repo license file should be checked directly before use (typical for these academic dance-gen datasets to be research-only or require a request form
- maturity: ICCV 2023 paper, active GitHub, referenced by 2025 successor work (OpenDance, GCDance).
- on_device: N/A.
- integration: Secondary fixture/calibration source behind AIST++ if license allows; otherwise reference-only for genre taxonomy design.
- caveats: License unconfirmed.
- url: https://github.com/li-ronghui/FineDance
### PhantomDance
- what: 260 professionally-animator-crafted dance-music pairs, ~9.5 hours total, using SMPL 24-joint skeleton definition, built for the DanceFormer/AAAI 2022 music-conditioned dance-generation work.
- why: Animator-authored (not mocap-noise) motion may be cleaner for defining 'ideal' reference choreography templates that Choreia's scoring engine compares learner motion against.
- license: Not explicitly confirmed — check repository license file (GitHub) directly before use.
- maturity: AAAI 2022 paper, official GitHub release (v1.2), moderate adoption.
- on_device: N/A.
- integration: Potential source of clean 'gold standard' reference sequences for Choreia's comparison engine, license permitting.
- caveats: License unconfirmed; animator-authored motion may be stylistically stylized/exaggerated versus real learner motion, so best used for reference templates rather than realistic negative-example fixtures.
- url: https://github.com/libuyu/PhantomDanceDataset
### URMP (University of Rochester Multi-Modal Music Performance Dataset)
- what: 44 classical chamber-music pieces (duets to quintets) with musical score, individual-instrument audio+video recordings, assembled mixture audio/video, and frame-/note-level ground-truth transcription annotations; includes cello among the instruments recorded.
- why: Directly relevant to Ostinato (V1 cello) as a source of camera+audio synchronized performance footage and note-level ground truth, useful for building bowing/posture fixtures and for calibrating audio-visual sync thresholds.
- license: Access requires filling out a Google form (to track usage/impact); explicit license text not found in search — request the terms directly from the dataset maintainers (contact listed: bochen.li@roches
- maturity: Published 2016 (Li et al., multimodal music analysis paper), still actively cited through 2025 (e.g., video-to-music generation surveys) — a durable, standard benchmark in the AV music-performance spa
- on_device: N/A, training/reference data only.
- integration: Use cello performance clips as replay fixtures for testing Ostinato's camera-based posture/bow-angle detection against real performance footage; note-level transcription ground truth is useful for validating audio-side timing logic (though your engin
- caveats: Coverage of solo cello technique/posture variety is limited (chamber ensemble focus, not pedagogical technique-error footage) — likely insufficient alone for full threshold calibration; will need supplementary self-recorded cello-technique fixtures. License terms not confirmed as commercial-safe.
- url: https://labsites.rochester.edu/air/projects/URMP/URMP_doc.pdf
### BEDLAM / BEDLAM2.0
- what: Synthetic dataset of ~over 8M (v2.0) images of animated, clothed 3D bodies (SMPL-X) rendered in Unreal Engine 5 with motion blur, diverse body shapes/skin tones/hair, and realistic motions, built by Max Planck (Perceiving Systems) for 3D human pose/shape training.
- why: Best-documented open synthetic-human pipeline for generating rare/extreme poses (e.g., handstands, inversions) that are hard to source real footage for — Gravita's handstand-inversion coverage gap is exactly the kind of problem BEDLAM-style synthetic
- license: Registration + acceptance of a license agreement required; use is gated per-asset — many high-quality commercial Unreal Marketplace/Evermotion assets used in rendering explicitly restrict use in neura
- maturity: CVPR 2023 (BEDLAM) + BEDLAM2.0 (arXiv Nov 2025, NeurIPS 2025) — active, well-funded academic project with regularly updated render pipeline tools on GitHub (PerceivingSystems/bedlam2_render).
- on_device: N/A — this is a rendering/data-generation pipeline and dataset, not a runtime component.
- integration: Best used as a methodology reference (how they rig SMPL-X bodies + rare poses in UE5) to build your OWN custom synthetic handstand/inversion generator in Blender/Unity rather than directly redistributing BEDLAM assets, given the licensing complexity 
- caveats: License is genuinely complicated (dataset license + per-asset marketplace licenses) — treat as NOT cleanly commercial without direct confirmation from MPI licensing; primary value for Yula Motion is architectural/technique reference, not a drop-in commercial dataset.
- url: https://bedlam.is.tue.mpg.de/
### Unity Perception + Synthetic Humans package
- what: Unity's open-source Perception package (com.unity.perception) extends the Unity Editor with tools for generating labeled synthetic CV datasets — keypoint/pose/animation randomization, domain randomization, and a companion 'Synthetic Humans' package for diverse, poseable, randomizable, deterministic 3D human generation, plus cloud scaling via Unity Simulation.
- why: Most practical, indie-budget-friendly toolchain (vs BEDLAM's UE5+MPI-grade pipeline) for generating YOUR OWN synthetic fixture library of rare poses (handstands for Gravita, extreme mobility poses for Lissom, punch stances for JabLab) with exact grou
- license: Unity Companion License / open-source (package itself free to use); output data you generate is yours — no data-licensing entanglement like BEDLAM's marketplace-asset problem, making it the cleanest p
- maturity: Actively maintained Unity Technologies open-source package (arXiv paper 2021, docs updated through Perception 1.0), well-documented tutorials including a specific Human Pose tutorial (github.com/Unity
- on_device: N/A — desktop/cloud data-generation tool, not a runtime dependency; output (rendered frames + ground-truth keypoints) becomes your fixture/training data.
- integration: Recommended primary tool: build a small Unity scene with a rigged/poseable avatar (e.g., using Unity's Synthetic Humans or an imported SMPL/Mixamo rig), script pose randomization for handstand/inversion/punch-stance ranges, and export labeled keypoin
- caveats: Search results for 2025-2026-specific updates were limited (most concrete docs are 2021-2022 vintage); confirm current package status/maintenance activity in the Unity Asset Store / Package Manager before committing, since Unity has discontinued some synthetic-data cloud services in the past (Unity 
- url: https://github.com/Unity-Technologies/com.unity.perception
### MediaPipe Pose Landmarker (BlazePose) — self-recording protocol enabler
- what: Google's on-device pose-landmark model (33 3D body landmarks), available via Tasks API for iOS/Android/Web/Python, real-time capable on mobile CPUs/GPUs — the same class of model your apps would use in production and thus the natural tool for building your OWN fixture library: record video → run MediaPipe → export landmark sequences as labeled JSON.
- why: This is the practical backbone of the 'record your own fixture library' protocol requested in the task: self-record reference exercises/poses on-device with the same landmark extractor you ship, then hand-label rep boundaries/technique-error moments 
- license: Apache 2.0 (MediaPipe/Google AI Edge is open-source, commercial use explicitly permitted) — the cleanest license story of anything in this list since it's the tool itself, not a dataset with third-par
- maturity: Actively maintained, current 2025-2026 Google AI Edge product line (rebranded from 'MediaPipe Solutions'), production-grade, used broadly in industry.
- on_device: Yes — this IS the on-device inference engine; fully aligned with the binding architecture (raw video never leaves device, real-time landmark extraction feeds your deterministic rule engine/state machine).
- integration: Practical protocol: (1) record reference + error-case video per exercise/pose/technique using target device cameras across lighting/angle/body-type variety, (2) run MediaPipe Pose Landmarker (or BlazePose Full/Heavy variant) offline over each clip to
- caveats: This is a protocol/tool recommendation rather than a dataset — the actual labeling effort (rep boundaries, technique-error tagging) remains manual work for the indie team; budget real time for recording diverse bodies/lighting to avoid the exact bias problems InfiniteRep/InfiniteForm were built to s
- url: https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker


# ==== pricing-monetization ====

## SUMMARY
Health & fitness/coaching-style consumer subscription apps in 2025-2026 cluster tightly around $9.99-$19.99/month and $59.99-$179.99/year for single-app, video/audio-driven coaching products; instrument-learning apps (Yousician, Trala, Simply Piano/Guitar) sit at the same corridor and are the most functionally relevant comps for Ostinato since they already do real-time on-device audio/pitch analysis at commercial scale. Two real family-bundle precedents exist with very different economics: Down Dog bundles all 6 of its apps for $39.99/yr (a near-giveaway retention play, cheaper than one single-app annual plan), while JoyTunes' Simply family bundles 4 apps + 5 profiles for $209.90/yr, only ~1.24x its own single-app annual price — the latter is the healthier model to emulate if Yula Motion ever cross-sells. RevenueCat's State of Subscription Apps data (surfaced here via a secondary synthesis, so treat exact numbers as directional pending primary-source confirmation) shows Health & Fitness monthly/annual price medians around $9.70/mo and $39.99/yr, hard-paywall models converting roughly 5x better than freemium at D35 (12.1% vs 2.2%), annual subscribers retaining far better than monthly (44.1% vs 17.5% at 12 months), and trial-to-paid conversion strongly rewarding longer trials (25.5% for ≤4-day trials vs 42.5% for 17-32 day trials) — directly arguing against short trials for a measure-improve loop product where the value (visible skill progress) only becomes obvious after several sessions. GOWOD's paywall pattern — full assessment/quiz completed BEFORE the paywall, then a 14-day trial offer with annual marked "best value" — is the closest analog to what a measure-improve coaching loop should do: let the user see their own baseline measurement (handstand attempt, mobility score, first shadow-boxing round, first note played, first dance move scored) before asking for payment, rather than a hard Day-0 paywall. Hardware-anchored (FightCamp $39/mo) and hybrid-human (Future $149-199/mo) comps mark ceilings that are architecturally irrelevant to Yula Motion's on-device, no-human-in-loop, single-phone-camera constraint and should not be used to justify premium pricing.

## RECOMMENDATIONS
- Price each of the 5 apps independently in the $9.99-$14.99/month, $59.99-$89.99/year corridor at launch — this matches the Health & Fitness category median (RevenueCat: ~$9.70/mo, ~$39.99/yr median, but coaching-specific comps like GOWOD/Bend/Down Dog single-app cluster higher at $9.99-14.99/$39.99-89.99) and avoids anchoring too close to Pliability/Yousician Premium+ ($20+/mo) before any app has proven retention.
- Do NOT build a cross-app Yula Motion family bundle at launch. Ship each app as an independent, standalone subscription first (no shared account/billing infrastructure cost, no cannibalization risk while none of the 5 apps has proven product-market fit). Revisit bundling only after 2+ apps have real retention data — and if/when you do, follow the Simply Piano/Guitar model (bundle ≈1.1-1.3x a single app's annual price, not Down Dog's near-giveaway ratio) so the bundle doesn't devalue the individual apps.
- Use a 7-day free trial as the default (matches Bend, GOWOD, STEEZY, Trala, Pliability — the near-universal norm in this comp set), but seriously consider extending toward the 14-32 day range GOWOD/Simply/STEEZY-partner-promo use, since RevenueCat data shows trial-to-paid conversion nearly doubles for 17-32 day trials vs ≤4-day trials — a measure-improve product especially benefits from a longer runway because visible skill improvement (better handstand hold, wider split, cleaner jab, first recognizable tune, first synced dance combo) typically needs more than one week to show.
- Adopt GOWOD's paywall placement pattern for all 5 apps: run the FULL assessment/baseline-measurement flow (first movement analysis, first mobility test, first shadow-boxing round scored, first note/rhythm check, first dance-move score) BEFORE showing the paywall — a 'usage/value-gated' soft paywall rather than a hard Day-0 paywall. This aligns with the core promise (real-time on-device coaching) by letting the user experience the coaching loop's value proposition once, free, before asking for payment, and matches RevenueCat's finding that hard paywalls convert better in raw D35 numbers but assessment-gated soft paywalls fit better where the product's differentiator (accurate on-device measurement) needs to be demonstrated to be believed.
- Weight annual-plan promotion heavily in paywall design (roughly 60-70% of comps default-select or highlight annual as 'Best Value') since RevenueCat data shows annual subscribers retain far longer than monthly (44.1% vs 17.5% at 12 months) — critical for solo-founder apps without a large team to run constant reactivation/win-back campaigns.
- Treat FightCamp ($39/mo, hardware-anchored) and Future/Caliber-style hybrid-human coaching ($80-200/mo) as explicit NON-comps for pricing purposes — they carry cost structures (hardware, human labor) that Yula Motion's on-device-only architecture does not have, and pricing near them would be unjustified and likely hurt conversion.

## RISKS
- Every specific price figure in this research was gathered via WebSearch snippets/aggregator and review-site summaries, not primary vendor pricing pages fetched directly (except the Airbridge RevenueCat-secondary-source fetch) — prices are known to vary by platform (iOS App Store vs Android vs web, seen concretely in STEEZY's $99.99 vs $149.99 split) and by region/promo, so treat every number here as a corridor estimate, not an exact current price, and re-verify on the vendor's own pricing page before finalizing Yula Motion's own price points.
- The RevenueCat conversion/retention percentages (trial-to-paid 39.9%/68.3%, hard-paywall-vs-freemium 12.1%/2.2%, annual-vs-monthly retention 44.1%/17.5%) were read via a third-party blog (Airbridge) synthesizing RevenueCat's report rather than fetched directly from revenuecat.com — there is real risk of transcription/interpretation error in that secondary source; before citing these numbers externally (investor deck, etc.), fetch revenuecat.com/state-of-subscription-apps directly and cross-check.
- No genuinely comparable 'AI on-device movement-coaching' app (the exact category Gravita/JabLab occupy) was found in the search results — all closest comps are either video-instruction apps (Down Dog, STEEZY, Bend, GOWOD, Pliability, which do NOT do real-time on-device pose analysis) or audio/pitch-detection apps (Yousician, Trala, Simply Piano/Guitar, which solve a different sensing problem than camera-based pose estimation). Pricing conclusions are therefore extrapolated across adjacent categories, not drawn from a direct precedent — genuine uncertainty remains about whether users will pay coaching-app prices for a product whose core tech (on-device pose/form analysis) is less market-proven than pitch-detection.
- No solo-founder-scale, 5-camera-vision-app-portfolio precedent was found — Down Dog and Simply/JoyTunes are the two multi-app family examples, but both are venture-scale companies with dedicated teams per app, not evidence for how a family of 5 solo/near-solo-founder apps should be priced or bundled.

## ITEMS (name | license | on_device | url)
### RevenueCat — State of Subscription Apps 2025/2026
- what: Annual benchmark report analyzing subscription data from 30,000+ apps / 100k+ apps (2025 ed. covers 2024 data; 2026 ed. released covering 2025 data), broken out by category including Health & Fitness.
- why: The single authoritative source for trial-to-paid, download-to-paid, price-tier conversion, and retention-by-billing-period benchmarks that our 5 apps should be pricing against.
- license: N/A
- maturity: Industry-standard annual report, 6th+ edition, widely cited
- on_device: N/A — data/report, not SDK
- integration: N/A (reference only); RevenueCat itself is a plausible IAP-abstraction SDK for the 5 apps' billing layer (cross-platform StoreKit2/Play Billing wrapper)
- caveats: Some cited figures (e.g. 'trial-to-paid 39.9% median / 68.3% top decile for Health&Fitness', 'annual retention 44.1% vs monthly 17.5%', 'hard paywall 12.1% vs freemium 2.2% D35 conversion') came via a secondary source (Airbridge blog synthesizing RevenueCat data) rather than being read directly off 
- url: https://www.revenuecat.com/state-of-subscription-apps
### Down Dog (yoga/HIIT/barre/pilates family)
- what: Category-leading yoga app family; each discipline (Yoga, HIIT, Barre, Pilates, Prenatal, Meditation) is a separate app store listing under one shared account model.
- why: Only major precedent among the comps for a MULTI-APP FAMILY pricing model — directly relevant to whether Yula Motion should sell 5 apps separately or as a bundle.
- license: N/A
- maturity: Long-running (10+ yrs), high App Store ratings, industry-standard reference app
- on_device: N/A (video-based, not camera-vision)
- integration: N/A — pricing/business-model reference only
- caveats: $9.99/mo, $59.99/yr per single app (per apps app store & review sites); separately, an 'all-access' bundle across all 6 apps is offered on the Down Dog WEBSITE at $39.99/yr — notably CHEAPER than a single app's annual price, i.e. the bundle is a loss-leader/retention play, not a premium multiplier. 
- url: https://apps.apple.com/us/app/yoga-down-dog/id983693694
### Pliability (formerly ROMWOD)
- what: Stretching/mobility/recovery video-program app aimed at athletes.
- why: Comparable to Lissom (mobility/flexibility) on pricing tier and trial design; sits at the premium end of the mobility category.
- license: N/A
- maturity: Established (ex-ROMWOD rebrand), broad app store presence
- on_device: N/A
- integration: N/A — reference only
- caveats: Price varies by source: $19.99/mo & $179.99/yr per one listing (Athlete plan); another source states $17.95/mo or $179/yr; a third cites a lower $14.99/mo-equivalent annual rate. Treat $15–20/mo, ~$180/yr as the corridor. 7-day free trial confirmed across sources.
- url: https://pliability.com/stories/gowod-vs-pliability
### GOWOD
- what: Personalized mobility/stretching app with a sport-specific assessment quiz driving program personalization.
- why: Closest functional analog to Lissom's 'assessment → daily program' loop, including its onboarding paywall placement pattern.
- license: N/A
- maturity: Established EU-origin app, cited in Adapty's paywall showcase library
- on_device: N/A
- integration: N/A — reference only
- caveats: ~$14.99/mo or ~$89.99/yr (promotional pricing fluctuates). Paywall design is directly useful: SOFT/assessment-gated placement — the mobility quiz + assessment runs fully BEFORE the paywall, and the paywall itself offers a 14-day trial on both monthly/annual with annual marked 'Best Value' (~25% off)
- url: https://www.gowod.app/pricing
### STEEZY Studio
- what: Learn-to-dance video class platform (structured curricula + freestyle) with app + web.
- why: Direct comp for Choreia (learn-to-dance) on price point, trial length, and annual-vs-monthly spread.
- license: N/A
- maturity: Well-established (10+ yrs), large content library (750+ classes)
- on_device: N/A (video content, not motion-tracking)
- integration: N/A — reference only
- caveats: Pricing is inconsistent across sources/platforms: web ~$149.99/yr vs iOS App Store ~$99.99/yr (classic case of platform-specific IAP pricing divergence — worth planning for in our own App Store vs Play vs web pricing). Monthly ~$20 (annual works out to ~$8.33/mo equivalent). 7-day free trial confirm
- url: https://steezy.zendesk.com/hc/en-us/articles/360052236032-How-much-does-STEEZY-Studio-cost
### Yousician
- what: Gamified instrument-learning app (guitar, piano, voice, bass, ukulele) using real-time audio pitch/rhythm detection to give feedback — the closest functional analog in the comp set to Ostinato's mic-based practice-coaching loop.
- why: Most important comp for Ostinato: it already runs on-device real-time audio analysis for technique feedback, has a tiered pricing ladder (Premium / Premium+ / Family), and predates 'AI coaching' branding.
- license: N/A
- maturity: Category leader, 10+ years, tens of millions of installs, multi-instrument
- on_device: Uses real-time pitch/audio detection (analogous problem to Ostinato's cello bowing/pitch detection) — strong signal that on-device audio-analysis coaching is commercially proven at scale
- integration: N/A — reference only for pricing/tiering; NOT a technical dependency
- caveats: Three-tier structure found: Premium $14.99/mo or $89.99/yr; Premium+ $19.99/mo or $139.99/yr (adds premium song catalog/personalized plans); Premium+ Family $29.99/mo or $209.99/yr for up to 4 members. This is the clearest FAMILY-PLAN precedent in the set (multiplier ≈1.5x the individual annual pric
- url: https://subger.com/en/service/yousician
### Trala
- what: Violin-learning app with real-time pitch feedback, freemium content gate (scales/beginner pieces free, full catalog paywalled).
- why: Smaller/newer analog to Ostinato — same instrument-practice-coach category, freemium+metered paywall pattern rather than hard trial gate.
- license: N/A
- maturity: Smaller player, less data availability than Yousician/Simply — earlier-stage app
- on_device: Real-time pitch/audio feedback (on-device audio analysis) analogous to Ostinato's needs
- integration: N/A — reference only
- caveats: $9.99/mo or $119.99/yr — notably the annual price is HIGHER per-month-equivalent-adjacent than typical (annual ≈ $10/mo, i.e. little to no annual discount vs monthly, which is unusual in this category and may indicate weaker annual-conversion incentive design). 7-day free trial. Content-gated freemi
- url: https://apps.apple.com/us/app/trala-learn-violin/id1143205265
### Simply Piano / Simply Guitar (Simply family, JoyTunes)
- what: Instrument-learning app family (Piano, Guitar, Sing, Draw) from one publisher (JoyTunes) sharing a unified Family plan across all four apps.
- why: Second strong multi-app FAMILY BUNDLE precedent (alongside Down Dog) — directly informs whether Yula Motion's 5 apps should ever cross-sell a bundle, and shows a real per-seat/per-app family pricing structure (not a loss-leader like Down Dog's).
- license: N/A
- maturity: Category leader (JoyTunes), long track record, high production value
- on_device: Uses real-time audio/pitch detection similar to Yousician/Trala/Ostinato's needs
- integration: N/A — reference only
- caveats: Individual plan $17.90/mo or $169.90/yr; Family plan (5 profiles, ALL 4 apps: Piano+Guitar+Sing+Draw) $23.90/mo or $209.90/yr — i.e. family bundle ≈1.24x the individual annual price for 5 seats + full catalog, a much richer bundle-to-single ratio than Down Dog's near-giveaway bundle. Both plans incl
- url: https://piano-help.hellosimply.com/en/articles/5912097-subscribe-to-simply-guitar
### FightCamp (companion/connected-equipment app)
- what: Boxing/kickboxing app tied to at-home connected punch-tracking equipment (bag + wearable trackers), not a pure-software play.
- why: Weak comp for JabLab specifically BECAUSE it is hardware-anchored — shows the ceiling price ($39/mo) that hardware-bundled fitness subscriptions can command, which is NOT representative of a pure-software, phone-camera-only shadow-boxing coach like J
- license: N/A
- maturity: Funded (~$90M raise reported 2021), established hardware+software category player
- on_device: N/A — uses proprietary hardware trackers + bag sensors, not phone-camera computer vision
- integration: N/A — not architecturally comparable to JabLab (single-phone-camera, no hardware)
- caveats: $39/mo cited by most sources (one source cites a $51 'starting price' — likely reflects a different bundle/region/promo, unreconciled). This price is propped up by hardware lock-in and should NOT be read as a norm for pure-app boxing coaching — it would badly mis-anchor JabLab's pricing if used dire
- url: https://www.garagegymreviews.com/fightcamp-review
### Hybrid AI+human fitness coaching apps (Future, Caliber Plus, and similar)
- what: Category of apps pairing an AI/algorithmic layer with a real human coach relationship (workout programming + check-ins), positioned above pure-AI apps and below in-person personal training.
- why: Establishes the OUTER price ceiling for 'coach-in-your-pocket' framing — useful contrast for Yula Motion's pure-AI/no-human-in-loop positioning, since our apps should price below this tier, not compete with it.
- license: N/A
- maturity: Mixed — several are VC-funded (Future reportedly $149-199/mo), aimed at premium/willing-to-pay segment
- on_device: N/A — these route data to human coaches, i.e. NOT on-device/privacy-first architecture; directly disqualified under our raw-video-never-leaves-device constraint
- integration: N/A — not architecturally relevant (they are cloud-based with human review), but pricing ceiling is a useful anchor
- caveats: Figures ($149-199/mo for Future; $40-90/mo for Caliber coaching tier; $80-150/mo generic 'hybrid' range) come from aggregator/roundup blog content, not verified against the vendors' own pricing pages in this pass — flag as low-confidence, illustrative-of-ceiling only, not to be cited as hard fact.
- url: https://www.rayfit.com/blog/2026/02/best-ai-personal-trainer-app/
