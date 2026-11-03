package org.reelbox.reelbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** The existing Flutter engine/Player owns decoding and is the sole event consumer. */
object NativeMediaEvents {
    var channel: MethodChannel? = null
    fun action(action: String, positionMs: Long? = null) {
        val arguments = mutableMapOf<String, Any>("action" to action)
        if (positionMs != null) arguments["positionMs"] = positionMs
        Handler(Looper.getMainLooper()).post { channel?.invokeMethod("mediaAction", arguments) }
    }
}

/** Foreground lifecycle/session/notification bridge. Deliberately contains NO decoder. */
class BackgroundPlaybackService : Service() {
    companion object {
        private const val CHANNEL = "reelbox_playback"
        private const val NOTIFICATION_ID = 3041
        private const val UPDATE = "org.reelbox.app.UPDATE_PLAYBACK"
        private const val CONTROL = "org.reelbox.app.MEDIA_CONTROL"
        private var running: BackgroundPlaybackService? = null

        fun start(context: Context, args: Map<*, *>) {
            require(NativeMediaEvents.channel != null) { "No active Flutter media owner." }
            val intent = Intent(context, BackgroundPlaybackService::class.java).setAction(UPDATE)
            val snapshot = PlaybackSnapshot.from(args)
            intent.putExtra("title", snapshot.title).putExtra("playing", snapshot.playing)
                .putExtra("positionMs", snapshot.positionMs).putExtra("durationMs", snapshot.durationMs)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
        fun update(args: Map<*, *>) { running?.applySnapshot(PlaybackSnapshot.from(args, running!!.snapshot)) }
        fun stop(context: Context) { context.stopService(Intent(context, BackgroundPlaybackService::class.java)) }
    }

    private lateinit var session: MediaSession
    private lateinit var audio: AudioManager
    private var snapshot = PlaybackSnapshot()
    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false
    private var interrupted = false
    private var resumeOnFocus = false
    private var noisyRegistered = false
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                interrupted = false
                if (resumeOnFocus) NativeMediaEvents.action("play")
                resumeOnFocus = false
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                resumeOnFocus = snapshot.playing
                interrupted = true
                NativeMediaEvents.action("pause")
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                interrupted = false
                resumeOnFocus = false
                abandonFocus()
                NativeMediaEvents.action("pause")
            }
        }
    }
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) NativeMediaEvents.action("pause")
        }
    }

    override fun onCreate() {
        super.onCreate()
        running = this
        audio = getSystemService(AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= 26) {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(
                NotificationChannel(CHANNEL, "Background playback", NotificationManager.IMPORTANCE_LOW)
            )
        }
        session = MediaSession(this, "ReelboxPlayback").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = NativeMediaEvents.action("play")
                override fun onPause() = NativeMediaEvents.action("pause")
                override fun onStop() { NativeMediaEvents.action("stop"); stopSelf() }
                override fun onSeekTo(pos: Long) = NativeMediaEvents.action("seek", pos.coerceAtLeast(0))
                override fun onSkipToNext() = NativeMediaEvents.action("next")
                override fun onSkipToPrevious() = NativeMediaEvents.action("previous")
            }, Handler(Looper.getMainLooper()))
            isActive = true
        }
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(noisy, filter)
        noisyRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (NativeMediaEvents.channel == null || intent == null) { stopSelf(); return START_NOT_STICKY }
        if (intent.action == CONTROL) {
            val action = intent.getStringExtra("action")
            if (action in listOf("play", "pause", "stop", "next", "previous")) NativeMediaEvents.action(action!!)
            if (action == "stop") stopSelf()
        } else if (intent.action == UPDATE) {
            snapshot = PlaybackSnapshot.from(mapOf(
                "title" to intent.getStringExtra("title"), "playing" to intent.getBooleanExtra("playing", false),
                "positionMs" to intent.getLongExtra("positionMs", 0), "durationMs" to intent.getLongExtra("durationMs", 0)
            ), snapshot)
            // Android 15 audio-focus eligibility requires foreground state BEFORE focus request.
            updateSession()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(NOTIFICATION_ID, notification())
            updateFocus()
        }
        return START_NOT_STICKY
    }

    private fun applySnapshot(value: PlaybackSnapshot) {
        snapshot = value
        updateSession()
        updateFocus()
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification())
    }

    private fun updateSession() {
        session.setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, snapshot.title)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, snapshot.durationMs).build())
        session.setPlaybackState(PlaybackState.Builder().setActions(
            PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_STOP or PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        ).setState(if (snapshot.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
            snapshot.positionMs, if (snapshot.playing) 1f else 0f).build())
    }

    @Suppress("DEPRECATION")
    private fun updateFocus() {
        if (!snapshot.playing) { if (!interrupted) abandonFocus(); return }
        if (focusHeld) return
        val granted = if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                .setWillPauseWhenDucked(true).setOnAudioFocusChangeListener(focusListener).build()
            focusRequest = request
            audio.requestAudioFocus(request)
        } else audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        focusHeld = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!focusHeld) NativeMediaEvents.action("pause")
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { audio.abandonAudioFocusRequest(it) }
        else if (focusHeld) audio.abandonAudioFocus(focusListener)
        focusHeld = false
        focusRequest = null
    }

    private fun control(action: String): PendingIntent = PendingIntent.getService(this, action.hashCode(),
        Intent(this, BackgroundPlaybackService::class.java).setAction(CONTROL).putExtra("action", action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun notification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return builder.setSmallIcon(R.drawable.ic_playback).setContentTitle(snapshot.title).setContentText("Reelbox")
            .setContentIntent(open).setVisibility(Notification.VISIBILITY_PUBLIC).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT).setOngoing(snapshot.playing)
            .setDeleteIntent(control("stop"))
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_previous, "Previous", control("previous")).build())
            .addAction(Notification.Action.Builder(if (snapshot.playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (snapshot.playing) "Pause" else "Play", control(if (snapshot.playing) "pause" else "play")).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_next, "Next", control("next")).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "Stop", control("stop")).build())
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) { NativeMediaEvents.action("stop"); stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() {
        if (running === this) running = null
        abandonFocus()
        if (noisyRegistered) unregisterReceiver(noisy)
        session.isActive = false
        session.release()
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
