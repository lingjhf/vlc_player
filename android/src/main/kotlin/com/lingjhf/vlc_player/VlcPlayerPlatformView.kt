package com.lingjhf.vlc_player

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

internal class VlcPlayerPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewIdentifier: Int,
    options: ArrayList<String>,
    private val onDispose: (Long, VlcPlayerPlatformView) -> Unit,
) : PlatformView, MediaPlayer.EventListener {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val videoLayout = VLCVideoLayout(context)
    private val libVLC = LibVLC(context, options)
    private val mediaPlayer = MediaPlayer(libVLC)
    private val eventChannel = EventChannel(messenger, "vlc_player/events/$viewIdentifier")
    private val streamHandler = StreamHandler()
    private val viewId = viewIdentifier.toLong()

    private var state = STATE_IDLE
    private var volume = 100
    private var playbackSpeed = 1.0f
    private var errorDescription: String? = null
    private var viewsAttached = false
    private var disposed = false

    init {
        videoLayout.setBackgroundColor(Color.BLACK)
        mediaPlayer.setEventListener(this)
        attachViewsIfNeeded()
        eventChannel.setStreamHandler(streamHandler)
    }

    override fun getView(): View = videoLayout

    fun setSource(
        uri: String,
        httpHeaders: Map<String, String>,
        autoPlay: Boolean,
        result: MethodChannel.Result,
    ) {
        if (!ensureActive(result)) {
            return
        }

        try {
            val media = Media(libVLC, Uri.parse(uri))
            httpHeaders.forEach { (name, value) ->
                if (isValidHeader(name, value)) {
                    media.addOption(":http-header=$name: $value")
                }
            }
            mediaPlayer.media = media
            media.release()
            errorDescription = null
            updateState(STATE_OPENING)
            if (autoPlay) {
                mediaPlayer.play()
            }
            result.success(null)
        } catch (error: RuntimeException) {
            errorDescription = error.message
            updateState(STATE_ERROR)
            result.error("set_source_failed", error.message, null)
        }
    }

    private fun isValidHeader(name: String, value: String): Boolean {
        return name.isNotBlank() &&
            !name.contains('\r') &&
            !name.contains('\n') &&
            !value.contains('\r') &&
            !value.contains('\n')
    }

    fun play(result: MethodChannel.Result) {
        if (!ensureActive(result)) {
            return
        }
        mediaPlayer.play()
        result.success(null)
    }

    fun pause(result: MethodChannel.Result) {
        if (!ensureActive(result)) {
            return
        }
        mediaPlayer.pause()
        result.success(null)
    }

    fun stop(result: MethodChannel.Result) {
        if (!ensureActive(result)) {
            return
        }
        mediaPlayer.stop()
        updateState(STATE_STOPPED)
        result.success(null)
    }

    fun seekTo(milliseconds: Long, result: MethodChannel.Result) {
        if (!ensureActive(result)) {
            return
        }
        mediaPlayer.time = milliseconds.coerceAtLeast(0L)
        sendSnapshot()
        result.success(null)
    }

    fun setVolume(volume: Int, result: MethodChannel.Result) {
        if (!ensureActive(result)) {
            return
        }
        this.volume = volume.coerceIn(0, 200)
        mediaPlayer.volume = this.volume
        sendSnapshot()
        result.success(null)
    }

    fun setPlaybackSpeed(speed: Float, result: MethodChannel.Result) {
        if (!ensureActive(result)) {
            return
        }
        playbackSpeed = speed.coerceAtLeast(0.01f)
        mediaPlayer.rate = playbackSpeed
        sendSnapshot()
        result.success(null)
    }

    override fun onFlutterViewAttached(flutterView: View) {
        if (!disposed) {
            attachViewsIfNeeded()
        }
    }

    override fun onFlutterViewDetached() {
        detachViewsIfNeeded()
    }

    override fun dispose() {
        if (disposed) {
            return
        }
        disposed = true
        eventChannel.setStreamHandler(null)
        mediaPlayer.setEventListener(null)
        mediaPlayer.stop()
        detachViewsIfNeeded()
        mediaPlayer.release()
        libVLC.release()
        onDispose(viewId, this)
    }

    override fun onEvent(event: MediaPlayer.Event) {
        when (event.type) {
            MediaPlayer.Event.Opening -> updateState(STATE_OPENING)
            MediaPlayer.Event.Buffering -> updateState(STATE_BUFFERING)
            MediaPlayer.Event.Playing -> updateState(STATE_PLAYING)
            MediaPlayer.Event.Paused -> updateState(STATE_PAUSED)
            MediaPlayer.Event.Stopped -> updateState(STATE_STOPPED)
            MediaPlayer.Event.EndReached -> updateState(STATE_ENDED)
            MediaPlayer.Event.EncounteredError -> {
                errorDescription = "VLC encountered an error while playing the media."
                updateState(STATE_ERROR)
            }
            MediaPlayer.Event.TimeChanged,
            MediaPlayer.Event.LengthChanged,
            -> sendSnapshot()
        }
    }

    private fun updateState(state: String) {
        this.state = state
        sendSnapshot()
    }

    private fun attachViewsIfNeeded() {
        if (!viewsAttached) {
            mediaPlayer.attachViews(videoLayout, null, false, false)
            viewsAttached = true
        }
    }

    private fun detachViewsIfNeeded() {
        if (viewsAttached) {
            mediaPlayer.detachViews()
            viewsAttached = false
        }
    }

    private fun ensureActive(result: MethodChannel.Result): Boolean {
        if (!disposed) {
            return true
        }
        result.error("disposed", "The vlc_player has been disposed.", null)
        return false
    }

    private fun sendSnapshot() {
        if (disposed) {
            return
        }

        val event = HashMap<String, Any>()
        event["state"] = state
        event["position"] = mediaPlayer.time.coerceAtLeast(0L)
        event["duration"] = mediaPlayer.length.coerceAtLeast(0L)
        event["volume"] = volume
        event["playbackSpeed"] = playbackSpeed.toDouble()
        errorDescription?.let {
            event["errorDescription"] = it
        }
        streamHandler.send(event)
    }

    private inner class StreamHandler : EventChannel.StreamHandler {
        private var events: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            this.events = events
            sendSnapshot()
        }

        override fun onCancel(arguments: Any?) {
            events = null
        }

        fun send(event: Map<String, Any>) {
            val eventSink = events ?: return
            mainHandler.post {
                if (!disposed && events === eventSink) {
                    eventSink.success(event)
                }
            }
        }
    }

    private companion object {
        const val STATE_IDLE = "idle"
        const val STATE_OPENING = "opening"
        const val STATE_BUFFERING = "buffering"
        const val STATE_PLAYING = "playing"
        const val STATE_PAUSED = "paused"
        const val STATE_STOPPED = "stopped"
        const val STATE_ENDED = "ended"
        const val STATE_ERROR = "error"
    }
}
