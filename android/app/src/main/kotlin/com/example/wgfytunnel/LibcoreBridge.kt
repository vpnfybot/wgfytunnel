package com.example.wgfytunnel

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.Network
import android.net.wifi.WifiManager
import android.os.CancellationSignal
import android.os.Build
import android.system.ErrnoException
import go.Seq
import libcore.BoxPlatformInterface
import libcore.ExchangeContext
import libcore.Libcore
import libcore.LocalDNSTransport
import libcore.NB4AInterface
import java.net.InetAddress
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.UnknownHostException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object LibcoreBridge {
    @Volatile
    private var initialized = false

    @Volatile
    private var initializationError: String? = null

    @Volatile
    var currentVpnService: SingBoxVpnService? = null

    @Volatile
    var underlyingNetwork: Network? = null

    val startController = SingBoxStartController()

    private lateinit var localResolver: LocalDNSTransport

    fun initialize(application: Application) {
        initializationError?.let { throw IllegalStateException(it) }
        if (initialized) return
        synchronized(this) {
            initializationError?.let { throw IllegalStateException(it) }
            if (initialized) return

            val appContext = application.applicationContext
            val nativeInterface = LibcoreNativeInterface(appContext)
            localResolver = LibcoreLocalResolver()
            val externalAssets = application.getExternalFilesDir(null) ?: application.filesDir

            try {
                Seq.setContext(application)
                Libcore.initCore(
                    processName(application),
                    application.cacheDir.absolutePath + "/",
                    application.filesDir.absolutePath + "/",
                    externalAssets.absolutePath + "/",
                    1024,
                    true,
                    nativeInterface,
                    nativeInterface,
                    localResolver,
                )
                initialized = true
            } catch (error: UnsatisfiedLinkError) {
                initializationError = unsupportedAbiMessage()
                throw IllegalStateException(initializationError, error)
            }
        }
    }

    fun resolver(): LocalDNSTransport = localResolver

    private fun processName(application: Application): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Application.getProcessName()
        } else {
            application.packageName
        }
    }

    private fun unsupportedAbiMessage(): String {
        val abiList = Build.SUPPORTED_ABIS.joinToString()
        return "Embedded sing-box недоступен для ABI: $abiList. В APK отсутствует совместимый libgojni.so."
    }
}

class SingBoxStartController {
    @Volatile
    private var latch: CountDownLatch? = null

    @Volatile
    private var errorMessage: String? = null

    fun reset() {
        errorMessage = null
        latch = CountDownLatch(1)
    }

    fun started() {
        latch?.countDown()
    }

    fun failed(message: String) {
        errorMessage = message
        latch?.countDown()
    }

    fun await(timeoutMs: Long): String? {
        val localLatch = latch ?: return "sing-box не был инициализирован"
        val completed = localLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return if (completed) errorMessage else "Истекло ожидание запуска sing-box"
    }
}

private class LibcoreNativeInterface(private val context: Context) : BoxPlatformInterface, NB4AInterface {
    override fun autoDetectInterfaceControl(fd: Int) {
        LibcoreBridge.currentVpnService?.protect(fd)
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return 0
        }
        val connectivityManager = context.getSystemService(ConnectivityManager::class.java) ?: return 0
        return connectivityManager.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
    }

    override fun openTun(singTunOptionsJson: String, tunPlatformOptionsJson: String): Long {
        val service = LibcoreBridge.currentVpnService ?: throw Exception("no VpnService")
        return service.startVpn(singTunOptionsJson, tunPlatformOptionsJson).toLong()
    }

    override fun packageNameByUid(uid: Int): String {
        if (uid <= 1000) return "android"
        return context.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: "android"
    }

    override fun selector_OnProxySelected(selectorTag: String, tag: String) {
        // Single outbound profile in this app, nothing to switch.
    }

    override fun uidByPackageName(packageName: String): Int {
        return try {
            @Suppress("DEPRECATION")
            context.packageManager.getApplicationInfo(packageName, 0).uid
        } catch (_: PackageManager.NameNotFoundException) {
            0
        }
    }

    override fun useOfficialAssets(): Boolean = true

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun wifiState(): String {
        return try {
            @Suppress("DEPRECATION")
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val info = wifiManager.connectionInfo
            val ssid = info?.ssid ?: ""
            val bssid = info?.bssid ?: ""
            "$ssid,$bssid"
        } catch (_: Exception) {
            ","
        }
    }
}

