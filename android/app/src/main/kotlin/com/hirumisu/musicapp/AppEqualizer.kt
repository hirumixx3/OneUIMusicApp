package com.hirumisu.musicapp

import android.media.audiofx.Equalizer
import kotlin.math.max
import kotlin.math.min

object AppEqualizer {
    private var equalizer: Equalizer? = null
    private var sessionId: Int = -1
    private var supportedCache: Boolean? = null
    private var desiredEnabled: Boolean = true
    private val desiredBandLevels = mutableMapOf<Short, Short>()

    @Synchronized
    fun isSupported(): Boolean {
        supportedCache?.let { return it }
        supportedCache = try {
            val probe = Equalizer(0, 0)
            probe.release()
            true
        } catch (_: Throwable) {
            false
        }
        return supportedCache == true
    }

    @Synchronized
    fun attachToSession(newSessionId: Int): Map<String, Any?> {
        if (!isSupported()) {
            return mapOf(
                "supported" to false,
                "attached" to false,
                "enabled" to false,
                "bands" to emptyList<Map<String, Any?>>()
            )
        }
        if (newSessionId <= 0) {
            return snapshot(attached = false)
        }
        if (equalizer == null || sessionId != newSessionId) {
            releaseInternal()
            equalizer = Equalizer(0, newSessionId)
            sessionId = newSessionId
            applyDesiredState()
        }
        return snapshot(attached = true)
    }

    @Synchronized
    fun setEnabled(enabled: Boolean): Map<String, Any?> {
        desiredEnabled = enabled
        equalizer?.enabled = enabled
        return snapshot(attached = equalizer != null)
    }

    @Synchronized
    fun setBandLevel(bandIndex: Int, level: Int): Map<String, Any?> {
        val eq = equalizer
        val band = bandIndex.toShort()
        desiredBandLevels[band] = level.toShort()
        if (eq != null && band.toInt() in 0 until eq.numberOfBands.toInt()) {
            val range = eq.bandLevelRange
            val clamped = level.coerceIn(range[0].toInt(), range[1].toInt()).toShort()
            eq.setBandLevel(band, clamped)
            desiredBandLevels[band] = clamped
        }
        return snapshot(attached = eq != null)
    }

    @Synchronized
    fun reset(): Map<String, Any?> {
        desiredBandLevels.clear()
        val eq = equalizer
        if (eq != null) {
            for (bandIndex in 0 until eq.numberOfBands.toInt()) {
                eq.setBandLevel(bandIndex.toShort(), 0)
            }
        }
        return snapshot(attached = eq != null)
    }

    @Synchronized
    fun getState(): Map<String, Any?> = snapshot(attached = equalizer != null)

    private fun applyDesiredState() {
        val eq = equalizer ?: return
        eq.enabled = desiredEnabled
        val range = eq.bandLevelRange
        for (bandIndex in 0 until eq.numberOfBands.toInt()) {
            val band = bandIndex.toShort()
            val desired = desiredBandLevels[band]
            if (desired != null) {
                val clamped = desired.toInt().coerceIn(range[0].toInt(), range[1].toInt()).toShort()
                eq.setBandLevel(band, clamped)
                desiredBandLevels[band] = clamped
            }
        }
    }

    private fun snapshot(attached: Boolean): Map<String, Any?> {
        val eq = equalizer
        val bands = ArrayList<Map<String, Any?>>()
        if (eq != null) {
            val range = eq.bandLevelRange
            for (bandIndex in 0 until eq.numberOfBands.toInt()) {
                val band = bandIndex.toShort()
                bands.add(
                    mapOf(
                        "index" to bandIndex,
                        "centerMilliHz" to eq.getCenterFreq(band).toInt(),
                        "minLevel" to range[0].toInt(),
                        "maxLevel" to range[1].toInt(),
                        "level" to eq.getBandLevel(band).toInt(),
                    )
                )
            }
        }
        return mapOf(
            "supported" to isSupported(),
            "attached" to attached,
            "enabled" to desiredEnabled,
            "sessionId" to if (sessionId > 0) sessionId else null,
            "bands" to bands,
        )
    }

    private fun releaseInternal() {
        try {
            equalizer?.release()
        } catch (_: Throwable) {
        }
        equalizer = null
        sessionId = -1
    }
}
