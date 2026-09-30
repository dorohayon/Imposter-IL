package com.imposteril.app

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // A real vibration for game moments (lib/state/buzz.dart). Flutter's
    // haptics are a keyboard tick here, which is faint and does nothing at all
    // when the phone's touch feedback is off.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "imposter/vibrate")
            .setMethodCallHandler { call, result ->
                if (call.method == "vibrate") {
                    vibrate(((call.arguments as? Int) ?: 150).toLong())
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun vibrate(millis: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createOneShot(millis, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(millis)
        }
    }
}
