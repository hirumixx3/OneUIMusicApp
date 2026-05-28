package com.hirumisu.musicapp

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import com.metrolist.innertube.YouTube
import com.metrolist.innertube.models.YouTubeClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlin.concurrent.thread

/**
 * Full-screen WebView used only to capture an authenticated YouTube Music cookie.
 * This deliberately extends android.app.Activity instead of AppCompatActivity so
 * the app module does not need the androidx.appcompat dependency.
 */
class GoogleLoginActivity : Activity() {

    companion object {
        const val RESULT_COOKIE = "google_cookie"
        const val RESULT_ACCOUNT_NAME = "account_name"
        const val RESULT_ACCOUNT_EMAIL = "account_email"
        const val RESULT_ACCOUNT_PHOTO = "account_photo"

        private val CAPTURE_HOSTS = setOf("music.youtube.com", "www.youtube.com", "youtube.com")
        private const val LOGIN_URL =
            "https://accounts.google.com/ServiceLogin?service=youtube" +
                "&continue=https://music.youtube.com/"
    }

    private lateinit var webView: WebView
    private val mainHandler = Handler(Looper.getMainLooper())
    private var cookieCaptured = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)

        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            userAgentString = YouTubeClient.USER_AGENT_WEB
            setSupportZoom(true)
            builtInZoomControls = false
            displayZoomControls = false
        }
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val host = request.url.host ?: return false
                if (!cookieCaptured && CAPTURE_HOSTS.any { allowed -> host.endsWith(allowed) }) {
                    view.loadUrl(request.url.toString())
                }
                return false
            }

            override fun onPageFinished(view: WebView, url: String) {
                if (cookieCaptured) return

                val host = runCatching { android.net.Uri.parse(url).host.orEmpty() }.getOrDefault("")
                if (CAPTURE_HOSTS.none { allowed -> host.endsWith(allowed) }) return

                CookieManager.getInstance().flush()
                val rawCookie = CookieManager.getInstance().getCookie(url) ?: return
                val hasGoogleAuthCookie = rawCookie.contains("SAPISID") ||
                    rawCookie.contains("SID") ||
                    rawCookie.contains("__Secure-3PSID")
                if (!hasGoogleAuthCookie) return

                cookieCaptured = true
                YouTube.cookie = rawCookie

                thread(start = true, isDaemon = true) {
                    var name = ""
                    var email = ""
                    var photo = ""

                    runCatching {
                        val info = runBlocking(Dispatchers.IO) {
                            YouTube.accountInfo().getOrNull()
                        }
                        name = info?.name.orEmpty()
                        email = info?.email.orEmpty()
                        photo = info?.thumbnailUrl.orEmpty()
                    }

                    MetrolistYouTubeSession.saveCookie(
                        applicationContext,
                        rawCookie,
                        name = name,
                        email = email,
                        photo = photo,
                    )

                    mainHandler.post {
                        val data = Intent()
                            .putExtra(RESULT_COOKIE, rawCookie)
                            .putExtra(RESULT_ACCOUNT_NAME, name)
                            .putExtra(RESULT_ACCOUNT_EMAIL, email)
                            .putExtra(RESULT_ACCOUNT_PHOTO, photo)
                        setResult(RESULT_OK, data)
                        finish()
                    }
                }
            }
        }

        setContentView(webView)
        webView.loadUrl(LOGIN_URL)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
        } else {
            setResult(RESULT_CANCELED)
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        if (::webView.isInitialized) webView.destroy()
        super.onDestroy()
    }
}
