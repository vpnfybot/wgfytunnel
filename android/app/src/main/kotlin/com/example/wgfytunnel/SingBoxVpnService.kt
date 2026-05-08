package com.example.wgfytunnel

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import libcore.BoxInstance
import libcore.Libcore
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class SingBoxVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.example.wgfytunnel.action.START_SINGBOX"
        const val ACTION_STOP = "com.example.wgfytunnel.action.STOP_SINGBOX"
        const val ACTION_RESTORE_NOTIFICATION = "com.example.wgfytunnel.action.RESTORE_SINGBOX_NOTIFICATION"
        const val EXTRA_CONFIG_JSON = "config_json"
        const val EXTRA_SPLIT_MODE = "split_mode"
        const val EXTRA_SELECTED_PACKAGES = "selected_packages"

        private const val NOTIFICATION_ID = 1002

        @Volatile
        var isActive: Boolean = false
            private set
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var boxInstance: BoxInstance? = null
    private var tunInterface: ParcelFileDescriptor? = null
    private var splitMode: SplitTunnelMode = SplitTunnelMode.ALL
    private var selectedPackages: Set<String> = emptySet()
    private val notificationExecutor = Executors.newSingleThreadScheduledExecutor()
    private var notificationUpdateTask: ScheduledFuture<*>? = null
    private var connectedAtElapsedRealtime: Long? = null
    private var notificationRxTotal: Long = 0L
    private var notificationTxTotal: Long = 0L

    override fun onCreate() {
        super.onCreate()
        trace("SingBoxVpnService.onCreate")
        LibcoreBridge.currentVpnService = this
        TunnelNotificationSupport.ensureChannel(this)
        trace("SingBoxVpnService.onCreate completed")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START) {
            clearTrace()
            SingBoxRuntimeState.reset(this)
        }
        trace("onStartCommand action=${intent?.action} startId=$startId flags=$flags")
        when (intent?.action) {
            ACTION_STOP -> {
                executor.execute {
                    trace("Processing ACTION_STOP")
                    stopBox()
                    SingBoxRuntimeState.stopped(this)
                    stopSelf()
                }
                return START_NOT_STICKY
            }

            ACTION_RESTORE_NOTIFICATION -> {
                if (!isActive) {
                    stopSelf()
                    return START_NOT_STICKY
                }

                startForegroundNotification(buildTunnelNotification("Туннель подключен"))
                return START_STICKY
            }

            ACTION_START -> {
                val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                if (configJson.isNullOrBlank()) {
                    SingBoxRuntimeState.failed(this, "Конфигурация sing-box не передана")
                    LibcoreBridge.startController.failed("Конфигурация sing-box не передана")
                    stopSelf()
                    return START_NOT_STICKY
                }

                splitMode = SplitTunnelMode.fromWireValue(
                    intent.getStringExtra(EXTRA_SPLIT_MODE) ?: SplitTunnelMode.ALL.wireValue,
                )
                selectedPackages = intent.getStringArrayListExtra(EXTRA_SELECTED_PACKAGES)?.toSet().orEmpty()

                try {
                    trace("Building foreground notification")
                    val notification = buildTunnelNotification(
                        "Туннель подключается",
                        elapsedMs = 0L,
                        rxBytes = 0L,
                        txBytes = 0L,
                    )
                    trace("Calling startForeground")
                    startForegroundNotification(notification)
                    trace("startForeground completed")
                } catch (t: Throwable) {
                    Log.e("SingBox", "startForeground failed", t)
                    trace("startForeground failed: ${t.message ?: t.javaClass.simpleName}")
                    SingBoxRuntimeState.failed(
                        this,
                        "startForeground failed: ${t.message ?: t.javaClass.simpleName}",
                    )
                    LibcoreBridge.startController.failed(
                        "startForeground failed: ${t.message ?: t.javaClass.simpleName}",
                    )
                    stopSelf()
                    return START_NOT_STICKY
                }

                trace("Submitting startBox task")
                executor.execute {
                    trace("startBox task running")
                    startBox(configJson)
                }
                trace("onStartCommand ACTION_START returning START_REDELIVER_INTENT")
                return START_REDELIVER_INTENT
            }
        }

        trace("onStartCommand returning default START_STICKY")
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        trace("onTaskRemoved called")
        super.onTaskRemoved(rootIntent)
    }

    fun startVpn(tunOptionsJson: String, tunPlatformOptionsJson: String): Int {
        tunInterface?.close()

        val builder = Builder()
            .setSession("wgfytunnel")
            .setMtu(1500)

        builder.addAddress("172.19.0.1", 30)
        builder.addDnsServer("172.19.0.2")
        builder.addRoute("0.0.0.0", 0)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            LibcoreBridge.underlyingNetwork?.let { network ->
                builder.setUnderlyingNetworks(arrayOf(network))
            }
        }

        applyPackageSelection(builder)

        tunInterface = builder.establish() ?: throw IOException("Не удалось создать VPN интерфейс sing-box")
        return tunInterface!!.fd
    }

    override fun onDestroy() {
        stopBox()
        SingBoxRuntimeState.stopped(this)
        LibcoreBridge.currentVpnService = null
        notificationExecutor.shutdownNow()
        executor.shutdown()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopSelf()
    }

    fun refreshNotificationIfActive() {
        if (!isActive) {
            return
        }

        updateNotification("Туннель подключен")
    }

    private fun applyPackageSelection(builder: Builder) {
        when (splitMode) {
            SplitTunnelMode.ALL -> return
            SplitTunnelMode.INCLUDE -> {
                (selectedPackages + packageName).sorted().forEach { pkg ->
                    try {
                        builder.addAllowedApplication(pkg)
                    } catch (_: PackageManager.NameNotFoundException) {
                        Log.w("SingBox", "Package not found for include rule: $pkg")
                    }
                }
            }

            SplitTunnelMode.EXCLUDE -> {
                selectedPackages.sorted().forEach { pkg ->
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (_: PackageManager.NameNotFoundException) {
                        Log.w("SingBox", "Package not found for exclude rule: $pkg")
                    }
                }
            }
        }
    }

    private fun startBox(configJson: String) {
        try {
            trace("Starting embedded sing-box instance")
            closeRuntime(keepForeground = true)
            LibcoreBridge.underlyingNetwork = getSystemService(ConnectivityManager::class.java)?.activeNetwork
            val instance = Libcore.newSingBoxInstance(configJson, LibcoreBridge.resolver())
            trace("Libcore.newSingBoxInstance completed")
            instance.setAsMain()
            trace("BoxInstance.setAsMain completed")
            instance.start()
            trace("BoxInstance.start completed")
            runCatching {
                instance.setV2rayStats(SingBoxConfig.proxyTag)
            }
            boxInstance = instance
            connectedAtElapsedRealtime = SystemClock.elapsedRealtime()
            notificationRxTotal = 0L
            notificationTxTotal = 0L
            startNotificationUpdates()
            isActive = true
            SingBoxRuntimeState.started(this)
            updateNotification("Туннель подключен")
            LibcoreBridge.startController.started()
        } catch (t: Throwable) {
            Log.e("SingBox", "Failed to start embedded sing-box", t)
            trace("Failed to start embedded sing-box: ${t.message ?: t.javaClass.simpleName}")
            SingBoxRuntimeState.failed(this, t.message ?: "Не удалось запустить sing-box")
            LibcoreBridge.startController.failed(t.message ?: "Не удалось запустить sing-box")
            stopSelf()
        }
    }

    private fun clearTrace() {
        runCatching {
            traceFile().writeText("")
        }
    }

    private fun trace(message: String) {
        Log.i("SingBox", message)
        runCatching {
            traceFile().appendText("${SystemClock.elapsedRealtime()} $message\n")
        }
    }

    private fun traceFile(): File {
        return File(filesDir, "singbox_service_trace.txt")
    }

    private fun stopBox() {
        closeRuntime(keepForeground = false)
    }

    private fun startNotificationUpdates() {
        if (notificationUpdateTask != null) {
            return
        }

        notificationUpdateTask = notificationExecutor.scheduleAtFixedRate(
            { refreshNotificationStats() },
            20L,
            20L,
            TimeUnit.SECONDS,
        )
    }

    private fun stopNotificationUpdates() {
        notificationUpdateTask?.cancel(true)
        notificationUpdateTask = null
    }

    private fun refreshNotificationStats() {
        val instance = boxInstance ?: return
        val txDelta = runCatching {
            instance.queryStats(SingBoxConfig.proxyTag, "uplink")
        }.getOrDefault(0L).coerceAtLeast(0L)
        val rxDelta = runCatching {
            instance.queryStats(SingBoxConfig.proxyTag, "downlink")
        }.getOrDefault(0L).coerceAtLeast(0L)

        notificationTxTotal += txDelta
        notificationRxTotal += rxDelta
        updateNotification("Туннель подключен")
    }

    private fun currentElapsedMs(): Long {
        val connectedAt = connectedAtElapsedRealtime ?: return 0L
        return SystemClock.elapsedRealtime() - connectedAt
    }

    private fun closeRuntime(keepForeground: Boolean) {
        isActive = false
        LibcoreBridge.underlyingNetwork = null
        stopNotificationUpdates()
        connectedAtElapsedRealtime = null
        notificationRxTotal = 0L
        notificationTxTotal = 0L

        runCatching {
            boxInstance?.close()
        }.onFailure {
            Log.w("SingBox", "Failed to close BoxInstance", it)
        }
        boxInstance = null

        runCatching {
            tunInterface?.close()
        }.onFailure {
            Log.w("SingBox", "Failed to close TUN interface", it)
        }
        tunInterface = null

        if (!keepForeground) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.cancel(NOTIFICATION_ID)
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private fun updateNotification(text: String) {
        val notificationManager = getSystemService(NotificationManager::class.java) ?: return
        notificationManager.notify(
            NOTIFICATION_ID,
            buildTunnelNotification(text),
        )
    }

    private fun buildTunnelNotification(
        text: String,
        elapsedMs: Long = currentElapsedMs(),
        rxBytes: Long = notificationRxTotal,
        txBytes: Long = notificationTxTotal,
    ): Notification {
        return TunnelNotificationSupport.buildNotification(
            context = this,
            statusText = text,
            elapsedMs = elapsedMs,
            rxBytes = rxBytes,
            txBytes = txBytes,
            deleteIntent = notificationDeleteIntent(),
        )
    }

    private fun startForegroundNotification(notification: Notification) {
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

    private fun notificationDeleteIntent(): PendingIntent {
        val intent = Intent(this, SingBoxVpnService::class.java).apply {
            action = ACTION_RESTORE_NOTIFICATION
        }
        return PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}