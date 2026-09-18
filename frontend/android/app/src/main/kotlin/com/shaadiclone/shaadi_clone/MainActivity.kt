package com.shaadiclone.shaadi_clone

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A plain FlutterActivity has no way to surface itself over a locked
// screen — WebSocket-delivered incoming calls were arriving fine while
// the phone was merely locked (screen off, app still alive), but the
// ringing UI never actually appeared: nothing told Android this activity
// should draw over the keyguard or wake the screen, so the call just sat
// there until the user happened to unlock and open the app manually,
// which was usually well past the 30s ring window. showCallUi (invoked
// from IncomingCallScreen the moment it mounts) is the fix — it's a
// one-way call, no result expected, so no MethodChannel.Result handling.
class MainActivity : FlutterActivity() {
    private val channel = "com.vivaha.app/call_ui"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "showCallUi" -> {
                    showOverLockScreen()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }
}
