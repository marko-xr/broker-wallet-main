package com.example.broker_wallet

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Tells the Dart Scanner when the document scanner's pending result was lost.
 *
 * flutter_doc_scanner (0.0.21) keeps the reply to the Dart call in a field and
 * sets that field to null, without answering it, in onDetachedFromActivity() —
 * which onDetachedFromActivityForConfigChanges() also calls. If the Activity
 * detaches while the scanner is open and the Flutter engine survives (a
 * configuration change MainActivity does not handle itself), the scanner's
 * answer arrives to a plugin with nothing to reply to, and the Dart call never
 * completes. This listener sees the same detach callbacks, and only while Dart
 * says a scan is being watched ("begin" … "end") it reports "scanAbandoned"
 * once. It reports a lost result, never elapsed time: a slow scan or one in the
 * background is not touched. It does not read, reply to or alter the plugin.
 *
 * When the Activity and its engine are destroyed together, Dart is gone too and
 * the app starts afresh, so nothing is left waiting and nothing is reported.
 */
class ScanLifecycleGuard : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.example.broker_wallet/scan_lifecycle"
    }

    private var channel: MethodChannel? = null
    private var watching = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        watching = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "begin" -> {
                watching = true
                result.success(null)
            }
            "end" -> {
                watching = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivityForConfigChanges() {
        reportIfWatching()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {
        reportIfWatching()
    }

    private fun reportIfWatching() {
        if (!watching) return
        watching = false
        channel?.invokeMethod("scanAbandoned", null)
    }
}
