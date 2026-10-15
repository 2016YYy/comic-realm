package com.comicrealm.comic_realm

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "comic_realm/cookies"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: ""
                    val raw = CookieManager.getInstance().getCookie(url) ?: ""
                    val cookies = raw.split(";").map { it.trim() }.filter { it.isNotEmpty() }
                    result.success(cookies)
                }
                else -> result.notImplemented()
            }
        }
    }
}
