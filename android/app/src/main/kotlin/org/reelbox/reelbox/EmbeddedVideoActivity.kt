package org.reelbox.reelbox

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.PermissionRequest
import android.webkit.SslErrorHandler
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.io.ByteArrayInputStream

/** Restricted video embed host, not a vendor storefront or general external browser. */
class EmbeddedVideoActivity : Activity() {
    companion object { private const val FILE_REQUEST = 6104 }
    private lateinit var web: WebView
    private lateinit var root: LinearLayout
    private lateinit var screen: FrameLayout
    private lateinit var status: TextView
    private lateinit var home: String
    private val resourceFetcher = RestrictedResourceFetcher()
    @Volatile private var securePage = false
    private var customView: View? = null
    private var customCallback: WebChromeClient.CustomViewCallback? = null
    private var oldOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private var oldUi = 0
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var networkRegistered = false
    private lateinit var connectivity: ConnectivityManager
    private val network = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = updateConnectivity()
        override fun onLost(network: Network) = updateConnectivity()
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = updateConnectivity()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        home = intent.getStringExtra("url").orEmpty()
        if (!NativeUrlPolicy.allowsRemote(home)) { finish(); return }
        securePage = home.startsWith("https:", true)
        title = intent.getStringExtra("title")?.take(512) ?: "Embedded video"
        screen = FrameLayout(this)
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.BLACK) }
        val tools = LinearLayout(this)
        fun control(label: String, action: () -> Unit) {
            tools.addView(Button(this).apply { text = label; setOnClickListener { action() } }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
        control("Back") { back() }
        control("Home") { load(home) }
        control("Refresh") { web.reload() }
        control("Close") { finish() }
        root.addView(tools)
        status = TextView(this).apply { setTextColor(Color.WHITE); setPadding(12, 4, 12, 4) }
        root.addView(status)
        web = WebView(this)
        root.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        screen.addView(root)
        setContentView(screen)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            if (Build.VERSION.SDK_INT >= 26) safeBrowsingEnabled = true
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val allowed = NativeUrlPolicy.allowsRemote(request.url.toString())
                if (!allowed && request.isForMainFrame) message("This destination is not permitted.")
                return !allowed
            }
            @Suppress("DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = !NativeUrlPolicy.allowsRemote(url)
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                val response = resourceFetcher.fetch(request.url.toString(), request.method, request.requestHeaders,
                    secureContext = !request.isForMainFrame && securePage)
                if (request.isForMainFrame) {
                    if (response.effectiveUrl.isNotEmpty()) securePage = response.effectiveUrl.startsWith("https:", true)
                    if (response.statusCode in listOf(401, 403, 451)) {
                        message("This source or destination denied access. Authorization cannot be bypassed.")
                    } else if (response.statusCode >= 500) message("Video page unavailable. Check connectivity and use Refresh.")
                }
                return resourceResponse(response)
            }
            @Suppress("DEPRECATION")
            override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse {
                return resourceResponse(resourceFetcher.fetch(url, secureContext = securePage))
            }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                handler.cancel()
                message("Secure connection failed. Playback was not authorized.")
            }
            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame && response.statusCode in listOf(401, 403, 451)) {
                    view.stopLoading()
                    message("This source denied access. Reelbox cannot bypass authorization or DRM.")
                }
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) message("Video page unavailable. Check connectivity and use Refresh.")
            }
            override fun onPageFinished(view: WebView, url: String) { updateConnectivity() }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (customView != null) { callback.onCustomViewHidden(); return }
                customView = view
                customCallback = callback
                oldOrientation = requestedOrientation
                @Suppress("DEPRECATION")
                oldUi = window.decorView.systemUiVisibility
                root.visibility = View.GONE
                screen.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            }
            override fun onHideCustomView() = hideFullscreen()
            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                fileCallback?.onReceiveValue(null)
                fileCallback = callback
                val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                    .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("video/*", "audio/*", "text/vtt", "application/x-subrip"))
                    .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.mode == FileChooserParams.MODE_OPEN_MULTIPLE)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                return try { @Suppress("DEPRECATION") startActivityForResult(picker, FILE_REQUEST); true }
                catch (_: Exception) { fileCallback?.onReceiveValue(null); fileCallback = null; false }
            }
        }
        web.setDownloadListener(DownloadListener { url, _, contentDisposition, mime, _ ->
            val name = URLUtil.guessFileName(url, contentDisposition, mime)
            if (!NativeUrlPolicy.allowsRemote(url) || mime.orEmpty().contains("android.package", true) ||
                Regex("\\.(apk|apks|xapk|aab)$", RegexOption.IGNORE_CASE).containsMatchIn(name)) {
                message("This download is not permitted.")
            } else AlertDialog.Builder(this).setTitle("Download media?")
                .setMessage("Send $name to an installed download manager? Web credentials are not forwarded.")
                .setNegativeButton("Cancel", null).setPositiveButton("Choose downloader") { _, _ ->
                    AlertDialog.Builder(this).setTitle("Download with")
                        .setItems(arrayOf("ADM", "1DM / IDM", "Other app")) { _, index ->
                            try {
                                val ok = NativeFileIntents(this).openDownloader(mapOf("url" to url, "filename" to name,
                                    "packageName" to listOf("ADM", "IDM", "ask")[index]))
                                if (!ok) message("No compatible download manager is installed.")
                            } catch (_: Exception) { message("Unable to hand off this download.") }
                        }.show()
                }.show()
        })
        connectivity = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        try { connectivity.registerDefaultNetworkCallback(network); networkRegistered = true } catch (_: Exception) { }
        if (Build.VERSION.SDK_INT >= 33) onBackInvokedDispatcher.registerOnBackInvokedCallback(
            android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT) { back() }
        if (savedInstanceState != null) web.restoreState(savedInstanceState) else load(home)
        updateConnectivity()
    }

    private fun load(url: String) {
        if (NativeUrlPolicy.allowsRemote(url)) { hideFullscreen(); web.loadUrl(url) }
        else message("This destination is not permitted.")
    }
    private fun resourceResponse(response: RestrictedResourceFetcher.Response): WebResourceResponse = try {
        WebResourceResponse(response.mimeType, response.encoding, response.statusCode,
            response.reasonPhrase, response.headers, response.body)
    } catch (_: IllegalArgumentException) {
        // Never fall back to WebView networking if Android rejects response metadata.
        try { response.body.close() } catch (_: Exception) { }
        WebResourceResponse("text/plain", "UTF-8", 502, "Unavailable", emptyMap(), ByteArrayInputStream(ByteArray(0)))
    }
    private fun message(text: String) { runOnUiThread { if (::status.isInitialized) status.text = text } }
    private fun updateConnectivity() {
        if (!::connectivity.isInitialized) return
        val caps = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        message(if (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true) "Embedded video · network connected" else "Offline · reconnect and tap Refresh")
    }
    private fun hideFullscreen() {
        val view = customView ?: return
        screen.removeView(view)
        customView = null
        root.visibility = View.VISIBLE
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = oldUi
        requestedOrientation = oldOrientation
        customCallback?.onCustomViewHidden()
        customCallback = null
    }
    private fun back() { if (customView != null) hideFullscreen() else if (web.canGoBack()) web.goBack() else finish() }
    @Deprecated("System back uses OnBackInvokedDispatcher on Android 13+")
    override fun onBackPressed() = back()
    override fun onSaveInstanceState(outState: Bundle) { if (::web.isInitialized) web.saveState(outState); super.onSaveInstanceState(outState) }
    @Deprecated("Activity result contract retained for the platform WebView file chooser")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FILE_REQUEST) return
        val uris = if (resultCode == RESULT_OK) {
            val clips = data?.clipData
            if (clips != null) (0 until clips.itemCount.coerceAtMost(10)).map { clips.getItemAt(it).uri }
            else listOfNotNull(data?.data)
        } else emptyList()
        fileCallback?.onReceiveValue(uris.filter { it.scheme == "content" }.takeIf { it.isNotEmpty() }?.toTypedArray())
        fileCallback = null
    }
    override fun onPause() { if (::web.isInitialized) web.onPause(); super.onPause() }
    override fun onResume() { super.onResume(); if (::web.isInitialized) web.onResume() }
    override fun onDestroy() {
        if (networkRegistered) connectivity.unregisterNetworkCallback(network)
        fileCallback?.onReceiveValue(null)
        fileCallback = null
        hideFullscreen()
        if (::web.isInitialized) {
            web.stopLoading()
            (web.parent as? ViewGroup)?.removeView(web)
            web.destroy()
        }
        super.onDestroy()
    }
}
