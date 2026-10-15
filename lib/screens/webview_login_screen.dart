import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/http_client.dart';
import '../core/native_cookie_manager.dart';

/// 通过 WebView 访问图源站点，手动通过反爬验证（Cloudflare / Gatekeeper PoW 等），
/// 验证通过后将全部 Cookie（含 HttpOnly）同步到应用的 CookieJar，使后续请求正常。
class WebViewLoginScreen extends StatefulWidget {
  /// 初始加载的 URL，通常为图源的搜索页或首页。
  final String? initialUrl;

  const WebViewLoginScreen({super.key, this.initialUrl});

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  late final WebViewController _controller;
  late final TextEditingController _urlController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? 'https://cn.bzmgcn.com');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            setState(() => _loading = false);
            // 将 WebView 中的全部 Cookie（含 HttpOnly）同步到应用 CookieJar。
            // document.cookie 拿不到 HttpOnly，故走原生 CookieManager。
            await _syncCookies();
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
  }

  Future<void> _syncCookies() async {
    try {
      final uri = Uri.parse(_urlController.text);
      final cookies = await NativeCookieManager.getCookies(_urlController.text);
      if (cookies.isNotEmpty) {
        await HttpClient().cookieJar.saveFromResponse(uri, cookies);
      }
    } catch (_) {}
  }

  void _go() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      _controller.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('过验证'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '验证完成',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cookie 已同步，返回即可正常使用')),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '输入图源地址',
                    ),
                    onSubmitted: (_) => _go(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _go),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
