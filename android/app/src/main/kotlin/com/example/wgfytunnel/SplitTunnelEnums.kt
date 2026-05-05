package com.example.wgfytunnel

enum class SplitTunnelMode(val wireValue: String) {
    ALL("all"),
    INCLUDE("include"),
    EXCLUDE("exclude");

    companion object {
        fun fromWireValue(value: String): SplitTunnelMode {
            return entries.firstOrNull { it.wireValue == value } ?: ALL
        }
    }
}

enum class SplitTunnelDomainMode(val wireValue: String) {
    ALL("all"),
    INCLUDE("include"),
    EXCLUDE("exclude");

    companion object {
        fun fromWireValue(value: String): SplitTunnelDomainMode {
            return entries.firstOrNull { it.wireValue == value } ?: ALL
        }
    }
}
