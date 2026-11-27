package com.lingjhf.vlc_player

import android.os.Handler
import android.os.Looper
import android.util.Size
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

internal object VlcNativeTransport {
    private val engines = ConcurrentHashMap<Long, VlcPlayerPlugin>()
    private val nextEngineId = AtomicLong(1)
    private val main = Handler(Looper.getMainLooper())
    private val codec = StandardMethodCodec.INSTANCE

    init {
        System.loadLibrary("vlc_player_transport")
    }

    fun attach(plugin: VlcPlayerPlugin): Long = nextEngineId.getAndIncrement().also {
        engines[it] = plugin
    }

    fun detach(engineId: Long) {
        engines.remove(engineId)
    }

    fun dvdVideoSize(path: String, title: Int): Size? {
        val dimensions = probeDvdVideoSize(path.toByteArray(Charsets.UTF_8), title)
        if (dimensions == 0L) return null
        return Size((dimensions ushr 32).toInt(), dimensions.toInt())
    }

    @JvmStatic
    fun enqueue(engineId: Long, replyPort: Long, callback: Long, bytes: ByteArray): Boolean {
        if (!engines.containsKey(engineId)) return false
        return main.post {
            val reply = Port(replyPort, callback)
            val result = object : MethodChannel.Result {
                override fun success(result: Any?) = reply.send(codec.encodeSuccessEnvelope(result))
                override fun error(code: String, message: String?, details: Any?) =
                    reply.send(codec.encodeErrorEnvelope(code, message, details))
                override fun notImplemented() = post(replyPort, callback, ByteArray(0))
            }
            val plugin = engines[engineId]
            if (plugin == null) {
                result.error("native_transport_unavailable", "The Flutter engine detached.", null)
                return@post
            }
            try {
                val call = codec.decodeMethodCall(ByteBuffer.wrap(bytes))
                plugin.handleCommand(call, result, callback)
            } catch (error: Exception) {
                result.error("vlc_error", error.message ?: error.javaClass.simpleName, null)
            }
        }
    }

    internal data class Port(val id: Long, val callback: Long) {
        fun sendEvent(event: Map<String, Any?>) = send(codec.encodeSuccessEnvelope(event))

        fun send(buffer: ByteBuffer) {
            buffer.flip()
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            post(id, callback, bytes)
        }
    }

    @JvmStatic
    private external fun post(port: Long, callback: Long, bytes: ByteArray)

    @JvmStatic
    private external fun probeDvdVideoSize(path: ByteArray, title: Int): Long
}
