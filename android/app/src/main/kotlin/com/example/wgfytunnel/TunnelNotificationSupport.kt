package com.example.wgfytunnel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.text.format.Formatter

object TunnelNotificationSupport {
    const val CHANNEL_ID = "wgfytunnel_status"
    private const val CHANNEL_NAME = "wgfytunnel"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    fun buildNotification(
        context: Context,
        statusText: String,
        elapsedMs: Long,
        rxBytes: Long,
        txBytes: Long,
        deleteIntent: PendingIntent? = null,
    ): Notification {
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val uptimeText = formatDuration(elapsedMs)
        val trafficText = formatTrafficTotal(context, rxBytes + txBytes)
        val singleLineText = "$uptimeText / $trafficText"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setContentTitle(singleLineText)
            .setSmallIcon(R.drawable.ic_stat_vpnfy)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        deleteIntent?.let(builder::setDeleteIntent)

        val notification = builder.build()
        notification.contentView?.let { compactView ->
            notification.bigContentView = compactView
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                notification.headsUpContentView = compactView
            }
        }
        notification.flags = notification.flags or
            Notification.FLAG_ONGOING_EVENT or
            Notification.FLAG_NO_CLEAR or
            Notification.FLAG_FOREGROUND_SERVICE
        return notification
    }

    private fun formatDuration(elapsedMs: Long): String {
        val totalSeconds = (elapsedMs.coerceAtLeast(0L) / 1000L)
        val hours = totalSeconds / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L
        return String.format("%02d:%02d:%02d", hours, minutes, seconds)
    }

    private fun formatTrafficTotal(context: Context, totalBytes: Long): String {
        if (totalBytes <= 0L) {
            return "0"
        }

        return Formatter.formatFileSize(context, totalBytes)
    }
}