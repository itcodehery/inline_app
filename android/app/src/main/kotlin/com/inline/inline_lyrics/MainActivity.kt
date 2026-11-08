package com.inline.inline_lyrics

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.inline.lyrics/media_control"
    private val EVENT_CHANNEL = "com.inline.lyrics/media_events"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasNotificationPermission" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }
                "hasOverlayPermission" -> {
                    result.success(canDrawOverlays())
                }
                "openOverlaySettings" -> {
                    openOverlaySettings()
                    result.success(true)
                }
                "showOverlay" -> {
                    try {
                        val intent = Intent(this, InlineFloatingService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OVERLAY_START_FAILED", e.message, null)
                    }
                }
                "closeOverlay" -> {
                    try {
                        val intent = Intent(this, InlineFloatingService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OVERLAY_STOP_FAILED", e.message, null)
                    }
                }
                "isOverlayActive" -> {
                    result.success(InlineFloatingService.isRunning)
                }
                "updateOverlayLyric" -> {
                    val text = call.argument<String>("text") ?: ""
                    val isSynced = call.argument<Boolean>("isSynced") ?: false
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    val fontSize = call.argument<Double>("fontSize")?.toFloat() ?: 14.5f
                    val transitionStyle = call.argument<String>("transitionStyle") ?: "slide"
                    val chipStyle = call.argument<String>("chipStyle") ?: "pill"
                    val accentColor = call.argument<String>("accentColor") ?: "#D4FF70"
                    val nextLyricText = call.argument<String>("nextLyricText") ?: ""
                    val trackTitle = call.argument<String>("trackTitle") ?: ""
                    val artistName = call.argument<String>("artistName") ?: ""
                    InlineFloatingService.updateLyricText(
                        text,
                        isSynced,
                        isPlaying,
                        fontSize,
                        transitionStyle,
                        chipStyle,
                        accentColor,
                        nextLyricText,
                        trackTitle,
                        artistName
                    )
                    result.success(true)
                }
                "checkActiveTrack" -> {
                    InlineNotificationListener.requestRefresh(this)
                    result.success(true)
                }
                "sendMediaAction" -> {
                    val action = call.argument<String>("action") ?: "toggle"
                    InlineNotificationListener.sendMediaAction(action)
                    result.success(true)
                }
                "setOverlayOpacity" -> {
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 1.0f
                    InlineFloatingService.setOpacity(opacity)
                    result.success(true)
                }
                "setTimingOffset" -> {
                    val offsetMs = call.argument<Int>("offsetMs") ?: 0
                    InlineFloatingService.currentTimingOffsetMs = offsetMs
                    result.success(true)
                }
                "setAutoHideWhenPaused" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    InlineFloatingService.autoHideWhenPaused = enabled
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        InlineFloatingService.onOffsetChanged = { newOffset ->
            runOnUiThread {
                channel.invokeMethod("onTimingOffsetChanged", mapOf("offsetMs" to newOffset))
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    InlineNotificationListener.onTrackChanged = { trackMap ->
                        runOnUiThread {
                            try {
                                eventSink?.success(trackMap)
                            } catch (_: Exception) {}
                        }
                    }
                    InlineNotificationListener.requestRefresh(this@MainActivity)
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    InlineNotificationListener.onTrackChanged = null
                }
            }
        )
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(packageName)
    }

    private fun canDrawOverlays(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (Settings.canDrawOverlays(this)) {
                return true
            }

            // Fallback for Motorola / MIUI / ColorOS where canDrawOverlays can be out-of-sync
            try {
                val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                val mode = appOps?.checkOpNoThrow(
                    AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                    Process.myUid(),
                    packageName
                )
                return mode == AppOpsManager.MODE_ALLOWED
            } catch (_: Exception) {}
            return false
        }
        return true
    }

    private fun openNotificationSettings() {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {}
    }

    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                // Direct standard Intent for "Display over other apps" list
                val genericIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(genericIntent)
                return
            } catch (_: Exception) {}

            try {
                val appDetailsIntent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(appDetailsIntent)
            } catch (_: Exception) {}
        }
    }

    override fun onResume() {
        super.onResume()
        InlineNotificationListener.requestRefresh(this)
    }
}
