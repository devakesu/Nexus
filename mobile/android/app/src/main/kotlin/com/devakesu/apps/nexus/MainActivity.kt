package com.devakesu.apps.nexus

import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
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
    }

    private var pendingSpotifyResult: MethodChannel.Result? = null

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
            .setScopes(arrayOf("user-top-read"))
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