private class LibcoreLocalResolver : LocalDNSTransport {
    private val dnsExecutor = Executors.newCachedThreadPool()

    override fun exchange(ctx: ExchangeContext, message: ByteArray) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            ctx.errnoCode(95)
            return
        }

        val signal = CancellationSignal()
        ctx.onCancel(signal::cancel)

        val callback = object : DnsResolver.Callback<ByteArray> {
            override fun onAnswer(answer: ByteArray, rcode: Int) {
                ctx.rawSuccess(answer)
            }

            override fun onError(error: DnsResolver.DnsException) {
                val cause = error.cause
                if (cause is ErrnoException) {
                    ctx.errnoCode(cause.errno)
                } else {
                    ctx.errnoCode(114514)
                }
            }
        }

        DnsResolver.getInstance().rawQuery(
            LibcoreBridge.underlyingNetwork,
            message,
            DnsResolver.FLAG_NO_RETRY,
            dnsExecutor,
            signal,
            callback,
        )
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val signal = CancellationSignal()
            ctx.onCancel(signal::cancel)

            val callback = object : DnsResolver.Callback<Collection<InetAddress>> {
                override fun onAnswer(answer: Collection<InetAddress>, rcode: Int) {
                    try {
                        if (rcode == 0) {
                            ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
                        } else {
                            ctx.errorCode(rcode)
                        }
                    } catch (_: Exception) {
                        ctx.errnoCode(114514)
                    }
                }

                override fun onError(error: DnsResolver.DnsException) {
                    try {
                        val cause = error.cause
                        if (cause is ErrnoException) {
                            ctx.errnoCode(cause.errno)
                        } else {
                            ctx.errnoCode(114514)
                        }
                    } catch (_: Exception) {
                        ctx.errnoCode(114514)
                    }
                }
            }

            val dnsType = when {
                network.endsWith("4") -> DnsResolver.TYPE_A
                network.endsWith("6") -> DnsResolver.TYPE_AAAA
                else -> null
            }

            if (dnsType != null) {
                DnsResolver.getInstance().query(
                    LibcoreBridge.underlyingNetwork,
                    domain,
                    dnsType,
                    DnsResolver.FLAG_NO_RETRY,
                    dnsExecutor,
                    signal,
                    callback,
                )
            } else {
                DnsResolver.getInstance().query(
                    LibcoreBridge.underlyingNetwork,
                    domain,
                    DnsResolver.FLAG_NO_RETRY,
                    dnsExecutor,
                    signal,
                    callback,
                )
            }
            return
        }

        try {
            val addresses = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                LibcoreBridge.underlyingNetwork?.getAllByName(domain) ?: InetAddress.getAllByName(domain)
            } else {
                InetAddress.getAllByName(domain)
            }

            val filtered = addresses.mapNotNull { address ->
                when {
                    network.endsWith("4") && address !is Inet4Address -> null
                    network.endsWith("6") && address !is Inet6Address -> null
                    else -> address.hostAddress
                }
            }

            if (filtered.isEmpty()) {
                ctx.errorCode(3)
            } else {
                ctx.success(filtered.joinToString("\n"))
            }
        } catch (_: UnknownHostException) {
            ctx.errorCode(3)
        } catch (_: Exception) {
            ctx.errnoCode(114514)
        }
    }

    override fun networkHandle(): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            LibcoreBridge.underlyingNetwork?.networkHandle ?: 0L
        } else {
            0L
        }
    }

    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
}