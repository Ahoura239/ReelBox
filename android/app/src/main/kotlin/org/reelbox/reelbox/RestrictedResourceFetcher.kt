package org.reelbox.reelbox

import java.io.ByteArrayInputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI

/** Credential-free HTTP transport: the WebView must never own HTTP redirects. */
internal class RestrictedResourceFetcher(
    private val openConnection: (java.net.URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) {
    data class Response(
        val statusCode: Int,
        val body: InputStream,
        val mimeType: String = "text/plain",
        val encoding: String? = "UTF-8",
        val reasonPhrase: String = "Blocked",
        val headers: Map<String, String> = emptyMap(),
        val effectiveUrl: String = "",
    )

    fun fetch(
        url: String,
        method: String = "GET",
        requestHeaders: Map<String, String> = emptyMap(),
        secureContext: Boolean = false,
    ): Response {
        if (method != "GET" && method != "HEAD") return empty(405)
        if (!allowsResource(url)) return empty(403)
        var target = URI(url).normalize()
        var requireTls = secureContext || target.scheme.equals("https", true)
        var forwardContext = true
        var active: HttpURLConnection? = null
        try {
            repeat(6) { hop ->
                if (!allowsResource(target.toString()) ||
                    (requireTls && !target.scheme.equals("https", true))) return empty(403)
                requireTls = requireTls || target.scheme.equals("https", true)
                val connection = openConnection(target.toURL())
                active = connection
                connection.connectTimeout = 10_000
                connection.readTimeout = 15_000
                connection.allowUserInteraction = false
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.useCaches = false
                // A small public-resource allowlist, not arbitrary headers or a cookie jar.
                for ((name, value) in requestHeaders) {
                    val lower = name.lowercase(java.util.Locale.ROOT)
                    val allowedHeader = lower in setOf("accept", "accept-language", "user-agent", "range", "if-range") ||
                        (forwardContext && lower in setOf("origin", "referer"))
                    if (allowedHeader && value.none { it == '\r' || it == '\n' || it == '\u0000' }) {
                        connection.setRequestProperty(name, value)
                    }
                }
                // Keep payload bytes and Content-Length/Range/Encoding consistent; no transparent gzip.
                connection.setRequestProperty("Accept-Encoding", "identity")
                val status = connection.responseCode
                if (status in listOf(301, 302, 303, 307, 308)) {
                    val location = connection.getHeaderField("Location")
                    connection.disconnect()
                    active = null
                    if (location.isNullOrBlank()) return empty(502)
                    if (hop == 5) return empty(508)
                    val next = target.resolve(location).normalize()
                    fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme.equals("https", true)) 443 else 80
                    if (!target.scheme.equals(next.scheme, true) || !target.host.equals(next.host, true) || port(target) != port(next)) {
                        forwardContext = false // Never restore a stripped context on a later hop back.
                    }
                    target = next
                } else {
                    // Android rejects all 3xx WebResourceResponse statuses, including 304.
                    if (status !in 100..299 && status !in 400..599) return empty(502)
                    val stream = if (method == "HEAD") null else if (status >= 400) connection.errorStream else connection.inputStream
                    val contentType = connection.contentType.orEmpty().split(';')
                    val mime = contentType.first().trim().ifEmpty { "application/octet-stream" }
                    val charset = contentType.drop(1).firstOrNull { it.trim().startsWith("charset=", true) }
                        ?.substringAfter('=')?.trim()?.trim('"', '\'')
                    val hopHeaders = connection.getHeaderField("Connection").orEmpty().split(',')
                        .map { it.trim().lowercase(java.util.Locale.ROOT) }.toSet()
                    val excluded = hopHeaders + setOf("connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
                        "te", "trailer", "transfer-encoding", "upgrade", "set-cookie", "set-cookie2")
                    val headers = connection.headerFields.filterKeys { it != null && it.lowercase(java.util.Locale.ROOT) !in excluded }
                        .mapValues { (_, values) -> values.joinToString(", ") }
                    val body = object : FilterInputStream(stream ?: ByteArrayInputStream(ByteArray(0))) {
                        override fun close() { try { super.close() } finally { connection.disconnect() } }
                    }
                    val reason = connection.responseMessage.orEmpty()
                        .takeIf { it.isNotBlank() && it.all { char -> char.code in 32..126 } } ?: "HTTP response"
                    active = null // Body owns the connection until WebView closes it.
                    return Response(status, body, mime, charset, reason, headers, target.toString())
                }
            }
        } catch (_: Exception) {
            return empty(502)
        } finally { active?.disconnect() }
        return empty(508)
    }

    private fun allowsResource(url: String): Boolean = try {
        if (!NativeUrlPolicy.allowsRemote(url)) false else {
            val uri = URI(url)
            var route = uri.rawPath.orEmpty() + "?" + uri.rawQuery.orEmpty()
            repeat(3) { route = java.net.URLDecoder.decode(route, "UTF-8") }
            route = java.text.Normalizer.normalize(route, java.text.Normalizer.Form.NFKC)
                .lowercase(java.util.Locale.ROOT).replace(Regex("[\\p{Cf}]"), "")
            // Removed catalog families are not embed resources. Keep private/episode playlists.
            !Regex("(^|[/_.?&=\\-])(live|channels?|live[-_]?channels?|public[-_]?(play)?lists?)([/_.?&=\\-]|$)")
                .containsMatchIn(route) &&
                !Regex("[?&]action=(showlist|show-list_fav|playlist-items)([&#]|$)").containsMatchIn(route)
        }
    } catch (_: Exception) { false }

    private fun empty(status: Int) = Response(status, ByteArrayInputStream(ByteArray(0)))
}
