package com.example.wgfytunnel

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executor

internal const val MAX_CONFIG_IMPORT_BYTES = 1024L * 1024L

internal class ConfigFileTooLargeException : IOException("Configuration file is too large")

internal fun copyConfigWithLimit(
    input: InputStream,
    output: OutputStream,
    maxBytes: Long = MAX_CONFIG_IMPORT_BYTES,
): Long {
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var totalBytes = 0L

    while (true) {
        val bytesRead = input.read(buffer)
        if (bytesRead < 0) {
            return totalBytes
        }

        totalBytes += bytesRead
        if (totalBytes > maxBytes) {
            throw ConfigFileTooLargeException()
        }
        output.write(buffer, 0, bytesRead)
    }
}

internal fun sanitizeConfigFileName(displayName: String?): String {
    val leafName = displayName
        ?.substringAfterLast('/')
        ?.substringAfterLast('\\')
        .orEmpty()
    val sanitized = leafName
        .filter { character -> character.code >= 32 && character != '/' && character != '\\' }
        .trim()
        .take(120)

    return if (sanitized.isBlank() || sanitized == "." || sanitized == "..") {
        "imported.conf"
    } else {
        sanitized
    }
}

class ConfigFilePicker(
    private val activity: Activity,
    private val executor: Executor,
) {
    private data class SelectedConfigFile(
        val file: File,
        val displayName: String,
    )

    companion object {
        private const val requestCode = 1003
        private const val cacheDirectoryName = "selected_configs"
    }

    private var pendingResult: MethodChannel.Result? = null

    fun open(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error(
                "CONFIG_PICKER_BUSY",
                "A configuration file picker is already open",
                null,
            )
            return
        }

        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            type = "*/*"
        }

        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pendingResult = null
            result.error("CONFIG_PICKER_FAILED", error.message, null)
        }
    }

    fun handleActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != requestCode) {
            return false
        }

        val result = pendingResult
        pendingResult = null
        if (result == null) {
            return true
        }
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return true
        }

        val uri = data?.data
        if (uri == null) {
            result.error("CONFIG_FILE_READ_FAILED", "No file was selected", null)
            return true
        }

        executor.execute {
            try {
                val selectedFile = copySelectedFileToCache(uri)
                activity.runOnUiThread {
                    result.success(
                        mapOf(
                            "path" to selectedFile.file.path,
                            "name" to selectedFile.displayName,
                        ),
                    )
                }
            } catch (_: ConfigFileTooLargeException) {
                activity.runOnUiThread {
                    result.error(
                        "CONFIG_FILE_TOO_LARGE",
                        "Configuration files must not exceed 1 MB",
                        null,
                    )
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("CONFIG_FILE_READ_FAILED", error.message, null)
                }
            }
        }
        return true
    }

    private fun copySelectedFileToCache(uri: Uri): SelectedConfigFile {
        val contentResolver = activity.contentResolver
        var displayName: String? = null
        var declaredSize: Long? = null
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    displayName = cursor.getString(nameIndex)
                }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    declaredSize = cursor.getLong(sizeIndex)
                }
            }
        }

        declaredSize?.let { size ->
            if (size > MAX_CONFIG_IMPORT_BYTES) {
                throw ConfigFileTooLargeException()
            }
        }

        val cacheDirectory = File(activity.cacheDir, cacheDirectoryName)
        if (!cacheDirectory.exists() && !cacheDirectory.mkdirs()) {
            throw IOException("Failed to create the configuration import cache")
        }

        val safeDisplayName = sanitizeConfigFileName(displayName)
        val selectedFile = File.createTempFile("selected_", ".tmp", cacheDirectory)
        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IOException("Failed to open the selected file")
            input.buffered().use { inputStream ->
                selectedFile.outputStream().buffered().use { outputStream ->
                    copyConfigWithLimit(inputStream, outputStream)
                }
            }
        } catch (error: Exception) {
            selectedFile.delete()
            throw error
        }

        return SelectedConfigFile(selectedFile, safeDisplayName)
    }
}
