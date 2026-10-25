import Flutter
import StoreKit
import UIKit

/// Store/platform signals for the Yula Motion family. Every method answers
/// nil when the platform API is unavailable; the Dart side keeps fallbacks.
public class MotionPlatformSignalsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.yulalab.motion_platform_signals",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(MotionPlatformSignalsPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "appTransactionId":
      appTransactionId(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// StoreKit 2 AppTransaction (iOS 16+); only a verified app transaction is
  /// returned. appTransactionID is back-deployed to iOS 16.
  private func appTransactionId(_ result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(nil)
      return
    }
    Task {
      do {
        let verification = try await AppTransaction.shared
        switch verification {
        case .verified(let transaction):
          let id = transaction.appTransactionID
          DispatchQueue.main.async { result(id) }
        case .unverified:
          DispatchQueue.main.async { result(nil) }
        }
      } catch {
        DispatchQueue.main.async { result(nil) }
      }
    }
  }
}
