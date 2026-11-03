package org.reelbox.reelbox

import android.app.PictureInPictureParams
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Window-scoped brightness, system stream volume, ACTION_VIEW and Android PiP.
 * No overlay, storage, write-settings or broad media permissions are requested. */
class MainActivity : FlutterActivity() {
    private lateinit var mediaChannel: MethodChannel
    private var playerActive = false
    private var cast: ReelboxCast? = null
    private fun castBridge(): ReelboxCast = cast ?: ReelboxCast(this, mediaChannel).also { cast = it }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.reelbox/media")
        NativeMediaEvents.channel = mediaChannel
        mediaChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setPlayerActive" -> {
                        playerActive = call.argument<Boolean>("active") ?: false
                        result.success(null)
                    }
                    "isInPip" -> result.success(Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode)
                    "enterPip" -> result.success(enterPlayerPip())
                    "getVolume" -> {
                        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        result.success(if (max > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max else 0.0)
                    }
                    "setVolume" -> {
                        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                        val value = (call.argument<Number>("value")?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, (value * max).toInt(), 0)
                        result.success(null)
                    }
                    "getBrightness" -> result.success(window.attributes.screenBrightness.toDouble())
                    "getEffectiveBrightness" -> {
                        val windowValue = window.attributes.screenBrightness
                        val value = if (windowValue >= 0) windowValue.toDouble() else
                            android.provider.Settings.System.getInt(contentResolver,
                                android.provider.Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
                        result.success(value.coerceIn(0.0, 1.0))
                    }
                    "setBrightness" -> {
                        val value = call.argument<Number>("value")?.toFloat() ?: -1f
                        val attributes = window.attributes
                        attributes.screenBrightness = if (value < 0) -1f else value.coerceIn(0.01f, 1f)
                        window.attributes = attributes
                        result.success(null)
                    }
                    "backgroundPlayback" -> {
                        if (call.argument<Boolean>("enabled") == true) {
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 3041)
                            }
                            BackgroundPlaybackService.start(this, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                        } else BackgroundPlaybackService.stop(this)
                        result.success(null)
                    }
                    "backgroundPlaybackUpdate" -> {
                        BackgroundPlaybackService.update(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                        result.success(null)
                    }
                    "backgroundPlaybackStop" -> { BackgroundPlaybackService.stop(this); result.success(null) }
                    "castShowPicker" -> result.success(castBridge().showPicker())
                    "castGetState" -> result.success(castBridge().getState())
                    "castLoad" -> castBridge().load(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                    "castCommand" -> castBridge().command(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
                    "castDisconnect" -> { castBridge().disconnect(); result.success(null) }
                    "openExternal" -> result.success(NativeFileIntents(this).openExternal(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
                    "openDownloader" -> result.success(NativeFileIntents(this).openDownloader(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
                    "revealFile" -> result.success(NativeFileIntents(this).revealFile(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
                    "openEmbedded" -> {
                        val url = call.argument<String>("url").orEmpty()
                        require(NativeUrlPolicy.allowsRemote(url))
                        startActivity(Intent(this, EmbeddedVideoActivity::class.java).putExtra("url", url)
                            .putExtra("title", call.argument<String>("title").orEmpty()))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("MEDIA_PLATFORM", "Android could not perform this media operation.", null)
            }
        }
    }

    override fun onDestroy() {
        cast?.dispose()
        cast = null
        if (::mediaChannel.isInitialized && NativeMediaEvents.channel === mediaChannel) {
            BackgroundPlaybackService.stop(this)
            NativeMediaEvents.channel = null
            mediaChannel.setMethodCallHandler(null)
        }
        super.onDestroy()
    }

    private fun enterPlayerPip(): Boolean {
        if (Build.VERSION.SDK_INT < 26 || !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build())
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (playerActive) enterPlayerPip()
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        if (::mediaChannel.isInitialized) mediaChannel.invokeMethod("pipChanged", inPip)
    }
}
