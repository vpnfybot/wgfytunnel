package com.example.wgfytunnel

import android.app.PendingIntent
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import com.wireguard.android.backend.Tunnel
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class WireGuardNotificationService : Service() {
    companion object {
        private const val ACTION_START = "com.example.wgfytunnel.action.START_WIREGUARD_NOTIFICATION"
        private const val ACTION_STOP = "com.example.wgfytunnel.action.STOP_WIREGUARD_NOTIFICATION"
        private const val ACTION_RESTORE = "com.example.wgfytunnel.action.RESTORE_WIREGUARD_NOTIFICATION"
        private const val EXTRA_CONNECTED_AT = "connected_at"
        private const val NOTIFICATION_ID = 1003

        fun start(context: Context, connectedAtElapsedRealtime: Long) {
            val intent = Intent(context, WireGuardNotificationService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CONNECTED_AT, connectedAtElapsedRealtime)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            runCatching {
                context.startService(
                    Intent(context, WireGuardNotificationService::class.java).apply {
                        action = ACTION_STOP
                    },
                )
            }
        }
    }

    private val executor = Executors.newSingleThreadScheduledExecutor()
    private var updateTask: ScheduledFuture<*>? = null
    private var connectedAtElapsedRealtime: Long = 0L

    override fun onCreate() {
        super.onCreate()
        WireGuardRuntime.initialize(applicationContext)
        TunnelNotificationSupport.ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                WireGuardRuntime.connectedAtElapsedRealtime = null
                stopUpdates()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_RESTORE -> {
                if (WireGuardRuntime.connectedAtElapsedRealtime == null) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return START_NOT_STICKY
                }

                refreshNotification()
                scheduleUpdates()
                return START_STICKY
            }

            ACTION_START -> {
                connectedAtElapsedRealtime = intent.getLongExtra(
                    EXTRA_CONNECTED_AT,
                    WireGuardRuntime.connectedAtElapsedRealtime ?: SystemClock.elapsedRealtime(),
                )
                startInForeground()
                scheduleUpdates()
                return START_STICKY
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        stopUpdates()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startInForeground() {
        val notification = TunnelNotificationSupport.buildNotification(
            context = this,
            statusText = "Туннель подключен",
            elapsedMs = SystemClock.elapsedRealtime() - connectedAtElapsedRealtime,
            rxBytes = 0L,
            txBytes = 0L,
            deleteIntent = notificationDeleteIntent(),
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun scheduleUpdates() {
        if (updateTask != null) {
            return
        }

        updateTask = executor.scheduleAtFixedRate(
            { refreshNotification() },
            20L,
            20L,
            TimeUnit.SECONDS,
        )
    }

    private fun stopUpdates() {
        updateTask?.cancel(true)
        updateTask = null
    }

    private fun refreshNotification() {
        val notificationManager = getSystemService(NotificationManager::class.java) ?: return
        val tunnelState = runCatching {
            WireGuardRuntime.backend.getState(WireGuardRuntime.tunnel)
        }.getOrDefault(Tunnel.State.DOWN)

        if (tunnelState != Tunnel.State.UP) {
            WireGuardRuntime.connectedAtElapsedRealtime = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        val stats = runCatching {
            WireGuardRuntime.backend.getStatistics(WireGuardRuntime.tunnel)
        }.getOrNull()
        val connectedAt = WireGuardRuntime.connectedAtElapsedRealtime ?: connectedAtElapsedRealtime

        notificationManager.notify(
            NOTIFICATION_ID,
            TunnelNotificationSupport.buildNotification(
                context = this,
                statusText = "Туннель подключен",
                elapsedMs = SystemClock.elapsedRealtime() - connectedAt,
                rxBytes = stats?.totalRx() ?: 0L,
                txBytes = stats?.totalTx() ?: 0L,
                deleteIntent = notificationDeleteIntent(),
            ),
        )
    }

    private fun notificationDeleteIntent(): PendingIntent {
        val intent = Intent(this, WireGuardNotificationService::class.java).apply {
            action = ACTION_RESTORE
        }
        return PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}