import Flutter
import UIKit
import WebKit
import CommonCrypto

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "comic_realm/cookies", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getCookies":
          guard let args = call.arguments as? [String: Any],
                let urlString = args["url"] as? String,
                let nsUrl = URL(string: urlString) else {
            result(FlutterMethodNotImplemented)
            return
          }
          WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let filtered = cookies.filter { cookie in
              nsUrl.host?.hasSuffix(cookie.domain) == true
                || cookie.domain.hasSuffix(nsUrl.host ?? "")
            }
            let resultArray = filtered.map { "\($0.name)=\($0.value)" }
            result(resultArray)
          }
        case "solveGatekeeper":
          guard let args = call.arguments as? [String: Any],
                let urlString = args["url"] as? String,
                let targetUrl = URL(string: urlString) else {
            result(FlutterMethodNotImplemented)
            return
          }
          self.solveGatekeeper(targetUrl: targetUrl, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 原生解 Gatekeeper PoW 挑战：使用 URLSession（复用 TLS 会话）。
  private func solveGatekeeper(targetUrl: URL, result: @escaping FlutterResult) {
    let host = targetUrl.host ?? ""
    let scheme = targetUrl.scheme ?? "https"
    let base = "\(scheme)://\(host)"
    guard let startUrl = URL(string: "\(base)/__gatekeeper_challenge/start?return=%2F") else {
      result(FlutterError(code: "GK_ERROR", message: "bad url", details: nil))
      return
    }
    let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    // 使用独立的 URLSession，其内部连接池会复用同一 TLS 会话。
    let config = URLSessionConfiguration.default
    config.httpAdditionalHeaders = ["User-Agent": ua]
    let session = URLSession(configuration: config)

    var request1 = URLRequest(url: startUrl)
    request1.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                      forHTTPHeaderField: "Accept")
    request1.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

    let task1 = session.dataTask(with: request1) { data, response, error in
      guard let data = data,
            let httpResp = response as? HTTPURLResponse, error == nil else {
        result(FlutterError(code: "GK_ERROR",
                            message: error?.localizedDescription ?? "start failed",
                            details: nil))
        return
      }

      // URLSession 自动把 __Host-gk_browser_* cookie 存入 HTTPCookieStorage，
      // 后续 verify 请求会自动携带，无需手动处理。
      let html = String(data: data, encoding: .utf8) ?? ""
      guard let challengeId = self.extract(html, pattern: "challengeId\\s*:\\s*\"([^\"]+)\""),
            let ticket = self.extract(html, pattern: "ticket\\s*:\\s*\"([^\"]+)\"") else {
        result(FlutterError(code: "GK_ERROR", message: "parse params failed", details: nil))
        return
      }
      let diffStr = self.extract(html, pattern: "difficultyBits\\s*:\\s*(\\d+)") ?? "16"
      let difficulty = Int(diffStr) ?? 16
      let verifyPath = self.extract(html, pattern: "verifyUrl\\s*:\\s*\"([^\"]+)\"")
        ?? "/__gatekeeper_challenge/verify"

      let nonce = self.solvePow(challengeId: challengeId, difficultyBits: difficulty)

      guard let baseUrl = URL(string: base),
            let verifyUrl = URL(string: verifyPath, relativeTo: baseUrl) else {
        result(FlutterError(code: "GK_ERROR", message: "bad verify url", details: nil))
        return
      }
      var request2 = URLRequest(url: verifyUrl.absoluteURL)
      request2.httpMethod = "POST"
      request2.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request2.setValue("application/json", forHTTPHeaderField: "Accept")
      request2.setValue(base, forHTTPHeaderField: "Origin")
      request2.setValue(startUrl.absoluteString, forHTTPHeaderField: "Referer")
      let body: [String: Any] = [
        "challenge_id": challengeId,
        "ticket": ticket,
        "nonce": nonce
      ]
      request2.httpBody = try? JSONSerialization.data(withJSONObject: body)

      let task2 = session.dataTask(with: request2) { _, resp2, error2 in
        if let error2 = error2 {
          result(FlutterError(code: "GK_ERROR",
                              message: error2.localizedDescription, details: nil))
          return
        }
        // 从 cookie store 读取全部 cookies（含 start 的 browser cookie 与
        // verify 的 clearance cookie），以 Set-Cookie 格式返回给 Dart。
        let cookies = HTTPCookieStorage.shared.cookies(for: verifyUrl.absoluteURL) ?? []
        let arr = cookies.map { self.toSetCookieString($0) }
        result(arr)
      }
      task2.resume()
    }
    task1.resume()
  }

  /// 将 HTTPCookie 序列化为 Set-Cookie 字符串（含 Secure / Path 等属性）。
  private func toSetCookieString(_ cookie: HTTPCookie) -> String {
    var parts = ["\(cookie.name)=\(cookie.value)"]
    parts.append("Path=\(cookie.path.isEmpty ? "/" : cookie.path)")
    if !cookie.domain.isEmpty {
      parts.append("Domain=\(cookie.domain)")
    }
    if cookie.isSecure { parts.append("Secure") }
    if cookie.isHTTPOnly { parts.append("HttpOnly") }
    return parts.joined(separator: "; ")
  }

  private func extract(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let r = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[r])
  }

  private func solvePow(challengeId: String, difficultyBits: Int) -> Int {
    let prefix = "gatekeeper-pow-v1:\(challengeId):"
    let prefixData = prefix.data(using: .utf8)!
    let fullBytes = difficultyBits / 8
    let remBits = difficultyBits % 8
    var nonce = 0
    while true {
      let msg = prefixData + "\(nonce)".data(using: .utf8)!
      let hash = sha256(msg)
      var ok = true
      for i in 0..<fullBytes {
        if hash[i] != 0 { ok = false; break }
      }
      if ok && remBits > 0 {
        let mask = UInt8(0xFF << (8 - remBits))
        if (hash[fullBytes] & mask) != 0 { ok = false }
      }
      if ok { return nonce }
      nonce += 1
    }
  }

  private func sha256(_ data: Data) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
      _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash
  }
}
