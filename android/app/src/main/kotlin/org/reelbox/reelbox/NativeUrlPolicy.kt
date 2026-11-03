package org.reelbox.reelbox

import java.net.URI
import java.net.URLDecoder
import java.text.Normalizer
import java.util.Locale

/** Outgoing media/browser policy only; never applied to catalog API traffic. */
object NativeUrlPolicy {
    private val forbiddenHosts = listOf("t.me", "telegram.me", "telegram.org", "telegra.ph", "telegram.dog")
    private val forbiddenPath = Regex("(^|[/_.?&=\\-])(apk|apks|xapk|aab|update|updates|updater|version|versions|support|contact|news|shop|store|telegram|subscribe|subscription|payment|login|register|drm|license)([/_.?&=\\-]|$)")
    private val formatting = Regex("[\\p{Cf}\\u064b-\\u065f\\u0670\\u06d6-\\u06ed]")
    private val entities = Regex("&#(x[0-9a-f]+|[0-9]+);", RegexOption.IGNORE_CASE)
    private fun decode(value: String): String {
        var decoded = value
        repeat(3) { decoded = URLDecoder.decode(decoded, "UTF-8") }
        return entities.replace(decoded) { match ->
            val token = match.groupValues[1]
            val number = if (token.startsWith("x", true)) token.drop(1).toIntOrNull(16) else token.toIntOrNull()
            if (number != null && Character.isValidCodePoint(number)) String(Character.toChars(number)) else ""
        }.replace("&amp;", "&").replace("&nbsp;", " ")
    }
    private fun normal(value: String): String = Normalizer.normalize(decode(value), Normalizer.Form.NFKC)
        .lowercase(Locale.ROOT).replace('ي', 'ی').replace('ى', 'ی').replace('ك', 'ک').replace(formatting, "")

    fun allowsRemote(value: String): Boolean = try {
        val uri = URI(value)
        val scheme = uri.scheme?.lowercase(Locale.ROOT)
        val host = uri.host?.lowercase(Locale.ROOT)?.trimEnd('.') ?: ""
        if (scheme !in listOf("http", "https") || host.isBlank() || uri.rawUserInfo != null || value.any { it.code <= 32 || it.code == 127 }) false
        else {
            val decoded = normal(value)
            val compact = decoded.replace(Regex("[\\s_\\-\\u0640]"), "")
            val vendor = listOf("melodybox", "melodibox", "norton", "ملودیباکس", "ملودیبکس", "نورتون", "نورتن").any { compact.contains(it) }
            !vendor && !decoded.contains('\\') && !decoded.contains("تلگرام") &&
                listOf("tg:", "telegram:", "intent:", "javascript:", "data:", "file:").none { decoded.contains(it) } &&
                forbiddenHosts.none { host == it || host.endsWith(".$it") || decoded.contains("//$it/") || decoded.endsWith("//$it") } &&
                !forbiddenPath.containsMatchIn(normal(uri.rawPath.orEmpty() + "?" + uri.rawQuery.orEmpty())) &&
                !Regex("\\.(apk|apks|xapk|aab|exe|msi|dmg|ipa)([?#/]|$)").containsMatchIn(decoded)
        }
    } catch (_: Exception) { false }

    fun allowsSharedFilename(value: String): Boolean = try {
        !Regex("\\.(apk|apks|xapk|aab|exe|msi|dmg|ipa)$").containsMatchIn(normal(value).trim().trimEnd('.'))
    } catch (_: Exception) { false }

    fun safePackage(value: String): Boolean = Regex("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+").matches(value)
}
