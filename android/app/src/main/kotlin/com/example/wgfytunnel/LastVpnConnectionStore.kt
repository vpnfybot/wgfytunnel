package com.example.wgfytunnel

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import android.service.quicksettings.TileService
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import org.json.JSONArray
import org.json.JSONObject

enum class SavedVpnBackend(val wireValue: String) {
    WIREGUARD("wireguard"),
    SING_BOX("sing-box");

    companion object {
        fun fromWireValue(value: String?): SavedVpnBackend {
            return entries.firstOrNull { it.wireValue == value } ?: WIREGUARD
        }
    }
}

data class LastVpnConnectionSnapshot(
    val backend: SavedVpnBackend,
    val configName: String,
    val payload: String,
    val splitMode: SplitTunnelMode,
    val selectedPackages: Set<String>,
) {
    companion object {
        fun wireGuard(configName: String, payload: String): LastVpnConnectionSnapshot {
            return LastVpnConnectionSnapshot(
                backend = SavedVpnBackend.WIREGUARD,
                configName = configName,
                payload = payload,
                splitMode = SplitTunnelMode.ALL,
                selectedPackages = emptySet(),
            )
        }

        fun singBox(
            configName: String,
            payload: String,
            splitMode: SplitTunnelMode,
            selectedPackages: Set<String>,
        ): LastVpnConnectionSnapshot {
            return LastVpnConnectionSnapshot(
                backend = SavedVpnBackend.SING_BOX,
                configName = configName,
                payload = payload,
                splitMode = splitMode,
                selectedPackages = selectedPackages,
            )
        }
    }
}

object LastVpnConnectionStore {
    private const val PREFS_NAME = "last_vpn_connection"
    private const val KEY_SNAPSHOT = "snapshot"

    fun save(context: Context, snapshot: LastVpnConnectionSnapshot) {
        val payload = JSONObject()
            .put("backend", snapshot.backend.wireValue)
            .put("configName", snapshot.configName)
            .put("payload", snapshot.payload)
            .put("splitMode", snapshot.splitMode.wireValue)
            .put("selectedPackages", JSONArray(snapshot.selectedPackages.sorted()))

        prefs(context)
            .edit()
            .putString(KEY_SNAPSHOT, payload.toString())
            .apply()
    }

    fun load(context: Context): LastVpnConnectionSnapshot? {
        val raw = prefs(context).getString(KEY_SNAPSHOT, null) ?: return null
        return runCatching {
            val json = JSONObject(raw)
            val packagesJson = json.optJSONArray("selectedPackages") ?: JSONArray()
            val packages = buildSet {
                for (index in 0 until packagesJson.length()) {
                    add(packagesJson.optString(index))
                }
            }.filter(String::isNotBlank).toSet()

            LastVpnConnectionSnapshot(
                backend = SavedVpnBackend.fromWireValue(json.optString("backend")),
                configName = json.optString("configName").ifBlank { "VPN" },
                payload = json.getString("payload"),
                splitMode = SplitTunnelMode.fromWireValue(json.optString("splitMode")),
                selectedPackages = packages,
            )
        }.getOrNull()
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_SNAPSHOT).apply()
    }

    private fun prefs(context: Context): SharedPreferences {
        return context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
}

enum class QuickTileLaunchResult {
    SUCCESS,
    NO_SNAPSHOT,
    PERMISSION_REQUIRED,
    FAILED,
}

object QuickTileVpnController {
    fun connectLastSaved(context: Context): QuickTileLaunchResult {
        val appContext = context.applicationContext
        val snapshot = LastVpnConnectionStore.load(appContext) ?: return QuickTileLaunchResult.NO_SNAPSHOT
        if (VpnService.prepare(appContext) != null) {
            return QuickTileLaunchResult.PERMISSION_REQUIRED
        }

        return when (snapshot.backend) {
            SavedVpnBackend.WIREGUARD -> connectWireGuard(appContext, snapshot)
            SavedVpnBackend.SING_BOX -> connectSingBox(appContext, snapshot)
        }
    }

    fun disconnect(context: Context): Boolean {
        val appContext = context.applicationContext
        var changed = false

        val singBoxManager = SingBoxManager(appContext)
        if (singBoxManager.isRunning) {
            singBoxManager.stop()
            changed = true
        }

        WireGuardRuntime.initialize(appContext)
        val wgConnected = runCatching {
            WireGuardRuntime.backend.getState(WireGuardRuntime.tunnel) == Tunnel.State.UP
        }.getOrDefault(false)

        runCatching {
            WireGuardRuntime.backend.setState(WireGuardRuntime.tunnel, Tunnel.State.DOWN, null)
        }.onSuccess {
            changed = changed || wgConnected
        }

        WireGuardRuntime.connectedAtElapsedRealtime = null
        WireGuardNotificationService.stop(appContext)
        requestTileRefresh(appContext)
        return changed
    }

    fun isConnected(context: Context): Boolean {
        return currentBackend(context) != null
    }

    fun currentBackend(context: Context): SavedVpnBackend? {
        val appContext = context.applicationContext
        val singBoxConnected = SingBoxRuntimeState.isRunning(appContext)
        if (singBoxConnected) {
            return SavedVpnBackend.SING_BOX
        }

        WireGuardRuntime.initialize(appContext)
        val wgConnected = runCatching {
            WireGuardRuntime.backend.getState(WireGuardRuntime.tunnel) == Tunnel.State.UP
        }.getOrDefault(false)
        return if (wgConnected) SavedVpnBackend.WIREGUARD else null
    }

    fun requestTileRefresh(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return
        }

        TileService.requestListeningState(
            context.applicationContext,
            ComponentName(context.applicationContext, QuickSettingsVpnTileService::class.java),
        )
    }

    private fun connectWireGuard(context: Context, snapshot: LastVpnConnectionSnapshot): QuickTileLaunchResult {
        val singBoxManager = SingBoxManager(context)
        if (singBoxManager.isRunning) {
            singBoxManager.stop()
        }

        WireGuardRuntime.initialize(context)

        return runCatching {
            val config = snapshot.payload.byteInputStream().use { input ->
                Config.parse(input)
            }
            WireGuardRuntime.backend.setState(WireGuardRuntime.tunnel, Tunnel.State.UP, config)
            val connectedAtElapsedRealtime = SystemClock.elapsedRealtime()
            WireGuardRuntime.connectedAtElapsedRealtime = connectedAtElapsedRealtime
            WireGuardNotificationService.start(context, connectedAtElapsedRealtime)
            requestTileRefresh(context)
            QuickTileLaunchResult.SUCCESS
        }.getOrElse {
            QuickTileLaunchResult.FAILED
        }
    }

    private fun connectSingBox(context: Context, snapshot: LastVpnConnectionSnapshot): QuickTileLaunchResult {
        WireGuardRuntime.initialize(context)
        runCatching {
            WireGuardRuntime.backend.setState(WireGuardRuntime.tunnel, Tunnel.State.DOWN, null)
        }
        WireGuardRuntime.connectedAtElapsedRealtime = null
        WireGuardNotificationService.stop(context)

        val success = SingBoxManager(context).start(
            snapshot.payload,
            snapshot.splitMode,
            snapshot.selectedPackages,
        )
        if (!success) {
            return QuickTileLaunchResult.FAILED
        }

        requestTileRefresh(context)
        return QuickTileLaunchResult.SUCCESS
    }
}