package com.example.wgfytunnel

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ConfigFilePickerTest {
    @Test
    fun copyConfigWithLimitCopiesAValidConfig() {
        val inputBytes = "[Interface]\nPrivateKey = test".toByteArray()
        val output = ByteArrayOutputStream()

        val copiedBytes = copyConfigWithLimit(ByteArrayInputStream(inputBytes), output)

        assertEquals(inputBytes.size.toLong(), copiedBytes)
        assertArrayEquals(inputBytes, output.toByteArray())
    }

    @Test(expected = ConfigFileTooLargeException::class)
    fun copyConfigWithLimitRejectsContentAboveTheLimit() {
        val inputBytes = ByteArray(1025)

        copyConfigWithLimit(
            ByteArrayInputStream(inputBytes),
            ByteArrayOutputStream(),
            maxBytes = 1024,
        )
    }

    @Test
    fun sanitizeConfigFileNameRemovesProviderPathSegments() {
        assertEquals("client.conf", sanitizeConfigFileName("../../client.conf"))
        assertEquals("imported.conf", sanitizeConfigFileName(".."))
    }
}
