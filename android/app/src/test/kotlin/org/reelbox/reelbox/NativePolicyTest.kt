package org.reelbox.reelbox.tests

import org.reelbox.reelbox.NativeUrlPolicy

/** JVM executable: no Android runtime, credentials, network, or Gradle. */
fun main() {
    var assertions = 0
    fun expect(condition: Boolean, message: () -> Any = { "Assertion failed" }) {
        assertions++
        check(condition, message)
    }
    expect(NativeUrlPolicy.allowsRemote("https://media.example.org/movie.m3u8?token=opaque"))
    expect(NativeUrlPolicy.allowsRemote("http://192.168.1.4/video.mp4"))
    for (url in listOf(
        "javascript:alert(1)", "intent://play", "file:///sdcard/video.mp4", "https://t.me/channel",
        "https://example.org/app.APK?download=1", "https://example.org/%75pdate/latest",
        "https://example.org/support/contact", "https://example.org/telegram", "https://melodybox.example/store",
        "https://norton.com/promo", "https://example.org/news", "https://example.org/shop",
        "https://user:pass@example.org/video.mp4", "https://example.org/app%252eapk",
        "https://example.org/مَلُودِي%20باكس", "https://example.org/نُورْتُون",
        "https://example.org/setup.exe", "https://example.org/app.dmg", "https://example.org/install.ipa",
        "https://example.org/video%5cplayer.mp4", "https://example.org/%2575pdate/latest",
        "https://example.org/%D8%AA%D9%84%DA%AF%D8%B1%D8%A7%D9%85",
        "https://example.org/?next=https%3A%2F%2Ft.me%2Fchannel", "https://example.org/?next=melody&#98;ox"
    )) expect(!NativeUrlPolicy.allowsRemote(url)) { "Unsafe URL accepted: $url" }
    expect(NativeUrlPolicy.safePackage("org.videolan.vlc"))
    expect(!NativeUrlPolicy.safePackage("bad;package"))
    expect(!NativeUrlPolicy.allowsSharedFilename("update.APK"))
    expect(!NativeUrlPolicy.allowsSharedFilename("installer.msi"))
    expect(NativeUrlPolicy.allowsSharedFilename("episode.mkv"))
    expect(NativeUrlPolicy.allowsSharedFilename("subtitle.vtt"))
    val first = org.reelbox.reelbox.PlaybackSnapshot.from(mapOf("title" to "Film", "playing" to true, "positionMs" to -20, "durationMs" to 100))
    expect(first.positionMs == 0L && first.playing && first.title == "Film")
    val next = org.reelbox.reelbox.PlaybackSnapshot.from(mapOf("positionMs" to 999), first)
    expect(next.positionMs == 100L && next.durationMs == 100L && next.title == "Film")
    expect(org.reelbox.reelbox.PlaybackSnapshot.from(mapOf("durationMs" to -9)).durationMs == 0L)
    println("Native URL policy and playback snapshots: $assertions assertions passed")
}
