package org.reelbox.reelbox

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

/** Only scoped content grants leave the app; never file:// or broad storage grants. */
class NativeFileIntents(private val activity: Activity) {
    private fun localFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOfNotNull(activity.filesDir, activity.cacheDir,
            activity.getExternalFilesDir(null), activity.externalCacheDir).map { it.canonicalFile }
        require(roots.any { file.path.startsWith(it.path + File.separator) } && file.isFile && file.canRead()) { "File is not in app-owned storage." }
        require(!file.name.endsWith(".apk", true) && !file.name.endsWith(".apks", true) && !file.name.endsWith(".xapk", true) && !file.name.endsWith(".aab", true))
        return file
    }

    private fun shareUri(file: File): Uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)

    private fun mediaUri(value: String): Uri {
        val parsed = Uri.parse(value)
        return when (parsed.scheme?.lowercase()) {
            "http", "https" -> { require(NativeUrlPolicy.allowsRemote(value)); parsed }
            "content" -> {
                require(!parsed.authority.isNullOrBlank())
                // Confirm this process really has read access; forwarding arbitrary provider URIs is forbidden.
                activity.contentResolver.openAssetFileDescriptor(parsed, "r")?.use { } ?: throw IllegalArgumentException("Unreadable content URI.")
                parsed
            }
            "file" -> shareUri(localFile(parsed.path ?: ""))
            null -> shareUri(localFile(value))
            else -> throw IllegalArgumentException("Unsupported media URI.")
        }
    }

    private fun grant(intent: Intent, uris: List<Uri>) {
        val content = uris.filter { it.scheme == "content" }
        if (content.isEmpty()) return
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.clipData = ClipData.newRawUri("Reelbox media", content.first()).also { clip ->
            content.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        }
    }

    private fun launch(intent: Intent, packageName: String?, title: String): Boolean {
        if (!packageName.isNullOrBlank() && packageName != "ask") {
            require(NativeUrlPolicy.safePackage(packageName))
            try { activity.startActivity(Intent(intent).setPackage(packageName)); return true }
            catch (_: ActivityNotFoundException) { /* Offer an installed alternative. */ }
        }
        return try {
            activity.startActivity(Intent.createChooser(Intent(intent).setPackage(null), title)); true
        } catch (_: ActivityNotFoundException) { false }
    }

    fun openExternal(args: Map<*, *>): Boolean {
        val uri = mediaUri(args["url"] as? String ?: "")
        val subtitle = (args["subtitleUrl"] as? String)?.takeIf { it.isNotBlank() }?.let { mediaUri(it) }
        val position = ((args["positionMs"] as? Number)?.toLong() ?: 0).coerceAtLeast(0)
        val requested = args["packageName"] as? String
        val target = when (requested?.lowercase()) {
            "vlc" -> "org.videolan.vlc"
            "mx", "mxplayer" -> "com.mxtech.videoplayer.ad"
            else -> requested
        }
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/*")
            .putExtra(Intent.EXTRA_TITLE, (args["title"] as? String).orEmpty().take(512))
        // VLC's public Android API uses a long position; MX Player uses int milliseconds.
        if (target?.startsWith("com.mxtech.") == true) intent.putExtra("position", position.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        else intent.putExtra("position", position)
        if (subtitle != null) {
            intent.putExtra("subtitles_location", subtitle.toString()) // VLC Android public API.
            intent.putExtra("subs", arrayOf(subtitle)) // MX Player public API.
            intent.putExtra("subs.enable", arrayOf(subtitle))
        }
        grant(intent, listOfNotNull(uri, subtitle))
        return launch(intent, target, "Open video with")
    }

    fun revealFile(args: Map<*, *>): Boolean {
        val file = localFile(args["path"] as? String ?: "")
        val uri = shareUri(file)
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
        // Shares/export via Android's scoped chooser (including installed document/save targets).
        val intent = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_TITLE, file.name)
        grant(intent, listOf(uri))
        return launch(intent, "ask", "Export ${file.name}")
    }

    fun openDownloader(args: Map<*, *>): Boolean {
        val url = args["url"] as? String ?: ""
        require(NativeUrlPolicy.allowsRemote(url))
        val requested = args["packageName"] as? String ?: "ask"
        val target = when (requested.lowercase()) {
            "adm" -> "com.dv.adm"
            "idm", "1dm" -> "idm.internet.download.manager"
            else -> requested
        }
        val name = (args["filename"] as? String).orEmpty().substringAfterLast('/').substringAfterLast('\\').take(240)
        require(!Regex("\\.(apk|apks|xapk|aab)$", RegexOption.IGNORE_CASE).containsMatchIn(name))
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(url), "application/octet-stream")
            .putExtra(Intent.EXTRA_TITLE, name)
        return launch(intent, target, "Send download to")
    }
}
