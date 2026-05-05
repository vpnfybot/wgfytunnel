package com.example.wgfytunnel

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Manages embedded sing-box runtime using libcore + Android VpnService.
 */
class SingBoxManager(private val context: Context) {
    @Volatile
    var lastError: String? = null
        private set

    val isRunning: Boolean
        get() = SingBoxRuntimeState.isRunning(context)

    /**
     * Start embedded sing-box with the given JSON configuration.
     */
    fun start(configJson: String, splitMode: SplitTunnelMode, selectedPackages: Set<String>): Boolean {
        lastError = null

        if (isRunning) {
            stop()
        }

        return try {
            val application = context.applicationContext
            if (application is Application) {
                LibcoreBridge.initialize(application)
            }
            SingBoxRuntimeState.reset(context)
            val intent = Intent(context, SingBoxVpnService::class.java).apply {
                action = SingBoxVpnService.ACTION_START
                putExtra(SingBoxVpnService.EXTRA_CONFIG_JSON, configJson)
                putExtra(SingBoxVpnService.EXTRA_SPLIT_MODE, splitMode.wireValue)
                putStringArrayListExtra(
                    SingBoxVpnService.EXTRA_SELECTED_PACKAGES,
                    ArrayList(selectedPackages.sorted()),
                )
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }

            val error = SingBoxRuntimeState.await(context, 15_000)
            if (error != null) {
                lastError = error
                android.util.Log.e("SingBox", error)
                false
            } else {
                true
            }
        } catch (e: Exception) {
            lastError = e.message ?: "Не удалось запустить sing-box"
            android.util.Log.e("SingBox", "Failed to start embedded sing-box: ${e.message}", e)
            false
        }
    }

    /**
     * Stop embedded sing-box service.
     */
    fun stop() {
        lastError = null
        runCatching {
            context.startService(
                Intent(context, SingBoxVpnService::class.java).apply {
                    action = SingBoxVpnService.ACTION_STOP
                },
            )
        }.onFailure {
            android.util.Log.w("SingBox", "Failed to stop sing-box service", it)
        }
    }
}
