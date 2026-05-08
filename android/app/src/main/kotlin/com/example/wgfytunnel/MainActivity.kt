package com.example.wgfytunnel

import android.Manifest
import android.app.Activity
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.BadConfigException
import com.wireguard.config.Config
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.DatagramSocket
import java.net.DatagramPacket
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
	companion object {
		private const val vpnPermissionRequestCode = 1001
		private const val notificationPermissionRequestCode = 1002
	}

	private val channelName = "wgfytunnel/wireguard"
	private val executor = Executors.newSingleThreadExecutor()
	private val dnsResolverExecutor = Executors.newCachedThreadPool()
	private val tunnel: AppTunnel
		get() = WireGuardRuntime.tunnel
	private val backend: GoBackend
		get() = WireGuardRuntime.backend
	private lateinit var singBoxManager: SingBoxManager
	private var notificationPermissionRequestInFlight = false
	@Volatile
	private var installedAppsCache: List<Map<String, String>>? = null
	private var useSingBox = false
	private var pendingResult: MethodChannel.Result? = null
	private var pendingConfig: Config? = null
	private var pendingStatusMessage: String? = null
	private var pendingWgConfig: String? = null
	private var pendingSplitMode: SplitTunnelMode? = null
	private var pendingSelectedPackages: Set<String>? = null
	private var pendingDomainMode: SplitTunnelDomainMode? = null
	private var pendingDomainList: List<String>? = null

	override fun onCreate(savedInstanceState: android.os.Bundle?) {
		super.onCreate(savedInstanceState)
		WireGuardRuntime.initialize(applicationContext)
		singBoxManager = SingBoxManager(applicationContext)
	}

	override fun onRequestPermissionsResult(
		requestCode: Int,
		permissions: Array<out String>,
		grantResults: IntArray,
	) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		if (requestCode != notificationPermissionRequestCode) {
			return
		}

		notificationPermissionRequestInFlight = false
		val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
		if (!granted) {
			return
		}

		WireGuardRuntime.connectedAtElapsedRealtime?.let { connectedAtElapsedRealtime ->
			WireGuardNotificationService.start(applicationContext, connectedAtElapsedRealtime)
		}
		LibcoreBridge.currentVpnService?.refreshNotificationIfActive()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getInstalledApps" -> {
						getInstalledApps(result)
					}

					"getWireGuardStatus" -> {
						executor.execute {
							val payload = runCatching { statusPayload() }
								.getOrElse {
									val singBoxConnected = singBoxManager.isRunning
									mapOf(
										"connected" to singBoxConnected,
										"tunnelName" to tunnel.name,
										"backend" to if (singBoxConnected) "sing-box" else "wireguard",
									)
								}
							runOnUiThread { result.success(payload) }
						}
					}

					"getWireGuardStats" -> {
						executor.execute {
							try {
								val stats = backend.getStatistics(tunnel)
								val payload = mapOf(
									"rxBytes" to stats.totalRx(),
									"txBytes" to stats.totalTx(),
								)
								runOnUiThread { result.success(payload) }
							} catch (e: Exception) {
								runOnUiThread { result.success(mapOf("rxBytes" to 0L, "txBytes" to 0L)) }
							}
						}
					}

					"connectWireGuard" -> {
						val filePath = call.argument<String>("filePath")
						val splitMode = call.argument<String>("splitMode") ?: SplitTunnelMode.ALL.wireValue
						val selectedPackages = call.argument<List<String>>("selectedPackages")?.toSet().orEmpty()
						val domainMode = call.argument<String>("domainMode") ?: SplitTunnelDomainMode.ALL.wireValue
						val domainList = call.argument<List<String>>("domainList").orEmpty()
						if (filePath.isNullOrBlank()) {
							result.error("INVALID_ARGS", "filePath is required", null)
							return@setMethodCallHandler
						}

						connectWireGuard(filePath, splitMode, selectedPackages, domainMode, domainList, result)
					}

					"disconnectWireGuard" -> {
						if (useSingBox || singBoxManager.isRunning) {
							disconnectSingBox(result)
						} else {
							disconnectWireGuard(result)
						}
					}

					else -> {
						result.notImplemented()
					}
				}
			}
	}

	@Deprecated("Deprecated in Java")
	override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode != vpnPermissionRequestCode) {
			return
		}

		val result = pendingResult ?: return
		val config = pendingConfig
		val wgConfig = pendingWgConfig
		val statusMessage = pendingStatusMessage
		val splitMode = pendingSplitMode ?: SplitTunnelMode.ALL
		val selectedPackages = pendingSelectedPackages ?: emptySet()
		pendingResult = null
		pendingConfig = null
		pendingWgConfig = null
		pendingStatusMessage = null
		pendingSplitMode = null
		pendingSelectedPackages = null
		pendingDomainMode = null
		pendingDomainList = null

		if (resultCode != Activity.RESULT_OK) {
			result.error("VPN_PERMISSION_DENIED", "Разрешение на запуск VPN отклонено", null)
			return
		}

		if (wgConfig != null) {
			startSingBox(wgConfig, splitMode, selectedPackages, result, statusMessage ?: "VPN sing-box подключен")
		} else if (config != null) {
			connectWithConfig(config, result, statusMessage)
		} else {
			result.error("VPN_NO_CONFIG", "Нет конфигурации для подключения", null)
		}
	}

	private fun connectWireGuard(
		filePath: String,
		splitModeRaw: String,
		selectedPackages: Set<String>,
		domainModeRaw: String,
		domainList: List<String>,
		result: MethodChannel.Result,
	) {
		if (pendingResult != null) {
			result.error("VPN_BUSY", "Подключение уже выполняется", null)
			return
		}

		if (useSingBox || singBoxManager.isRunning) {
			singBoxManager.stop()
			useSingBox = false
		}

		val splitMode = SplitTunnelMode.fromWireValue(splitModeRaw)
		if (splitMode != SplitTunnelMode.ALL && selectedPackages.isEmpty()) {
			result.error("WG_SPLIT_EMPTY", "Для выбранного режима нужно отметить хотя бы одно приложение", null)
			return
		}

		val domainMode = SplitTunnelDomainMode.fromWireValue(domainModeRaw)
		if (domainMode != SplitTunnelDomainMode.ALL && domainList.isEmpty()) {
			result.error("WG_DOMAIN_EMPTY", "Для доменного режима укажите хотя бы один домен", null)
			return
		}

		val statusMessage = when {
			domainMode == SplitTunnelDomainMode.INCLUDE -> "VPN: только выбранные сайты через туннель (${domainList.joinToString(", ")})"
			domainMode == SplitTunnelDomainMode.EXCLUDE -> "VPN: все сайты кроме выбранных через туннель (${domainList.joinToString(", ")})"
			splitMode == SplitTunnelMode.ALL -> "VPN подключен для всей системы"
			splitMode == SplitTunnelMode.INCLUDE -> "VPN подключен только для выбранных приложений"
			splitMode == SplitTunnelMode.EXCLUDE -> "VPN подключен для всей системы, кроме выбранных приложений"
			else -> "VPN подключен"
		}

		executor.execute {
			val config = try {
				parseConfig(filePath, splitMode, selectedPackages, domainMode, domainList)
			} catch (e: IOException) {
				runOnUiThread {
					result.error("WG_CONFIG_IO", e.message ?: "Не удалось прочитать конфиг", null)
				}
				return@execute
			} catch (e: BadConfigException) {
				runOnUiThread {
					result.error("WG_CONFIG_INVALID", e.message ?: "Конфиг WireGuard невалиден", null)
				}
				return@execute
			}

			runOnUiThread {
				val permissionIntent = VpnService.prepare(this)
				if (permissionIntent != null) {
					pendingResult = result
					pendingConfig = config
					pendingStatusMessage = statusMessage
					startActivityForResult(permissionIntent, vpnPermissionRequestCode)
					return@runOnUiThread
				}

				connectWithConfig(config, result, statusMessage)
			}
		}
	}

	private fun connectWithConfig(config: Config, result: MethodChannel.Result, statusMessage: String?) {
		executor.execute {
			try {
				backend.setState(tunnel, Tunnel.State.UP, config)
				runOnUiThread {
					val connectedAtElapsedRealtime = SystemClock.elapsedRealtime()
					WireGuardRuntime.connectedAtElapsedRealtime = connectedAtElapsedRealtime
					WireGuardNotificationService.start(applicationContext, connectedAtElapsedRealtime)
					requestNotificationPermissionIfNeeded()
					result.success(statusPayload(statusMessage ?: "VPN подключен", connectedOverride = true))
				}
			} catch (e: Exception) {
				runOnUiThread {
					WireGuardRuntime.connectedAtElapsedRealtime = null
					WireGuardNotificationService.stop(applicationContext)
					result.error("WG_CONNECT_FAILED", e.message ?: "Не удалось поднять WireGuard туннель", null)
				}
			}
		}
	}

	private fun getInstalledApps(result: MethodChannel.Result) {
		executor.execute {
			try {
				val cachedApps = installedAppsCache
				if (cachedApps != null) {
					runOnUiThread {
						result.success(cachedApps)
					}
					return@execute
				}

				val apps = queryInstalledApps().map {
					mapOf(
						"label" to it.label,
						"packageName" to it.packageName,
					)
				}
				installedAppsCache = apps
				runOnUiThread {
					result.success(apps)
				}
			} catch (e: Exception) {
				runOnUiThread {
					result.error("WG_APPS_FAILED", e.message ?: "Не удалось получить список приложений", null)
				}
			}
		}
	}

	private fun disconnectWireGuard(result: MethodChannel.Result) {
		executor.execute {
			try {
				backend.setState(tunnel, Tunnel.State.DOWN, null)
				runOnUiThread {
					WireGuardRuntime.connectedAtElapsedRealtime = null
					WireGuardNotificationService.stop(applicationContext)
					result.success(statusPayload("VPN отключен", connectedOverride = false))
				}
			} catch (e: Exception) {
				runOnUiThread {
					result.error("WG_DISCONNECT_FAILED", e.message ?: "Не удалось отключить туннель", null)
				}
			}
		}
	}

	// ===== SingBox methods =====

	private fun connectSingBox(
		filePath: String,
		splitModeRaw: String,
		selectedPackages: Set<String>,
		domainModeRaw: String,
		domainList: List<String>,
		result: MethodChannel.Result,
	) {
		android.util.Log.i("SingBox", "connectSingBox called: domainMode=$domainModeRaw, domains=$domainList")

		if (pendingResult != null) {
			result.error("VPN_BUSY", "Подключение уже выполняется", null)
			return
		}

		val splitMode = SplitTunnelMode.fromWireValue(splitModeRaw)
		val domainMode = SplitTunnelDomainMode.fromWireValue(domainModeRaw)

		// Read WireGuard config
		val rawConfig = try {
			File(filePath).readText()
		} catch (e: IOException) {
			result.error("WG_CONFIG_IO", e.message ?: "Не удалось прочитать конфиг", null)
			return
		}

		// Parse WireGuard config
		val wgConfig = try {
			SingBoxConfig.parseWireGuardConfig(rawConfig)
		} catch (e: Exception) {
			result.error("WG_CONFIG_INVALID", e.message ?: "Конфиг WireGuard невалиден", null)
			return
		}

		// Build sing-box config
		val singBoxConfig = SingBoxConfig.buildConfig(
			wgConfig = wgConfig,
			splitMode = splitMode,
			selectedPackages = selectedPackages,
			domainMode = domainMode,
			domainList = domainList,
		)

		android.util.Log.d("SingBox", "Generated config: ${singBoxConfig.toString(2)}")

		val statusMessage = when (domainMode) {
			SplitTunnelDomainMode.ALL -> "VPN sing-box подключен для всей системы"
			SplitTunnelDomainMode.INCLUDE -> "VPN sing-box: только выбранные сайты через туннель"
			SplitTunnelDomainMode.EXCLUDE -> "VPN sing-box: все сайты кроме выбранных через туннель"
		}

		// Check VPN permission
		val permissionIntent = VpnService.prepare(this)
		if (permissionIntent != null) {
			pendingResult = result
			pendingWgConfig = singBoxConfig.toString()
			pendingStatusMessage = statusMessage
			pendingSplitMode = splitMode
			pendingSelectedPackages = selectedPackages
			pendingDomainMode = domainMode
			pendingDomainList = domainList
			startActivityForResult(permissionIntent, vpnPermissionRequestCode)
			return
		}

		startSingBox(singBoxConfig.toString(), splitMode, selectedPackages, result, statusMessage)
	}

	private fun startSingBox(
		configJson: String,
		splitMode: SplitTunnelMode,
		selectedPackages: Set<String>,
		result: MethodChannel.Result,
		statusMessage: String,
	) {
		executor.execute {
			val success = singBoxManager.start(configJson, splitMode, selectedPackages)
			if (success) {
				WireGuardRuntime.connectedAtElapsedRealtime = null
				WireGuardNotificationService.stop(applicationContext)
				useSingBox = true
				runOnUiThread {
					requestNotificationPermissionIfNeeded()
					result.success(statusPayload(statusMessage, connectedOverride = true))
				}
			} else {
				runOnUiThread {
						result.error(
							"SINGBOX_START_FAILED",
							singBoxManager.lastError ?: "Не удалось запустить sing-box",
							null,
						)
				}
			}
		}
	}

	private fun disconnectSingBox(result: MethodChannel.Result) {
		executor.execute {
			singBoxManager.stop()
			useSingBox = false
			WireGuardRuntime.connectedAtElapsedRealtime = null
			WireGuardNotificationService.stop(applicationContext)
			runOnUiThread {
				result.success(statusPayload("VPN sing-box отключен", connectedOverride = false))
			}
		}
	}

	private fun parseConfig(
		filePath: String,
		splitMode: SplitTunnelMode,
		selectedPackages: Set<String>,
		domainMode: SplitTunnelDomainMode,
		domainList: List<String>,
	): Config {
		val source = File(filePath)
		if (!source.exists()) {
			throw IOException("Файл не найден")
		}

		val rawConfig = source.readText()
		val resolvedIps = if (domainMode == SplitTunnelDomainMode.ALL || domainList.isEmpty()) {
			emptyList()
		} else {
			resolveDomains(domainList)
		}
		android.util.Log.d("WG_SPLIT", "Domain list: $domainList")
		android.util.Log.d("WG_SPLIT", "Resolved IPs: $resolvedIps")
		if (domainMode == SplitTunnelDomainMode.INCLUDE && domainList.isNotEmpty() && resolvedIps.isEmpty()) {
			throw IOException("Не удалось определить IP для выбранных доменов. Проверьте DNS/сеть и попробуйте снова")
		}
		val effectiveConfig = applySplitTunnelOverrides(rawConfig, splitMode, selectedPackages, domainMode, resolvedIps)
		android.util.Log.d("WG_SPLIT", "Effective config AllowedIPs section: ${effectiveConfig.lines().filter { it.trim().startsWith("AllowedIPs", ignoreCase = true) }}")
		effectiveConfig.byteInputStream().use { stream ->
			return Config.parse(stream)
		}
	}

	private fun applySplitTunnelOverrides(
		rawConfig: String,
		splitMode: SplitTunnelMode,
		selectedPackages: Set<String>,
		domainMode: SplitTunnelDomainMode,
		resolvedIps: List<String>,
	): String {
		val appOverrideLine = when (splitMode) {
			SplitTunnelMode.ALL -> null
			SplitTunnelMode.INCLUDE -> "IncludedApplications = ${selectedPackages.sorted().joinToString(",")}"
			SplitTunnelMode.EXCLUDE -> "ExcludedApplications = ${selectedPackages.sorted().joinToString(",")}"
		}

		val allLines = rawConfig.lines()
		val existingAllowedIps = allLines
			.map { it.trim() }
			.filter { it.startsWith("AllowedIPs", ignoreCase = true) }
			.mapNotNull { line ->
				val afterEquals = line.substringAfter("=", "").trim()
				afterEquals.takeIf { it.isNotEmpty() }
			}
			.flatMap { it.split(",").map(String::trim).filter(String::isNotEmpty) }

		val overrideAllowedIpsLine = if (domainMode == SplitTunnelDomainMode.ALL) {
			null
		} else {
			computeAllowedIps(existingAllowedIps.map { "AllowedIPs = $it" }, domainMode, resolvedIps)
		}

		val output = mutableListOf<String>()
		var inInterface = false
		var interfaceInjected = false
		var peerSeen = false
		var allowedInjectedInPeer = false

		for (line in allLines) {
			val trimmed = line.trim()

			if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
				inInterface = trimmed.equals("[Interface]", ignoreCase = true)
				if (trimmed.equals("[Peer]", ignoreCase = true)) {
					peerSeen = true
				}
			}

			if (trimmed.startsWith("IncludedApplications", ignoreCase = true) ||
				trimmed.startsWith("ExcludedApplications", ignoreCase = true)
			) {
				continue
			}

			if (overrideAllowedIpsLine != null && trimmed.startsWith("AllowedIPs", ignoreCase = true)) {
				continue
			}

			output.add(line)

			if (inInterface && !interfaceInjected && appOverrideLine != null && trimmed.equals("[Interface]", ignoreCase = true)) {
				output.add(appOverrideLine)
				interfaceInjected = true
			}

			if (overrideAllowedIpsLine != null && !allowedInjectedInPeer && trimmed.equals("[Peer]", ignoreCase = true)) {
				output.add(overrideAllowedIpsLine)
				allowedInjectedInPeer = true
			}
		}

		if (appOverrideLine != null && !interfaceInjected) {
			throw IOException("В конфиге отсутствует секция [Interface]")
		}

		if (overrideAllowedIpsLine != null) {
			if (!peerSeen) {
				throw IOException("В конфиге отсутствует секция [Peer]")
			}
			if (!allowedInjectedInPeer) {
				throw IOException("Не удалось применить AllowedIPs для доменного режима")
			}
		}

		return output.joinToString("\n")
	}

	/**
	 * Resolve domain using public DNS (8.8.8.8) via UDP to avoid depending on system DNS
	 * which may not be available before VPN is up.
	 */
	private fun resolveDomains(domains: List<String>): List<String> {
		val uniqueDomains = domains
			.map(String::trim)
			.filter(String::isNotEmpty)
			.distinct()
		if (uniqueDomains.isEmpty()) {
			return emptyList()
		}

		val tasks = uniqueDomains.associateWith { domain ->
			dnsResolverExecutor.submit<List<String>> { resolveDomain(domain) }
		}
		val resolvedIps = linkedSetOf<String>()

		for ((domain, task) in tasks) {
			try {
				resolvedIps.addAll(task.get(6, TimeUnit.SECONDS))
			} catch (e: Exception) {
				task.cancel(true)
				android.util.Log.w("WG_SPLIT", "Failed to resolve domain $domain: ${e.javaClass.simpleName}: ${e.message}")
			}
		}

		return resolvedIps.toList()
	}

	private fun resolveDomain(domain: String): List<String> {
		val dnsIps = runCatching { dnsQuery(domain) }.getOrElse {
			android.util.Log.w("WG_SPLIT", "UDP DNS query failed for $domain: ${it.javaClass.simpleName}: ${it.message}")
			emptyList()
		}
		if (dnsIps.isNotEmpty()) {
			return dnsIps
		}

		android.util.Log.w("WG_SPLIT", "DNS query returned empty for $domain, falling back to InetAddress")
		return InetAddress.getAllByName(domain).mapNotNull { addr ->
			when (addr) {
				is Inet4Address -> "${addr.hostAddress}/32"
				is Inet6Address -> "${addr.hostAddress}/128"
				else -> null
			}
		}
	}

	/**
	 * Perform a simple A-record DNS query over UDP to 8.8.8.8:53
	 */
	private fun dnsQuery(domain: String): List<String> {
		val dnsServer = InetAddress.getByName("8.8.8.8")
		val query = buildDnsQuery(domain)

		DatagramSocket().use { socket ->
			socket.soTimeout = 5000

			// Send query
			val request = DatagramPacket(query, query.size, dnsServer, 53)
			socket.send(request)

			// Receive response
			val responseBuffer = ByteArray(512)
			val response = DatagramPacket(responseBuffer, responseBuffer.size)
			socket.receive(response)

			return parseDnsResponse(response.data, response.length)
		}
	}

	/**
	 * Build a simple DNS A-record query packet
	 */
	private fun buildDnsQuery(domain: String): ByteArray {
		val parts = domain.split(".")
		val buffer = ByteBuffer.allocate(512)

		// Transaction ID
		buffer.putShort(0x1234)
		// Flags: standard query
		buffer.putShort(0x0100)
		// Questions: 1
		buffer.putShort(1)
		// Answer RRs: 0
		buffer.putShort(0)
		// Authority RRs: 0
		buffer.putShort(0)
		// Additional RRs: 0
		buffer.putShort(0)

		// Query name
		for (part in parts) {
			buffer.put(part.length.toByte())
			buffer.put(part.toByteArray(Charsets.UTF_8))
		}
		buffer.put(0)

		// Query type: A (1)
		buffer.putShort(1)
		// Query class: IN (1)
		buffer.putShort(1)

		return buffer.array().copyOf(buffer.position())
	}

	/**
	 * Parse DNS response and extract IPv4 addresses
	 */
	private fun parseDnsResponse(data: ByteArray, length: Int): List<String> {
		val buffer = ByteBuffer.wrap(data, 0, length)
		val ips = mutableListOf<String>()

		// Skip header (12 bytes)
		if (length < 12) return ips
		buffer.position(12)

		// Read transaction ID and flags
		val transactionId = buffer.short
		val flags = buffer.short
		val questions = buffer.short.toInt() and 0xFFFF
		val answers = buffer.short.toInt() and 0xFFFF
		val authority = buffer.short.toInt() and 0xFFFF
		val additional = buffer.short.toInt() and 0xFFFF

		// Check for error response
		if ((flags.toInt() and 0x000F) != 0) {
			android.util.Log.w("WG_SPLIT", "DNS response error code: ${flags.toInt() and 0x000F}")
			return ips
		}

		// Skip questions section
		for (i in 0 until questions) {
			skipDnsName(buffer)
			buffer.position(buffer.position() + 4) // skip type and class
		}

		// Parse answers
		for (i in 0 until answers) {
			skipDnsName(buffer) // skip name
			if (buffer.remaining() < 10) break
			val type = buffer.short.toInt() and 0xFFFF
			val clazz = buffer.short.toInt() and 0xFFFF
			val ttl = buffer.int
			val rdLength = buffer.short.toInt() and 0xFFFF

			if (type == 1 && rdLength == 4) { // A record
				val ip = "${buffer.get().toInt() and 0xFF}.${buffer.get().toInt() and 0xFF}.${buffer.get().toInt() and 0xFF}.${buffer.get().toInt() and 0xFF}"
				ips.add("$ip/32")
			} else {
				// Skip other record types
				buffer.position(buffer.position() + rdLength)
			}
		}

		return ips
	}

	/**
	 * Skip a DNS name (compressed or uncompressed) in the buffer
	 */
	private fun skipDnsName(buffer: ByteBuffer) {
		while (true) {
			if (!buffer.hasRemaining()) return
			val len = buffer.get().toInt() and 0xFF
			if (len == 0) return
			if ((len and 0xC0) == 0xC0) {
				// Compression pointer
				if (buffer.hasRemaining()) buffer.get()
				return
			}
			buffer.position(buffer.position() + len)
		}
	}

	private fun computeAllowedIps(
		existingLines: List<String>,
		domainMode: SplitTunnelDomainMode,
		resolvedIps: List<String>,
	): String {
		if (domainMode == SplitTunnelDomainMode.ALL) {
			return if (existingLines.isEmpty()) "AllowedIPs = 0.0.0.0/0, ::/0" else existingLines.joinToString("\n")
		}

		// Parse base CIDRs from existing AllowedIPs lines
		val baseCidrs = if (existingLines.isEmpty()) {
			listOf("0.0.0.0/0", "::/0")
		} else {
			existingLines.flatMap { line ->
				val afterEquals = line.substringAfter("=", "").trim()
				if (afterEquals.isEmpty()) emptyList()
				else afterEquals.split(",").map { it.trim() }.filter { it.isNotEmpty() }
			}
		}

		return when (domainMode) {
			SplitTunnelDomainMode.INCLUDE -> {
				// Only route resolved IPs through tunnel
				"AllowedIPs = ${resolvedIps.joinToString(", ")}"
			}

			SplitTunnelDomainMode.EXCLUDE -> {
				// Route everything except resolved IPs through tunnel
				val excluded = resolvedIps.toSet()
				android.util.Log.d("WG_SPLIT", "EXCLUDE mode: baseCidrs=$baseCidrs, excluded=$excluded")
				val resultCidrs = subtractIpsFromCidrs(baseCidrs, excluded)
				android.util.Log.d("WG_SPLIT", "EXCLUDE mode: resultCidrs=$resultCidrs")
				val finalCidrs = if (resultCidrs.isEmpty()) {
					// Fallback: if subtraction emptied everything, keep base CIDRs
					baseCidrs
				} else {
					resultCidrs
				}
				// Filter out IPv6 ::/0 when in EXCLUDE mode to ensure excluded domains
				// don't leak through IPv6. IPv6 CIDR subtraction is not implemented.
				val noV6 = finalCidrs.filter { !it.startsWith("::/") }
				android.util.Log.d("WG_SPLIT", "EXCLUDE mode: noV6=$noV6")
				// If we have excluded IPs but no valid routes left, we can't exclude anything
				// In that case, route everything through VPN (the exclusion won't work for this domain)
				if (noV6.isEmpty()) {
					"AllowedIPs = 0.0.0.0/0"
				} else {
					"AllowedIPs = ${noV6.joinToString(", ")}"
				}
			}

			SplitTunnelDomainMode.ALL -> "AllowedIPs = 0.0.0.0/0, ::/0" // unreachable
		}
	}

	private fun subtractIpsFromCidrs(baseCidrs: List<String>, excludeIps: Set<String>): List<String> {
		// Separate v4 and v6
		val v4Cidrs = mutableListOf<Pair<Long, Int>>() // (network-as-long, prefix)
		val v6Result = mutableListOf<String>()

		for (cidr in baseCidrs) {
			val parts = cidr.split("/")
			if (parts.size != 2) continue
			val ip = parts[0].trim()
			val prefix = parts[1].trim().toIntOrNull() ?: continue

			if (ip.contains(":")) {
				// IPv6: keep as-is for simplicity (full IPv6 CIDR subtraction is very complex)
				val excludedV6 = excludeIps.filter { it.contains(":") }.map { it.substringBefore("/") }.toSet()
				if (excludedV6.isEmpty() || prefix == 0) {
					v6Result.add(cidr)
				} else {
					// For ::/0 with exclusions, keep ::/0 — we can't easily carve out IPv6
					v6Result.add(cidr)
				}
			} else {
				val netLong = ipv4ToLong(ip)
				if (netLong != null) {
					v4Cidrs.add(netLong to prefix)
				}
			}
		}

		// Extract v4 exclude IPs
		val v4Exclude = excludeIps
			.mapNotNull { it.substringBefore("/") }
			.mapNotNull { ipv4ToLong(it) }
			.toSet()

		val v4Result = mutableListOf<String>()
		for ((net, prefix) in v4Cidrs) {
			if (v4Exclude.isEmpty()) {
				v4Result.add(longToCidr(net, prefix))
				continue
			}
			v4Result.addAll(subtractIpFromCidr(net, prefix, v4Exclude))
		}

		return v4Result + v6Result
	}

	/**
	 * Subtract a set of IPs from a CIDR block. Recursively splits around each excluded IP.
	 */
	private fun subtractIpFromCidr(network: Long, prefix: Int, excludeIps: Set<Long>): List<String> {
		val mask = if (prefix == 0) 0L else (0xFFFFFFFFL shl (32 - prefix)) and 0xFFFFFFFFL
		val first = network and mask
		val last = if (prefix == 32) first else first or ((1L shl (32 - prefix)) - 1)

		val hits = excludeIps.filter { it in first..last }
		if (hits.isEmpty()) {
			return listOf(longToCidr(first, prefix))
		}

		if (prefix >= 32) {
			// Single IP — excluded, return nothing
			return emptyList()
		}

		// Split into two halves and recurse
		val newPrefix = prefix + 1
		val half = 1L shl (32 - newPrefix)
		val left = subtractIpFromCidr(first, newPrefix, excludeIps)
		val right = subtractIpFromCidr(first or half, newPrefix, excludeIps)
		return left + right
	}

	private fun ipv4ToLong(ip: String): Long? {
		val octets = ip.split(".")
		if (octets.size != 4) return null
		var result = 0L
		for (o in octets) {
			val v = o.toIntOrNull() ?: return null
			if (v !in 0..255) return null
			result = (result shl 8) or v.toLong()
		}
		return result
	}

	private fun longToCidr(network: Long, prefix: Int): String {
		val a = ((network shr 24) and 0xFF).toInt()
		val b = ((network shr 16) and 0xFF).toInt()
		val c = ((network shr 8) and 0xFF).toInt()
		val d = (network and 0xFF).toInt()
		return "$a.$b.$c.$d/$prefix"
	}



	private fun queryInstalledApps(): List<InstalledApp> {
		val packages = try {
			packageManager.getInstalledPackages(PackageManager.PackageInfoFlags.of(0))
		} catch (_: NoSuchMethodError) {
			@Suppress("DEPRECATION")
			packageManager.getInstalledPackages(0)
		}

		return packages.mapNotNull { packageInfo ->
			val pkg = packageInfo.packageName
			if (pkg == packageName) {
				return@mapNotNull null
			}
			if (packageManager.getLaunchIntentForPackage(pkg) == null) {
				return@mapNotNull null
			}

			val appInfo = try {
				packageManager.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
			} catch (_: NoSuchMethodError) {
				@Suppress("DEPRECATION")
				packageManager.getApplicationInfo(pkg, 0)
			} catch (_: PackageManager.NameNotFoundException) {
				return@mapNotNull null
			}

			val label = packageManager.getApplicationLabel(appInfo).toString().ifBlank { pkg }
			InstalledApp(label = label, packageName = pkg)
		}
			.distinctBy { it.packageName }
			.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER, InstalledApp::label).thenBy(InstalledApp::packageName))
	}

	private fun statusPayload(message: String? = null, connectedOverride: Boolean? = null): Map<String, Any> {
		val wgConnected = backend.getState(tunnel) == Tunnel.State.UP
		val singBoxConnected = singBoxManager.isRunning
		val connected = connectedOverride ?: (wgConnected || singBoxConnected)
		val payload = mutableMapOf<String, Any>(
			"connected" to connected,
			"tunnelName" to tunnel.name,
			"backend" to if (singBoxConnected) "sing-box" else "wireguard",
		)
		if (message != null) {
			payload["message"] = message
		}
		return payload
	}

	private fun requestNotificationPermissionIfNeeded() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
			return
		}

		if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
			return
		}

		if (notificationPermissionRequestInFlight) {
			return
		}

		notificationPermissionRequestInFlight = true
		requestPermissions(
			arrayOf(Manifest.permission.POST_NOTIFICATIONS),
			notificationPermissionRequestCode,
		)
	}

	private data class InstalledApp(
		val label: String,
		val packageName: String,
	)
}
