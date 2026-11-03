package org.reelbox.reelbox.tests

import com.sun.net.httpserver.HttpServer
import org.reelbox.reelbox.RestrictedResourceFetcher
import java.net.InetSocketAddress
import java.net.HttpURLConnection
import java.net.URL
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import javax.net.ssl.SSLHandshakeException
import java.util.concurrent.CopyOnWriteArrayList

/** Deterministic connection seam: not a device TLS or WebView simulation. */
private class FixtureConnection(
    url: URL,
    private val code: Int = 200,
    private val fields: Map<String, List<String>> = emptyMap(),
    private val payload: InputStream = ByteArrayInputStream("public".toByteArray()),
    private val failure: IOException? = null,
    private val phrase: String = "",
) : HttpURLConnection(url) {
    var closed = false
    var statusReads = 0
    override fun connect() {}
    override fun disconnect() { closed = true }
    override fun usingProxy() = false
    override fun getResponseCode(): Int {
        check(!instanceFollowRedirects) { "Automatic redirects enabled" }
        check(connectTimeout in 1..30_000 && readTimeout in 1..30_000) { "Unbounded network wait" }
        statusReads++
        failure?.let { throw it }
        return code
    }
    override fun getResponseMessage(): String = phrase
    override fun getHeaderFields(): Map<String, List<String>> = fields
    override fun getHeaderField(name: String): String? = fields.entries.firstOrNull { it.key.equals(name, true) }?.value?.firstOrNull()
    override fun getInputStream(): InputStream = payload
    override fun getErrorStream(): InputStream = payload
}

