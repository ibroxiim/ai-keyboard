package com.ibrokhim.aikeyboard.ai

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/** A file picked for "Tarjima uslubi" or a friend's notes: plain text or Markdown, read into the editor. */
object InstructionsImport {
    /** The file's text, tidied and cut at [Prompts.STYLE_LIMIT]; null when it is empty or not text at all. */
    fun text(bytes: ByteArray): String? {
        var text = decode(bytes) ?: return null
        text = text.replace("\r\n", "\n").replace('\r', '\n')
        // A UTF-8 byte-order mark survives decoding as U+FEFF, which `trim` does not count as whitespace.
        if (text.startsWith("﻿")) text = text.drop(1)
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        return trimmed.take(Prompts.STYLE_LIMIT)
    }

    private fun decode(bytes: ByteArray): String? {
        strict(Charsets.UTF_8, bytes)?.let { return it }
        // UTF-16 only with a byte-order mark: without one, any bytes "decode" into nonsense instead of failing.
        val bom = bytes.size >= 2 &&
            ((bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) || (bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()))
        return if (bom) strict(Charsets.UTF_16, bytes) else null
    }

    private fun strict(charset: Charset, bytes: ByteArray): String? = try {
        charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    } catch (e: CharacterCodingException) {
        null
    }
}
