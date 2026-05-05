package com.example.wgfytunnel

object LibcoreNativeShim {
    init {
        System.loadLibrary("singbox-exec")
    }

    external fun versionBoxLength(): Int

    external fun newSingBoxRef(configJson: String): Int
}