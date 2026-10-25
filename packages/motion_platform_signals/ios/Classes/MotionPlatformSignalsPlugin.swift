import Flutter
import StoreKit
import UIKit

#if canImport(DeclaredAgeRange)
  import DeclaredAgeRange
#endif

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
    case "requestAgeSignal":
      let gates = ((call.arguments as? [String: Any])?["ageGates"] as? [Int]) ?? [13, 16, 18]
      requestAgeSignal(gates, result)
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

  /// Declared Age Range (iOS 26+). Any error (not available in the region,
  /// missing entitlement, invalid account, network) answers nil.
  private func requestAgeSignal(_ gates: [Int], _ result: @escaping FlutterResult) {
    #if canImport(DeclaredAgeRange)
      guard #available(iOS 26.0, *), !gates.isEmpty, gates.count <= 3 else {
        result(nil)
        return
      }
      Task { @MainActor in
        guard let controller = Self.topViewController() else {
          result(nil)
          return
        }
        do {
          let response = try await AgeRangeService.shared.requestAgeRange(
            ageGates: gates[0],
            gates.count > 1 ? gates[1] : nil,
            gates.count > 2 ? gates[2] : nil,
            in: controller)
          switch response {
          case .declinedSharing:
            result(["source": "apple", "shared": false])
          case .sharing(let range):
            result([
              "source": "apple",
              "shared": true,
              "lower": range.lowerBound.map { $0 as Any } ?? NSNull(),
              "upper": range.upperBound.map { $0 as Any } ?? NSNull(),
              "declaration": range.ageRangeDeclaration.map {
                String(describing: $0) as Any
              } ?? NSNull(),
            ])
          @unknown default:
            result(nil)
          }
        } catch {
          result(nil)
        }
      }
    #else
      result(nil)
    #endif
  }

  @MainActor
  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
