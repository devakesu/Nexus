package com.devakesu.apps.nexus

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
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
    }

    private var pendingSpotifyResult: MethodChannel.Result? = null

    // Meetup Safety direct-dial: a CALL_PHONE permission request has to round
    // -trip through onRequestPermissionsResult, so the pending MethodChannel
    // result and the number to dial are held here in the meantime.
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingCallNumber: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // showWhenLocked/turnScreenOn in AndroidManifest.xml cover API 27+;
        // pre-27 devices need the equivalent window flags set here so the
        // Meetup Safety check-in alert still launches over the lock screen.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAFETY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
}
