package com.example.wgfytunnel

import org.json.JSONArray
import org.json.JSONObject

/**
 * Generates sing-box JSON configuration from WireGuard config + split tunnel settings.
 */
object SingBoxConfig {
    private const val fakeIpRange = "198.18.0.0/15"
    private const val defaultDirectDns = "1.1.1.1"
    private const val defaultRemoteDns = "tls://8.8.8.8"
    private const val directTag = "direct"
    const val proxyTag = "proxy"
    private const val dnsLocalTag = "dns-local"
    private const val dnsDirectTag = "dns-direct"
    private const val dnsRemoteTag = "dns-remote"
    private const val dnsFakeTag = "dns-fake"


    fun buildConfig(
        wgConfig: WireGuardConfig,
        splitMode: SplitTunnelMode,
        selectedPackages: Set<String>,
        domainMode: SplitTunnelDomainMode,
        domainList: List<String>,
    ): JSONObject {
        val config = JSONObject()
        val directDnsAddress = primaryDirectDnsAddress(wgConfig)
        val remoteDnsAddress = primaryRemoteDnsAddress(wgConfig)
        val normalizedDomains = domainList
            .mapNotNull { normalizeDomainToken(it) }
            .distinct()
        val forcedDirectDomains = buildForcedDirectDomains(wgConfig, remoteDnsAddress)

        // Log configuration
        config.put("log", JSONObject().apply {
            put("level", "info")
            put("timestamp", true)
        })

        // DNS configuration
        config.put("dns", JSONObject().apply {
            put("fakeip", JSONObject().apply {
                put("enabled", true)
                put("inet4_range", fakeIpRange)
            })
            put("reverse_mapping", true)
            put("servers", JSONArray().apply {
                put(JSONObject().apply {
                    put("tag", dnsLocalTag)
                    put("address", "local")
                    put("detour", directTag)
                    put("strategy", "ipv4_only")
                })
                put(JSONObject().apply {
                    put("tag", dnsDirectTag)
                    put("address", directDnsAddress)
                    put("detour", directTag)
                    put("address_resolver", dnsLocalTag)
                    put("strategy", "ipv4_only")
                })
                put(JSONObject().apply {
                    put("tag", dnsRemoteTag)
                    put("address", remoteDnsAddress)
                    put("address_resolver", dnsDirectTag)
                    put("strategy", "ipv4_only")
                })
                put(JSONObject().apply {
                    put("tag", dnsFakeTag)
                    put("address", "fakeip")
                    put("strategy", "ipv4_only")
                })
            })
            put("rules", JSONArray().apply {
                if (forcedDirectDomains.isNotEmpty()) {
                    put(JSONObject().apply {
                        applyDomainRuleFields(this, forcedDirectDomains)
                        put("server", dnsDirectTag)
                    })
                }

                if (domainMode == SplitTunnelDomainMode.INCLUDE && normalizedDomains.isNotEmpty()) {
                    // In INCLUDE mode, use fakeip only for selected domains.
                    // Other domains should resolve to real IPs for direct routing.
                    put(JSONObject().apply {
                        applyDomainRuleFields(this, normalizedDomains)
                        put("server", dnsFakeTag)
                        put("disable_cache", true)
                    })
                    put(JSONObject().apply {
                        put("inbound", JSONArray().apply { put("tun-in") })
                        put("server", dnsDirectTag)
                    })
                } else {
                    // For full/exclude domain modes, fakeip for TUN traffic enables
                    // stable domain-based routing via reverse mapping.
                    put(JSONObject().apply {
                        put("inbound", JSONArray().apply { put("tun-in") })
                        put("server", dnsFakeTag)
                        put("disable_cache", true)
                    })
                }

                put(JSONObject().apply {
                    put("outbound", JSONArray().apply { put("any") })
                    put("server", dnsDirectTag)
                })
            })
            put("final", dnsRemoteTag)
            put("strategy", "ipv4_only")
        })

        // Inbounds - TUN interface
        config.put("inbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("type", "tun")
                put("tag", "tun-in")
                put("inet4_address", JSONArray().apply {
                    put("172.19.0.1/30")
                })
                put("mtu", wgConfig.mtu ?: 1420)
                put("auto_route", false)
                put("endpoint_independent_nat", true)
                put("stack", "mixed")
                put("domain_strategy", "ipv4_only")
                put("sniff", true)
                put("sniff_override_destination", true)
            })
        })

        // Outbounds
        config.put("outbounds", JSONArray().apply {
            // Direct outbound
            put(JSONObject().apply {
                put("type", directTag)
                put("tag", directTag)
            })

            // Block outbound
            put(JSONObject().apply {
                put("type", "block")
                put("tag", "block")
            })

            // DNS outbound
            put(JSONObject().apply {
                put("type", "dns")
                put("tag", "dns-out")
            })

            put(JSONObject().apply {
                put("type", "wireguard")
                put("tag", proxyTag)
                put("server", wgConfig.endpointHost)
                put("server_port", wgConfig.endpointPort)
                put("system_interface", false)
                put("local_address", JSONArray().apply {
                    wgConfig.addresses.forEach { put(it) }
                })
                put("private_key", wgConfig.privateKey)
                put("peer_public_key", wgConfig.publicKey)
                if (wgConfig.presharedKey != null) {
                    put("pre_shared_key", wgConfig.presharedKey)
                }
                put("mtu", wgConfig.mtu ?: 1420)
            })
        })

        // Route rules
        val routeRules = JSONArray()

        // DNS hijack rules for TUN traffic.
        routeRules.put(JSONObject().apply {
            put("port", JSONArray().apply { put(53) })
            put("action", "hijack-dns")
        })
        routeRules.put(JSONObject().apply {
            put("protocol", JSONArray().apply { put("dns") })
            put("action", "hijack-dns")
        })

        // Domain-based rules
        when (domainMode) {
            SplitTunnelDomainMode.INCLUDE -> {
                if (normalizedDomains.isNotEmpty()) {
                    routeRules.put(JSONObject().apply {
                        put("ip_cidr", JSONArray().apply { put(fakeIpRange) })
                        put("outbound", proxyTag)
                    })
                    routeRules.put(JSONObject().apply {
                        applyDomainRuleFields(this, normalizedDomains)
                        put("outbound", proxyTag)
                    })
                }
            }

            SplitTunnelDomainMode.EXCLUDE -> {
                if (normalizedDomains.isNotEmpty()) {
                    routeRules.put(JSONObject().apply {
                        applyDomainRuleFields(this, normalizedDomains)
                        put("outbound", directTag)
                    })
                }
            }

            SplitTunnelDomainMode.ALL -> {
                // No additional domain rules.
            }
        }

        config.put("route", JSONObject().apply {
            put("rules", routeRules)
            put("auto_detect_interface", true)
            put(
                "final",
                when (domainMode) {
                    SplitTunnelDomainMode.INCLUDE -> directTag
                    SplitTunnelDomainMode.EXCLUDE, SplitTunnelDomainMode.ALL -> proxyTag
                },
            )
        })

        return config
    }

    private fun primaryDirectDnsAddress(wgConfig: WireGuardConfig): String {
        return wgConfig.dns
            ?.split(',', ';')
            ?.asSequence()
            ?.map { it.trim() }
            ?.firstOrNull { it.isNotEmpty() }
            ?: defaultDirectDns
    }

    private fun primaryRemoteDnsAddress(wgConfig: WireGuardConfig): String {
        return defaultRemoteDns
    }

    private fun buildForcedDirectDomains(wgConfig: WireGuardConfig, remoteDnsAddress: String): List<String> {
        return buildList {
            if (!isIpLiteral(wgConfig.endpointHost)) {
                add("full:${wgConfig.endpointHost.lowercase()}")
            }
            extractHostForDnsResolver(remoteDnsAddress)?.takeIf { !isIpLiteral(it) }?.let {
                add("full:${it.lowercase()}")
            }
        }.distinct()
    }

    private fun applyDomainRuleFields(target: JSONObject, domains: List<String>) {
        val ruleSets = JSONArray()
        val fullDomains = JSONArray()
        val suffixDomains = JSONArray()
        val regexDomains = JSONArray()
        val keywordDomains = JSONArray()

        domains.forEach { domain ->
            when {
                domain.startsWith("geosite:") -> ruleSets.put(domain)
                domain.startsWith("full:") -> fullDomains.put(domain.removePrefix("full:"))
                domain.startsWith("domain:") -> suffixDomains.put(domain.removePrefix("domain:"))
                domain.startsWith("regexp:") -> regexDomains.put(domain.removePrefix("regexp:"))
                domain.startsWith("keyword:") -> keywordDomains.put(domain.removePrefix("keyword:"))
                else -> {
                    // Match both apex domain and subdomains for plain host input.
                    fullDomains.put(domain)
                    suffixDomains.put(domain)
                }
            }
        }

        if (ruleSets.length() > 0) target.put("rule_set", ruleSets)
        if (fullDomains.length() > 0) target.put("domain", fullDomains)
        if (suffixDomains.length() > 0) target.put("domain_suffix", suffixDomains)
        if (regexDomains.length() > 0) target.put("domain_regex", regexDomains)
        if (keywordDomains.length() > 0) target.put("domain_keyword", keywordDomains)
    }

    private fun normalizeDomainToken(raw: String): String? {
        val trimmed = raw.trim().lowercase()
        if (trimmed.isBlank()) return null

        // Keep advanced rule syntax untouched.
        if (
            trimmed.startsWith("geosite:") ||
            trimmed.startsWith("full:") ||
            trimmed.startsWith("domain:") ||
            trimmed.startsWith("regexp:") ||
            trimmed.startsWith("keyword:")
        ) {
            return trimmed
        }

        var host = trimmed
            .substringAfter("://", trimmed)
            .substringBefore('/')
            .substringBefore('?')
            .substringBefore('#')

        if (host.startsWith("[")) {
            host = host.substringAfter('[').substringBefore(']')
        } else if (host.count { it == ':' } == 1) {
            host = host.substringBefore(':')
        }

        host = host.removePrefix("*.").removePrefix(".")

        if (host.isBlank()) return null
        if (host.startsWith(".") || host.endsWith(".")) return null
        if (host.contains('/')) return null
        if (!host.contains('.')) return null

        return host
    }

    private fun extractHostForDnsResolver(address: String): String? {
        val normalized = address.substringAfter("://", address).substringBefore('/')
        if (normalized.isBlank()) return null
        if (normalized.startsWith("[")) {
            return normalized.substringAfter('[').substringBefore(']')
        }
        return normalized.substringBefore(':')
    }

    private fun isIpLiteral(value: String): Boolean {
        if (value.isBlank()) return false
        return value.matches(Regex("^[0-9.]+$")) || value.contains(':')
    }

    data class WireGuardConfig(
        val privateKey: String,
        val publicKey: String,
        val presharedKey: String?,
        val addresses: List<String>,
        val dns: String?,
        val mtu: Int?,
        val endpointHost: String,
        val endpointPort: Int,
        val allowedIPs: List<String>,
    )

    fun parseWireGuardConfig(configText: String): WireGuardConfig {
        val lines = configText.lines()

        var privateKey: String? = null
        var publicKey: String? = null
        var presharedKey: String? = null
        var addressStr: String? = null
        var dns: String? = null
        var mtu: Int? = null
        var endpoint: String? = null
        var allowedIPsStr: String = "0.0.0.0/0, ::/0"

        var inInterface = false
        var inPeer = false

        for (line in lines) {
            val trimmed = line.trim()
            when {
                trimmed.equals("[Interface]", ignoreCase = true) -> {
                    inInterface = true
                    inPeer = false
                }
                trimmed.equals("[Peer]", ignoreCase = true) -> {
                    inInterface = false
                    inPeer = true
                }
                inInterface && trimmed.startsWith("PrivateKey", ignoreCase = true) -> {
                    privateKey = trimmed.substringAfter("=").trim()
                }
                inInterface && trimmed.startsWith("Address", ignoreCase = true) -> {
                    addressStr = trimmed.substringAfter("=").trim()
                }
                inInterface && trimmed.startsWith("DNS", ignoreCase = true) -> {
                    dns = trimmed.substringAfter("=").trim()
                }
                inInterface && trimmed.startsWith("MTU", ignoreCase = true) -> {
                    mtu = trimmed.substringAfter("=").trim().toIntOrNull()
                }
                inPeer && trimmed.startsWith("PublicKey", ignoreCase = true) -> {
                    publicKey = trimmed.substringAfter("=").trim()
                }
                inPeer && trimmed.startsWith("PresharedKey", ignoreCase = true) -> {
                    presharedKey = trimmed.substringAfter("=").trim()
                }
                inPeer && trimmed.startsWith("Endpoint", ignoreCase = true) -> {
                    endpoint = trimmed.substringAfter("=").trim()
                }
                inPeer && trimmed.startsWith("AllowedIPs", ignoreCase = true) -> {
                    allowedIPsStr = trimmed.substringAfter("=").trim()
                }
            }
        }

        if (privateKey == null) throw IllegalArgumentException("Missing PrivateKey")
        if (publicKey == null) throw IllegalArgumentException("Missing PublicKey")
        if (endpoint == null) throw IllegalArgumentException("Missing Endpoint")

        val endpointParts = endpoint.split(":")
        val endpointHost = endpointParts[0]
        val endpointPort = endpointParts.getOrNull(1)?.toIntOrNull() ?: 51820

        val addresses = addressStr?.split(",")?.map { it.trim() } ?: listOf("10.0.0.2/32")
        val allowedIPs = allowedIPsStr.split(",").map { it.trim() }

        return WireGuardConfig(
            privateKey = privateKey,
            publicKey = publicKey,
            presharedKey = presharedKey,
            addresses = addresses,
            dns = dns,
            mtu = mtu,
            endpointHost = endpointHost,
            endpointPort = endpointPort,
            allowedIPs = allowedIPs,
        )
    }
}
