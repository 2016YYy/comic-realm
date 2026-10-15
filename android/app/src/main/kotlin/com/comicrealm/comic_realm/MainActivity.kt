package com.comicrealm.comic_realm

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest

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
                "solveGatekeeper" -> {
                    val url = call.argument<String>("url") ?: ""
                    Thread {
                        try {
                            val cookies = solveGatekeeper(url)
                            runOnUiThread { result.success(cookies) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("GK_ERROR", e.message ?: "unknown", null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 原生解 Gatekeeper PoW 挑战。
     *
     * 关键点：使用 HttpURLConnection（底层 OkHttp 连接池），start 与 verify
     * 复用同一 TLS 会话，避免 dart:io HttpClient 不复用 HTTPS 连接导致的
     * `binding_mismatch`。
     */
    private fun solveGatekeeper(targetUrl: String): List<String> {
        val uri = URI(targetUrl)
        val base = "${uri.scheme}://${uri.host}"
        val startUrl = "$base/__gatekeeper_challenge/start?return=%2F"
        val ua = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                + "AppleWebKit/537.36 (KHTML, like Gecko) "
                + "Chrome/124.0.0.0 Safari/537.36")

        // 1. GET challenge start
        val conn1 = URL(startUrl).openConnection() as HttpURLConnection
        conn1.requestMethod = "GET"
        conn1.setRequestProperty("User-Agent", ua)
        conn1.setRequestProperty("Accept",
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        conn1.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")

        val browserCookies = mutableMapOf<String, String>()
        var i = 1
        while (true) {
            val name = conn1.getHeaderFieldKey(i) ?: break
            val value = conn1.getHeaderField(i)
            if ("set-cookie".equals(name, ignoreCase = true)) {
                val eq = value.indexOf('=')
                if (eq > 0) {
                    val cname = value.substring(0, eq)
                    val semi = value.indexOf(';', eq)
                    val cval = if (semi > 0) value.substring(eq + 1, semi)
                               else value.substring(eq + 1)
                    browserCookies[cname] = cval
                }
            }
            i++
        }

        // 收集 start 响应的 browser cookie（验证通过后仍需随请求发送）
        val allCookies = mutableListOf<String>()
        var k = 1
        while (true) {
            val name = conn1.getHeaderFieldKey(k) ?: break
            val value = conn1.getHeaderField(k)
            if ("set-cookie".equals(name, ignoreCase = true)) {
                allCookies.add(value)
            }
            k++
        }

        val html = conn1.inputStream.bufferedReader().use { it.readText() }
        // 不主动 disconnect，让连接池复用同一 TLS 会话

        // 2. 解析挑战参数
        val challengeId = regexGroup(html, """challengeId\s*:\s*"([^"]+)"""")
            ?: throw Exception("no challengeId")
        val ticket = regexGroup(html, """ticket\s*:\s*"([^"]+)"""")
            ?: throw Exception("no ticket")
        val diffStr = regexGroup(html, """difficultyBits\s*:\s*(\d+)""") ?: "16"
        val verifyPath = regexGroup(html, """verifyUrl\s*:\s*"([^"]+)"""")
            ?: "/__gatekeeper_challenge/verify"
        val difficulty = diffStr.toIntOrNull() ?: 16

        // 3. 解 PoW
        val nonce = solvePow(challengeId, difficulty)

        // 4. POST verify（同一连接池，复用 TLS 会话）
        val verifyUrl = URI(base).resolve(verifyPath).toString()
        val conn2 = URL(verifyUrl).openConnection() as HttpURLConnection
        conn2.requestMethod = "POST"
        conn2.doOutput = true
        conn2.setRequestProperty("User-Agent", ua)
        conn2.setRequestProperty("Content-Type", "application/json")
        conn2.setRequestProperty("Accept", "application/json")
        conn2.setRequestProperty("Origin", base)
        conn2.setRequestProperty("Referer", startUrl)
        val cookieHeader = browserCookies.entries
            .joinToString("; ") { "${it.key}=${it.value}" }
        if (cookieHeader.isNotEmpty()) {
            conn2.setRequestProperty("Cookie", cookieHeader)
        }

        val body = JSONObject()
            .put("challenge_id", challengeId)
            .put("ticket", ticket)
            .put("nonce", nonce.toString())
            .toString()
        conn2.outputStream.use { it.write(body.toByteArray()) }

        val status = conn2.responseCode
        // 读取响应体以释放连接
        if (status in 200..299) {
            conn2.inputStream.bufferedReader().use { it.readText() }
        } else {
            conn2.errorStream?.bufferedReader()?.use { it.readText() }
        }

        // 收集 clearance cookies（verify 响应）
        var j = 1
        while (true) {
            val name = conn2.getHeaderFieldKey(j) ?: break
            val value = conn2.getHeaderField(j)
            if ("set-cookie".equals(name, ignoreCase = true)) {
                allCookies.add(value)
            }
            j++
        }
        conn2.disconnect()
        return allCookies
    }

    private fun regexGroup(text: String, pattern: String): String? =
        Regex(pattern).find(text)?.groupValues?.getOrNull(1)

    private fun solvePow(challengeId: String, difficultyBits: Int): Long {
        val prefix = "gatekeeper-pow-v1:$challengeId:"
        val prefixBytes = prefix.toByteArray(Charsets.UTF_8)
        val md = MessageDigest.getInstance("SHA-256")
        val fullBytes = difficultyBits / 8
        val remBits = difficultyBits % 8
        var nonce = 0L
        while (true) {
            val msg = prefixBytes + nonce.toString().toByteArray(Charsets.UTF_8)
            val h = md.digest(msg)
            var ok = true
            for (k in 0 until fullBytes) {
                if (h[k].toInt() != 0) { ok = false; break }
            }
            if (ok && remBits > 0) {
                val mask = (0xFF shl (8 - remBits)) and 0xFF
                if ((h[fullBytes].toInt() and mask) != 0) ok = false
            }
            if (ok) return nonce
            nonce++
        }
    }
}
