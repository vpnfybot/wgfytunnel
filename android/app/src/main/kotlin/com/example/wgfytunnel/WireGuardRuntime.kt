package com.example.wgfytunnel

import android.content.Context
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.NoopTunnelActionHandler
import org.amnezia.awg.backend.Tunnel

object WireGuardRuntime {
    private val initLock = Any()

    @Volatile
    private var initialized = false

    lateinit var backend: GoBackend
        private set

    val tunnel: AppTunnel = AppTunnel("wgfytunnel")

    @Volatile
    var connectedAtElapsedRealtime: Long? = null

    fun initialize(context: Context) {
        if (initialized) {
            return
        }

        synchronized(initLock) {
            if (initialized) {
                return
            }

            backend = GoBackend(context.applicationContext, NoopTunnelActionHandler())
            initialized = true
        }
    }
}

class AppTunnel(private val tunnelName: String) : Tunnel {
    @Volatile
    var state: Tunnel.State = Tunnel.State.DOWN
        private set

    override fun getName(): String = tunnelName

    override fun onStateChange(newState: Tunnel.State) {
        state = newState
    }

    override fun isIpv4ResolutionPreferred(): Boolean = false

    override fun isMetered(): Boolean = false
}
