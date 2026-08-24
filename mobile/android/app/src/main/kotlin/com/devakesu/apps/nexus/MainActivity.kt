package com.devakesu.apps.nexus

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.MotionEvent
import android.content.Context
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.spotify.sdk.android.auth.AuthorizationClient
import com.spotify.sdk.android.auth.AuthorizationRequest
import com.spotify.sdk.android.auth.AuthorizationResponse
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.devakesu.apps.nexus/spotify_auth"
        const val SPOTIFY_REQUEST_CODE = 0x5B01

        const val SAFETY_CHANNEL = "com.devakesu.apps.nexus/safety"
        const val CALL_PERMISSION_REQUEST_CODE = 0x5B02

        const val SECURITY_CHANNEL = "com.devakesu.apps.nexus/security"
    }

    private var pendingSpotifyResult: MethodChannel.Result? = null

    // Meetup Safety direct-dial: a CALL_PHONE permission request has to round
    // -trip through onRequestPermissionsResult, so the pending MethodChannel
    // result and the number to dial are held here in the meantime.
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingCallNumber: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val isSafetyCheckinLaunch = intent?.getStringExtra("payload") == "meetup_safety_checkin_due"
        setShowWhenLockedCompat(isSafetyCheckinLaunch)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val isSafetyCheckinLaunch = intent.getStringExtra("payload") == "meetup_safety_checkin_due"
        if (isSafetyCheckinLaunch) {
            setShowWhenLockedCompat(true)
        }
    }

    private fun setShowWhenLockedCompat(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(show)
            setTurnScreenOn(show)
        } else {
            @Suppress("DEPRECATION")
            if (show) {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            } else {
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
        }
    }

    private fun isScreenBeingRecordedOrMirrored(): Boolean {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return false
        val displays = displayManager.displays
        for (display in displays) {
            if (display.displayId != Display.DEFAULT_DISPLAY) {
                val flags = display.flags
                val isPresentation = (flags and DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION) != 0
                val isAutoMirror = (flags and DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR) != 0
                val isPublic = (flags and DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC) != 0
                if (isPresentation || isAutoMirror || isPublic) {
                    return true
                }
            }
        }
        return false
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val isObscured = (event.flags and MotionEvent.FLAG_WINDOW_IS_OBSCURED) != 0 ||
                (event.flags and MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED) != 0
        if (isObscured) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, SECURITY_CHANNEL).invokeMethod("onOverlayDetected", null)
            }
        }
        return super.dispatchTouchEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connectSpotify" -> {
                        val clientId = call.argument<String>("clientId").orEmpty()
                        val redirectUri = call.argument<String>("redirectUri").orEmpty()
                        launchSpotifyAuth(clientId, redirectUri, result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDebuggerConnected" -> {
                        val connected = android.os.Debug.isDebuggerConnected() ||
                            android.os.Debug.waitingForDebugger() ||
                            isTraced()
                        result.success(connected)
                    }
                    "setSecureFlag" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "isScreenRecordingOrMirroring" -> {
                        result.success(isScreenBeingRecordedOrMirrored())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAFETY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setShowWhenLocked" -> {
                        val show = call.argument<Boolean>("show") ?: false
                        setShowWhenLockedCompat(show)
                        result.success(null)
                    }
                    "startRecording" -> {
                        // A native crash right as Silent SOS activates would be the
                        // one moment this app can least afford to fail silently -
                        // e.g. ForegroundServiceStartNotAllowedException on API 31+
                        // if the OS decides the app isn't eligible to start one.
                        try {
                            startForegroundService(Intent(this, SafetyRecordingService::class.java))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("FOREGROUND_SERVICE_START_FAILED", e.message, null)
                        }
                    }
                    "stopRecording" -> {
                        try {
                            stopService(Intent(this, SafetyRecordingService::class.java))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("FOREGROUND_SERVICE_STOP_FAILED", e.message, null)
                        }
                    }
                    "callDirect" -> {
                        val number = call.argument<String>("number").orEmpty()
                        if (number.isEmpty()) {
                            result.error("INVALID_NUMBER", "number is missing", null)
                        } else {
                            callDirect(number, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // --- Meetup Safety direct-dial (Android only - iOS never allows any
    // third-party app to place a call without its own system confirmation
    // prompt, so there's no equivalent on that platform) ---

    private fun callDirect(number: String, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            placeCall(number)
            result.success(true)
            return
        }

        // If a previous request is still pending (e.g. a rapid double-tap
        // before the system permission dialog appeared), resolve it now
        // instead of silently dropping its Result and leaving that caller's
        // Dart Future to hang forever - MethodChannel.Result must be
        // completed exactly once.
        pendingCallResult?.success(false)
        pendingCallResult = result
        pendingCallNumber = number
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CALL_PHONE),
            CALL_PERMISSION_REQUEST_CODE,
        )
    }

    private fun placeCall(number: String) {
        startActivity(
            Intent(Intent.ACTION_CALL, Uri.parse("tel:$number")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALL_PERMISSION_REQUEST_CODE) return

        val result = pendingCallResult
        val number = pendingCallNumber
        pendingCallResult = null
        pendingCallNumber = null

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted && number != null) {
            placeCall(number)
        }
        // A false result tells the Dart side to fall back to the
        // dialer-prefill flow (e.g. permission denied).
        result?.success(granted)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(NotificationManager::class.java) ?: return

        // Channel groups
        nm.createNotificationChannelGroups(
            listOf(
                NotificationChannelGroup("likes", "Likes"),
                NotificationChannelGroup("matches", "Matches"),
                NotificationChannelGroup("chats", "Chats"),
                NotificationChannelGroup("safety", "Meetup Safety"),
            )
        )

        nm.createNotificationChannels(
            listOf(
                NotificationChannel(
                    "likes_like",
                    "Likes",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "When someone likes you"
                    group = "likes"
                },
                NotificationChannel(
                    "likes_superlike",
                    "Super Likes",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "When someone super likes you"
                    group = "likes"
                },
                NotificationChannel(
                    "matches_new",
                    "New Matches",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "When you get a new match"
                    group = "matches"
                },
                NotificationChannel(
                    "chat_message",
                    "Chats",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "When you receive a new chat message"
                    group = "chats"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
                NotificationChannel(
                    "chat_event_reminder",
                    "Reminders",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "When a planned meetup is coming up"
                    group = "chats"
                },
                NotificationChannel(
                    "meetup_safety_ongoing",
                    "Meetup Safety (active)",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "The persistent alert panel shown while a Meetup Safety check-in is active"
                    group = "safety"
                },
                NotificationChannel(
                    "meetup_safety_checkin",
                    "Meetup Safety check-in",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alerts you when it's time to check in during Meetup Safety"
                    group = "safety"
                },
                NotificationChannel(
                    "safety_contact_removed",
                    "Trusted Contacts",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alerts you when a trusted contact is removed"
                    group = "safety"
                },
                NotificationChannel(
                    "meetup_safety_reminder",
                    "Check-in Reminders",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Nudges you to configure or start your check-in"
                    group = "safety"
                },
                NotificationChannel(
                    "safety_recording",
                    "Meetup Safety recording",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while Silent SOS is recording evidence."
                    group = "safety"
                },
            )
        )
    }

    private fun launchSpotifyAuth(
        clientId: String,
        redirectUri: String,
        result: MethodChannel.Result,
    ) {
        if (clientId.isEmpty() || redirectUri.isEmpty()) {
            result.error("INVALID_CONFIG", "clientId or redirectUri is missing", null)
            return
        }
        pendingSpotifyResult = result

        val request = AuthorizationRequest
            .Builder(clientId, AuthorizationResponse.Type.CODE, redirectUri)
            .setScopes(
                arrayOf(
                    "user-top-read",
                    "playlist-read-private",
                    "playlist-read-collaborative",
                ),
            )
            .build()

        // If the Spotify app is installed, this opens a native one-tap approval overlay.
        // Otherwise it falls back to Chrome Custom Tabs. We use Authorization Code (not
        // Implicit Grant) because Spotify deprecated response_type=token.
        AuthorizationClient.openLoginActivity(this, SPOTIFY_REQUEST_CODE, request)
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SPOTIFY_REQUEST_CODE) return

        val pending = pendingSpotifyResult ?: return
        pendingSpotifyResult = null

        val response = AuthorizationClient.getResponse(resultCode, data)
        when (response.type) {
            AuthorizationResponse.Type.CODE ->
                pending.success(response.code)
            AuthorizationResponse.Type.ERROR ->
                pending.error("SPOTIFY_AUTH_ERROR", response.error ?: "Unknown error", null)
            else ->
                pending.error("SPOTIFY_AUTH_CANCELLED", "User cancelled", null)
        }
    }

    private fun isTraced(): Boolean {
        return try {
            val statusFile = java.io.File("/proc/self/status")
            if (statusFile.exists()) {
                val reader = java.io.BufferedReader(java.io.FileReader(statusFile))
                var line: String?
                var traced = false
                while (reader.readLine().also { line = it } != null) {
                    if (line?.startsWith("TracerPid:") == true) {
                        val pid = line!!.substringAfter("TracerPid:").trim().toIntOrNull() ?: 0
                        if (pid > 0) {
                            traced = true
                            break
                        }
                    }
                }
                reader.close()
                traced
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }
}
