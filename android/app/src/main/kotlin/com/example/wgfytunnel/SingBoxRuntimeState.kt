package com.example.wgfytunnel

import android.content.Context
import android.os.SystemClock
import java.io.File

object SingBoxRuntimeState {
    private const val STATE_STARTING = "starting"
    private const val STATE_STARTED = "started"
    private const val STATE_STOPPED = "stopped"
    private const val STATE_FAILED_PREFIX = "failed:"
    private const val FILE_NAME = "singbox_runtime_state.txt"

    fun reset(context: Context) {
        write(context, STATE_STARTING)
    }

    fun started(context: Context) {
        write(context, STATE_STARTED)
    }

    fun failed(context: Context, message: String) {
        write(context, STATE_FAILED_PREFIX + message.replace('\n', ' ').trim())
    }

    fun stopped(context: Context) {
        val current = read(context)
        if (current != null && current.startsWith(STATE_FAILED_PREFIX)) {
            return
        }
        write(context, STATE_STOPPED)
    }

    fun isRunning(context: Context): Boolean {
        return read(context) == STATE_STARTED
    }

    fun await(context: Context, timeoutMs: Long): String? {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            when (val state = read(context)) {
                STATE_STARTED -> return null
                null, "", STATE_STARTING -> Thread.sleep(100)
                STATE_STOPPED -> return "sing-box остановлен"
                else -> {
                    if (state.startsWith(STATE_FAILED_PREFIX)) {
                        return state.removePrefix(STATE_FAILED_PREFIX).ifBlank {
                            "Не удалось запустить sing-box"
                        }
                    }
                    Thread.sleep(100)
                }
            }
        }
        return "Истекло ожидание запуска sing-box"
    }

    private fun file(context: Context): File {
        return File(context.filesDir, FILE_NAME)
    }

    private fun read(context: Context): String? {
        return runCatching {
            file(context).takeIf { it.exists() }?.readText()?.trim()
        }.getOrNull()
    }

    private fun write(context: Context, value: String) {
        runCatching {
            file(context).writeText(value)
        }
    }
}