package com.yulalab.motion_platform_signals

import android.app.Activity
import com.google.android.play.agesignals.AgeSignalsAccessRequest
import com.google.android.play.agesignals.AgeSignalsManager
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.model.AgeSignalsStatus
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Store/platform signals for the Yula Motion family; null where unavailable. */
class MotionPlatformSignalsPlugin :
  FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private var channel: MethodChannel? = null
  private var activity: Activity? = null
  private var manager: AgeSignalsManager? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "com.yulalab.motion_platform_signals")
      .also { it.setMethodCallHandler(this) }
    manager = try {
      AgeSignalsManagerFactory.create(binding.applicationContext)
    } catch (_: Throwable) {
      null
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    manager = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      // The App Store app transaction has no Google Play equivalent.
      "appTransactionId" -> result.success(null)
      "requestAgeSignal" -> requestAgeSignal(result)
      else -> result.notImplemented()
    }
  }

  /**
   * Play Age Signals (0.0.4): ask for sharing access (Play may show its own
   * prompt), then read the range. Any failure answers null.
   */
  private fun requestAgeSignal(result: MethodChannel.Result) {
    val signals = manager
    val host = activity
    if (signals == null || host == null) {
      result.success(null)
      return
    }
    try {
      val access = AgeSignalsAccessRequest.builder().setActivity(host).build()
      signals.requestAgeSignalsAccess(access)
        .addOnSuccessListener { accessResult ->
          when (accessResult.ageSignalsStatus()) {
            AgeSignalsStatus.SHARED -> readAgeSignals(signals, result)
            AgeSignalsStatus.NOT_SHARED ->
              result.success(mapOf("source" to "google", "shared" to false))
            else -> result.success(null)
          }
        }
        .addOnFailureListener { result.success(null) }
    } catch (_: Throwable) {
      result.success(null)
    }
  }

  private fun readAgeSignals(signals: AgeSignalsManager, result: MethodChannel.Result) {
    signals.checkAgeSignals(AgeSignalsRequest.builder().build())
      .addOnSuccessListener { signal ->
        val lower = signal.ageLower()
        val upper = signal.ageUpper()
        // Both bounds null: the person is not sharing an age range.
        result.success(
          mapOf(
            "source" to "google",
            "shared" to (lower != null || upper != null),
            "lower" to lower,
            "upper" to upper,
          ),
        )
      }
      .addOnFailureListener { result.success(null) }
  }
}
