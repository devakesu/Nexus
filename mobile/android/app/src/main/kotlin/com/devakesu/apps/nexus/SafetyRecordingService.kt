package com.devakesu.apps.nexus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * A minimal foreground service whose only job is to keep this app's process
 * alive (and clearly, visibly flagged as recording) while Silent SOS's
 * Digital Witness capture is running and the user backgrounds the app or
 * locks the screen. The actual camera/mic recording is driven entirely by
 * the `camera` Flutter plugin in the Dart/Flutter engine - this service
 * doesn't touch the camera itself, it just prevents Android from killing or
 * deprioritizing the process the way it would an ordinary backgrounded app.
 *
 * The persistent notification this posts is not incidental: it's the whole
 * point. Android will not let any app hide that a foreground service (let
 * alone one of type camera/microphone) is running, and Silent SOS is
 * designed to be an overt, in-the-open recording rather than covert
 * surveillance - see the Meetup Safety plan's Milestone C notes.
 */
class SafetyRecordingService : Service() {

    private companion object {
        const val CHANNEL_ID = "safety_recording"
        const val NOTIFICATION_ID = 9101
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification(), foregroundServiceType())
        return START_STICKY
    }

    private fun foregroundServiceType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        } else {
            0
        }
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Meetup Safety recording",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while Silent SOS is recording evidence."
                },
            )
        }

        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Recording emergency evidence")
            .setContentText("Silent SOS is recording video and audio. Tap to open Nexus.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
