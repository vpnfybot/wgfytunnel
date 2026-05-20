package com.example.wgfytunnel

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class QuickSettingsVpnTileService : TileService() {
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        unlockAndRun {
            Thread {
                val shouldOpenApp = handleTileClick()
                mainHandler.post {
                    if (shouldOpenApp) {
                        openMainActivity()
                    }
                    refreshTile()
                }
            }.start()
        }
    }

    private fun handleTileClick(): Boolean {
        return if (QuickTileVpnController.isConnected(applicationContext)) {
            QuickTileVpnController.disconnect(applicationContext)
            false
        } else {
            when (QuickTileVpnController.connectLastSaved(applicationContext)) {
                QuickTileLaunchResult.SUCCESS -> false
                QuickTileLaunchResult.NO_SNAPSHOT,
                QuickTileLaunchResult.PERMISSION_REQUIRED,
                QuickTileLaunchResult.FAILED -> true
            }
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val snapshot = LastVpnConnectionStore.load(applicationContext)
        val activeBackend = QuickTileVpnController.currentBackend(applicationContext)

        tile.icon = Icon.createWithResource(this, R.drawable.ic_stat_vpnfy)
        tile.label = applicationInfo.loadLabel(packageManager)
        tile.state = when {
            activeBackend != null -> Tile.STATE_ACTIVE
            snapshot != null -> Tile.STATE_INACTIVE
            else -> Tile.STATE_UNAVAILABLE
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when {
                activeBackend != null -> snapshot?.configName ?: "VPN"
                snapshot != null -> snapshot.configName
                else -> "Open app"
            }
        }

        tile.contentDescription = when {
            activeBackend != null -> "VPN active"
            snapshot != null -> "Connect last VPN configuration"
            else -> "Open app to choose a configuration"
        }
        tile.updateTile()
    }

    private fun openMainActivity() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } ?: Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }
    }
}