/** Real loopback HTTP; no remote hosts, accounts, Android runtime or Gradle. */
fun main(args: Array<String>) {
    val selected = args.firstOrNull() ?: "all"
    var passed = 0
    fun test(name: String, body: () -> Unit) {
        if (selected != "all" && selected != name) return
        body()
        passed++
        println("PASS $name")
    }
    test("blocked_redirect") {
        val hits = CopyOnWriteArrayList<String>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            hits.add(exchange.requestURI.path)
            if (exchange.requestURI.path == "/redirect.js") {
                exchange.responseHeaders.add("Location", "/news/script.js")
                exchange.sendResponseHeaders(302, -1)
            } else {
                val bytes = "forbidden-marker".toByteArray()
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
            exchange.close()
        }
        server.start()
        try {
            val url = "http://127.0.0.1:${server.address.port}/redirect.js"
            val response = RestrictedResourceFetcher().fetch(url)
            response.body.close()
            check(response.statusCode == 403) { "Forbidden redirect must fail closed" }
            check(hits == listOf("/redirect.js")) { "Forbidden target requested: $hits" }
        } finally { server.stop(0) }
    }
    test("allowed_redirect_metadata") {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            if (exchange.requestURI.path == "/entry.js") {
                exchange.responseHeaders.add("Location", "./assets/player.js")
                exchange.sendResponseHeaders(307, -1)
            } else {
                val bytes = "public-player".toByteArray()
                exchange.responseHeaders.add("Content-Type", "application/javascript; charset=\"UTF-8\"")
                exchange.responseHeaders.add("Access-Control-Allow-Origin", "https://embed.example.org")
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
            exchange.close()
        }
        server.start()
        try {
            val base = "http://127.0.0.1:${server.address.port}"
            val response = RestrictedResourceFetcher().fetch("$base/entry.js")
            check(response.statusCode == 200 && response.reasonPhrase.isNotBlank())
            check(response.mimeType == "application/javascript" && response.encoding == "UTF-8")
            check(response.effectiveUrl == "$base/assets/player.js")
            check(response.headers.entries.any { it.key.equals("Access-Control-Allow-Origin", true) && it.value == "https://embed.example.org" })
            check(response.body.use { String(it.readBytes()) } == "public-player")
            for (path in listOf("/collections/private.m3u8", "/episodes/playlist.m3u8")) {
                val playlist = RestrictedResourceFetcher().fetch("$base$path")
                check(playlist.statusCode == 200 && playlist.body.use { String(it.readBytes()) } == "public-player")
            }
        } finally { server.stop(0) }
    }
    test("redirect_boundaries") {
        val hits = CopyOnWriteArrayList<String>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val path = exchange.requestURI.path
            hits.add(path)
            val target = when (path) {
                "/loop.js" -> "/loop.js"
                "/malformed.js" -> "http://[invalid"
                "/empty.js" -> null
                "/chain.js" -> "/second.js"
                "/second.js" -> "/%256eews/script.js"
                else -> "/news/script.js"
            }
            if (target != null) exchange.responseHeaders.add("Location", target)
            exchange.sendResponseHeaders(path.removePrefix("/code-").toIntOrNull() ?: 302, -1)
            exchange.close()
        }
        server.start()
        try {
            val fetcher = RestrictedResourceFetcher()
            val base = "http://127.0.0.1:${server.address.port}"
            val loop = fetcher.fetch("$base/loop.js")
            loop.body.close()
            check(loop.statusCode == 508 && hits.size == 6) { "Redirect budget must be five: ${loop.statusCode}, ${hits.size}" }
            for (path in listOf("malformed.js", "empty.js")) {
                val response = fetcher.fetch("$base/$path")
                response.body.close()
                check(response.statusCode == 502)
            }
            hits.clear()
            val chain = fetcher.fetch("$base/chain.js")
            chain.body.close()
            check(chain.statusCode == 403 && hits == listOf("/chain.js", "/second.js"))
            for (code in listOf(301, 302, 303, 307, 308)) {
                hits.clear()
                val response = fetcher.fetch("$base/code-$code")
                response.body.close()
                check(response.statusCode == 403 && hits == listOf("/code-$code"))
            }
            hits.clear()
            for (url in listOf("not a URI", "$base/news/script.js", "file:///unreadable", "content://unreadable", "data:text/plain,test")) {
                val response = fetcher.fetch(url)
                response.body.close()
                check(response.statusCode == 403)
            }
            check(hits.isEmpty())
        } finally { server.stop(0) }
    }
    test("range_head_and_headers") {
        val seen = CopyOnWriteArrayList<Pair<String, Map<String, List<String>>>>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            seen.add(exchange.requestMethod to exchange.requestHeaders.toMap())
            if (exchange.requestURI.path == "/entry.mp4") {
                exchange.responseHeaders.add("Location", "/video.mp4")
                exchange.sendResponseHeaders(307, -1)
                exchange.close()
                return@createContext
            }
            exchange.responseHeaders.add("Content-Type", "video/mp4")
            exchange.responseHeaders.add("Accept-Ranges", "bytes")
            exchange.responseHeaders.add("Content-Range", "bytes 2-5/10")
            exchange.responseHeaders.add("Set-Cookie", "fixture=public; Path=/")
            exchange.responseHeaders.add("Connection", "keep-alive, X-Hop-Only")
            exchange.responseHeaders.add("X-Hop-Only", "must-not-forward")
            exchange.responseHeaders.add("ETag", "\"fixture-range\"")
            if (exchange.requestMethod == "HEAD") {
                exchange.responseHeaders.add("Content-Length", "4")
                exchange.sendResponseHeaders(206, -1)
            } else {
                exchange.sendResponseHeaders(206, 4)
                exchange.responseBody.use { it.write("2345".toByteArray()) }
            }
            exchange.close()
        }
        server.start()
        try {
            val fetcher = RestrictedResourceFetcher()
            val url = "http://127.0.0.1:${server.address.port}/entry.mp4"
            val requestHeaders = mapOf("Range" to "bytes=2-5", "If-Range" to "\"fixture-range\"",
                "User-Agent" to "PublicEmbedFixture", "Authorization" to "fixture-only",
                "Cookie" to "fixture=not-a-real-session", "Proxy-Authorization" to "fixture-only",
                "X-Api-Key" to "fixture-only", "Accept-Encoding" to "gzip", "Host" to "wrong.invalid",
                "If-None-Match" to "\"fixture\"")
            for (method in listOf("GET", "HEAD")) {
                val response = fetcher.fetch(url, method, requestHeaders)
                check(response.statusCode == 206 && response.mimeType == "video/mp4" && response.encoding == null)
                check(response.headers.entries.any { it.key.equals("Content-Range", true) && it.value == "bytes 2-5/10" })
                check(response.headers.entries.any { it.key.equals("Content-Length", true) && it.value == "4" })
                check(response.headers.keys.none { it.lowercase() in listOf("set-cookie", "connection", "x-hop-only", "transfer-encoding") })
                check(response.body.use { String(it.readBytes()) } == if (method == "HEAD") "" else "2345")
            }
            check(seen.map { it.first } == listOf("GET", "GET", "HEAD", "HEAD"))
            for ((_, headers) in seen) {
                fun header(name: String) = headers.entries.firstOrNull { it.key.equals(name, true) }?.value?.singleOrNull()
                check(header("Range") == "bytes=2-5" && header("If-Range") == "\"fixture-range\"")
                check(header("User-Agent") == "PublicEmbedFixture" && header("Accept-Encoding") == "identity")
                check(listOf("Authorization", "Cookie", "Proxy-Authorization", "X-Api-Key", "If-None-Match").all { header(it) == null })
                check(header("Host") != "wrong.invalid")
            }
            for (method in listOf("POST", "PUT", "DELETE", "OPTIONS")) {
                val response = fetcher.fetch(url, method, requestHeaders)
                response.body.close()
                check(response.statusCode == 405)
            }
            check(seen.size == 4) { "Unsupported methods must not be sent" }
        } finally { server.stop(0) }
    }
    test("cross_origin_headers") {
        val seen = CopyOnWriteArrayList<Map<String, List<String>>>()
        val first = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val second = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val origin = "http://127.0.0.1:${first.address.port}"
        first.createContext("/") { exchange ->
            seen.add(exchange.requestHeaders.toMap())
            if (exchange.requestURI.path == "/entry.js") {
                exchange.responseHeaders.add("Location", "http://localhost:${second.address.port}/middle.js")
                exchange.sendResponseHeaders(302, -1)
            } else {
                exchange.sendResponseHeaders(200, 2)
                exchange.responseBody.use { it.write("ok".toByteArray()) }
            }
            exchange.close()
        }
        second.createContext("/") { exchange ->
            seen.add(exchange.requestHeaders.toMap())
            exchange.responseHeaders.add("Location", "$origin/final.js")
            exchange.sendResponseHeaders(308, -1)
            exchange.close()
        }
        first.start(); second.start()
        try {
            val response = RestrictedResourceFetcher().fetch("$origin/entry.js", "GET", mapOf(
                "Origin" to origin, "Referer" to "$origin/embed?fixture=public", "Range" to "bytes=0-1",
                "Cookie" to "fixture-only", "Authorization" to "fixture-only", "X-Private" to "fixture-only"))
            check(response.body.use { String(it.readBytes()) } == "ok")
            check(seen.size == 3)
            fun header(index: Int, name: String) = seen[index].entries.firstOrNull { it.key.equals(name, true) }?.value?.singleOrNull()
            // The JDK suppresses Origin as a restricted header; Android may send it.
            check(header(0, "Referer") == "$origin/embed?fixture=public") { "Initial public Referer missing: ${header(0, "Referer")}" }
            for (index in 1..2) check(header(index, "Origin") == null && header(index, "Referer") == null)
            for (index in 0..2) {
                check(header(index, "Range") == "bytes=0-1")
                check(listOf("Cookie", "Authorization", "X-Private").all { header(index, it) == null })
            }
        } finally { first.stop(0); second.stop(0) }
    }
    test("tls_downgrade_and_stream_ownership") {
        val opened = mutableListOf<FixtureConnection>()
        val fetcher = RestrictedResourceFetcher(openConnection = { url ->
            FixtureConnection(url, 302, mapOf("Location" to listOf("http://media.example.org/video.mp4"))).also { opened.add(it) }
        })
        val downgrade = fetcher.fetch("https://media.example.org/entry")
        downgrade.body.close()
        check(downgrade.statusCode == 403 && opened.size == 1 && opened.single().closed)
        val mixed = fetcher.fetch("http://media.example.org/video.mp4", secureContext = true)
        mixed.body.close()
        check(mixed.statusCode == 403 && opened.size == 1)
        val tlsConnection = FixtureConnection(URL("https://media.example.org/video.mp4"), failure = SSLHandshakeException("fixture untrusted peer"))
        val tls = RestrictedResourceFetcher(openConnection = { tlsConnection }).fetch(tlsConnection.url.toString())
        tls.body.close()
        check(tls.statusCode == 502 && tlsConnection.closed && tlsConnection.statusReads == 1)
        var reads = 0
        var closes = 0
        val payload = object : InputStream() {
            override fun read(): Int { reads++; return if (reads == 1) 65 else -1 }
            override fun close() { closes++ }
        }
        val connection = FixtureConnection(URL("https://media.example.org/video.mp4"), payload = payload)
        val response = RestrictedResourceFetcher(openConnection = { connection }).fetch(connection.url.toString())
        check(response.statusCode == 200 && reads == 0 && !connection.closed) { "Body was buffered or closed before streaming" }
        check(response.reasonPhrase.isNotBlank())
        check(response.body.read() == 65)
        response.body.close()
        check(connection.closed && closes == 1)
    }
    test("android_status_and_transport_failures") {
        val invalidPhrase = FixtureConnection(URL("https://media.example.org/player.js"), phrase = "OK\r\nfixture\u00e9")
        val safePhrase = RestrictedResourceFetcher(openConnection = { invalidPhrase }).fetch(invalidPhrase.url.toString())
        safePhrase.body.close()
        check(safePhrase.reasonPhrase.isNotBlank() && safePhrase.reasonPhrase.all { it.code in 32..126 })
        // WebResourceResponse accepts 100..299/400..599, never 3xx or invalid codes.
        for (code in listOf(-1, 99, 300, 304, 305, 306, 399, 600)) {
            val connection = FixtureConnection(URL("https://media.example.org/player.js"), code)
            val response = RestrictedResourceFetcher(openConnection = { connection }).fetch(connection.url.toString())
            response.body.close()
            check(response.statusCode == 502 && connection.closed) { "Invalid WebView status escaped: $code -> ${response.statusCode}" }
        }
        for (failure in listOf(IOException("fixture connection failure"), java.net.SocketTimeoutException("fixture timeout"))) {
            val connection = FixtureConnection(URL("https://media.example.org/player.js"), failure = failure)
            val response = RestrictedResourceFetcher(openConnection = { connection }).fetch(connection.url.toString())
            check(response.statusCode == 502 && response.body.use { it.read() } == -1 && connection.closed)
        }
    }
    test("access_denial_passthrough") {
        val hits = CopyOnWriteArrayList<String>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            hits.add(exchange.requestURI.path)
            val code = exchange.requestURI.path.drop(1).toInt()
            val bytes = "fixture-denied-$code".toByteArray()
            exchange.responseHeaders.add("Content-Type", "text/plain; charset=UTF-8")
            exchange.responseHeaders.add("WWW-Authenticate", "Basic realm=fixture")
            exchange.sendResponseHeaders(code, bytes.size.toLong())
            exchange.responseBody.use { it.write(bytes) }
            exchange.close()
        }
        server.start()
        try {
            for (code in listOf(401, 403, 451, 404, 416)) {
                val response = RestrictedResourceFetcher().fetch("http://127.0.0.1:${server.address.port}/$code")
                check(response.statusCode == code && response.mimeType == "text/plain" && response.encoding == "UTF-8")
                check(response.body.use { String(it.readBytes()) } == "fixture-denied-$code")
            }
            check(hits == listOf("/401", "/403", "/451", "/404", "/416")) { "Access denials must not cause retries: $hits" }
        } finally { server.stop(0) }
    }
    test("excluded_redirect_destinations") {
        val hits = CopyOnWriteArrayList<String>()
        var destination = ""
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            hits.add(exchange.requestURI.path)
            exchange.responseHeaders.add("Location", destination)
            exchange.sendResponseHeaders(302, -1)
            exchange.close()
        }
        server.start()
        try {
            val base = "http://127.0.0.1:${server.address.port}"
            for (target in listOf("/news/script.js", "/support/help", "/updates/latest", "/setup.apk",
                "/melodybox/embed", "/%2575pdater/latest", "https://t.me/fixture", "/live/channel.m3u8",
                "/channels/example", "/public-playlists/items", "/public_playlists/items", "/?action=showlist")) {
                hits.clear()
                destination = if (target.startsWith("/")) "$base$target" else target
                for (method in listOf("GET", "HEAD")) {
                    val response = RestrictedResourceFetcher().fetch("$base/entry.js", method)
                    response.body.close()
                    check(response.statusCode == 403) { "Excluded redirect permitted: $target ($method)" }
                }
                check(hits == listOf("/entry.js", "/entry.js")) { "Excluded target contacted: $target -> $hits" }
            }
        } finally { server.stop(0) }
    }
    check(passed > 0) { "Unknown case: $selected" }
    println("Restricted resource fetch: $passed cases passed")
}
