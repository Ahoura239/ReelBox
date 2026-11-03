package org.reelbox.reelbox

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.mediarouter.app.MediaRouteButton
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaTrack
import com.google.android.gms.cast.framework.CastButtonFactory
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.SessionProvider
import com.google.android.gms.cast.framework.media.CastMediaOptions
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.api.PendingResult
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

/** Default Media Receiver: no server credentials, DRM keys, or custom receiver app. */
class ReelboxCastOptions : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions = CastOptions.Builder()
        .setReceiverApplicationId(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID)
        .setCastMediaOptions(CastMediaOptions.Builder().setNotificationOptions(null).setMediaSessionEnabled(false).build())
        .setEnableReconnectionService(false)
        .build()
    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null
}

/** Support-fragment host kept separate from the Flutter activity/theme. */
class CastPickerActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "Cast video"
        val button = MediaRouteButton(this)
        button.contentDescription = "Choose a Cast receiver"
        setContentView(button, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        try {
            CastButtonFactory.setUpMediaRouteButton(this, button)
            if (savedInstanceState == null) button.post { button.showDialog() }
        } catch (_: Exception) {
            android.widget.Toast.makeText(this, "Google Cast is unavailable on this device.", android.widget.Toast.LENGTH_LONG).show()
            finish()
        }
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
    }
    override fun onSupportNavigateUp(): Boolean { finish(); return true }
}

class ReelboxCast(private val activity: MainActivity, private val channel: MethodChannel) {
    private var context: CastContext? = null
    private val handler = Handler(Looper.getMainLooper())
    private var disposed = false
    private val poll = object : Runnable {
        override fun run() {
            if (disposed) return
            emit()
            handler.postDelayed(this, 1000)
        }
    }
    private val listener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) = emit()
        override fun onSessionStarted(session: CastSession, id: String) = emit()
        override fun onSessionStartFailed(session: CastSession, error: Int) = emit()
        override fun onSessionEnding(session: CastSession) = emit()
        override fun onSessionEnded(session: CastSession, error: Int) = emit()
        override fun onSessionResuming(session: CastSession, id: String) = emit()
        override fun onSessionResumed(session: CastSession, suspended: Boolean) = emit()
        override fun onSessionResumeFailed(session: CastSession, error: Int) = emit()
        override fun onSessionSuspended(session: CastSession, reason: Int) = emit()
    }

    @Suppress("DEPRECATION")
    private fun initialize(): CastContext {
        check(!disposed)
        return context ?: CastContext.getSharedInstance(activity).also {
            context = it
            it.sessionManager.addSessionManagerListener(listener, CastSession::class.java)
            handler.post(poll)
        }
    }

    fun state(): Map<String, Any> {
        val session = context?.sessionManager?.currentCastSession
        val connected = session?.isConnected == true
        val client = if (connected) session?.remoteMediaClient else null
        return mapOf(
            "connected" to connected,
            "playing" to (client?.isPlaying == true),
            "positionMs" to (client?.approximateStreamPosition ?: 0L),
            "durationMs" to (client?.streamDuration ?: 0L),
            "deviceName" to (session?.castDevice?.friendlyName ?: "")
        )
    }

    private fun emit() { if (!disposed) channel.invokeMethod("castChanged", state()) }

    fun showPicker(): Boolean {
        initialize()
        activity.startActivity(Intent(activity, CastPickerActivity::class.java))
        return true
    }

    fun getState(): Map<String, Any> { initialize(); return state() }

    private fun remote(): RemoteMediaClient = initialize().sessionManager.currentCastSession
        ?.takeIf { it.isConnected }?.remoteMediaClient
        ?: throw IllegalStateException("No Cast receiver is connected.")

    fun load(args: Map<*, *>, result: MethodChannel.Result) {
        val url = args["url"] as? String ?: ""
        require(NativeUrlPolicy.allowsRemote(url)) { "Unsupported Cast URL." }
        val subtitle = (args["subtitleUrl"] as? String)?.takeIf { it.isNotBlank() }
        require(subtitle == null || NativeUrlPolicy.allowsRemote(subtitle)) { "Unsupported subtitle URL." }
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
            putString(MediaMetadata.KEY_TITLE, (args["title"] as? String).orEmpty().take(512))
        }
        val contentType = (args["contentType"] as? String)?.takeIf { it.isNotBlank() } ?: when {
            android.net.Uri.parse(url).path.orEmpty().endsWith(".m3u8", true) -> "application/x-mpegURL"
            android.net.Uri.parse(url).path.orEmpty().endsWith(".mpd", true) -> "application/dash+xml"
            else -> "video/mp4"
        }
        val info = MediaInfo.Builder(url).setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(contentType).setMetadata(metadata)
        if (subtitle != null) info.setMediaTracks(listOf(MediaTrack.Builder(1, MediaTrack.TYPE_TEXT)
            .setContentId(subtitle).setContentType("text/vtt").setSubtype(MediaTrack.SUBTYPE_SUBTITLES)
            .setName("Subtitles").build()))
        val request = MediaLoadRequestData.Builder().setMediaInfo(info.build()).setAutoplay(true)
            .setCurrentTime((args["positionMs"] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0)
        if (subtitle != null) request.setActiveTrackIds(longArrayOf(1))
        complete(remote().load(request.build()), result)
    }

    fun command(args: Map<*, *>, result: MethodChannel.Result) {
        val client = remote()
        val request = when (args["action"] as? String) {
            "play" -> client.play()
            "pause" -> client.pause()
            "stop" -> client.stop()
            "seek" -> client.seek(MediaSeekOptions.Builder()
                .setPosition((args["positionMs"] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0).build())
            "volume" -> client.setStreamVolume((args["value"] as? Number)?.toDouble()?.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 1.0)
            else -> throw IllegalArgumentException("Unknown Cast command.")
        }
        complete(request, result)
    }

    private fun complete(request: PendingResult<RemoteMediaClient.MediaChannelResult>, result: MethodChannel.Result) {
        request.setResultCallback({ response ->
            if (response.status.isSuccess) result.success(true)
            else result.error("CAST_RECEIVER", "The Cast receiver rejected or timed out this operation.", response.status.statusCode)
            emit()
        }, 20, TimeUnit.SECONDS)
    }

    fun disconnect() { initialize().sessionManager.endCurrentSession(true); emit() }
    fun dispose() {
        disposed = true
        handler.removeCallbacksAndMessages(null)
        context?.sessionManager?.removeSessionManagerListener(listener, CastSession::class.java)
        context = null
    }
}
