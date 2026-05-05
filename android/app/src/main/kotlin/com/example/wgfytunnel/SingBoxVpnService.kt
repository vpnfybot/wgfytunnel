package com.example.wgfytunnel

import android.app.Notification
import android.app.NotificationChannel
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

class SingBoxVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.example.wgfytunnel.action.START_SINGBOX"
        const val ACTION_STOP = "com.example.wgfytunnel.action.STOP_SINGBOX"
        const val EXTRA_CONFIG_JSON = "config_json"
        const val EXTRA_SPLIT_MODE = "split_mode"
        const val EXTRA_SELECTED_PACKAGES = "selected_packages"

        private const val CHANNEL_ID = "wgfytunnel_singbox"
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

    override fun onCreate() {
        super.onCreate()
        trace("SingBoxVpnService.onCreate")
        LibcoreBridge.currentVpnService = this
        createNotificationChannel()
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
                    val notification = buildNotification("Запуск sing-box")
                    trace("Calling startForeground")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startForeground(
                            NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }
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
        executor.shutdown()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopSelf()
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

    private fun buildNotification(text: String): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("wgfytunnel")
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "wgfytunnel VPN",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
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
            boxInstance = instance
            isActive = true
            SingBoxRuntimeState.started(this)
            updateNotification("VPN sing-box подключен")
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

    private fun closeRuntime(keepForeground: Boolean) {
        isActive = false
        LibcoreBridge.underlyingNetwork = null

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
        notificationManager.notify(NOTIFICATION_ID, buildNotification(text))
    }
}