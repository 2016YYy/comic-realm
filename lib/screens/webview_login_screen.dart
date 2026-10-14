import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/http_client.dart';

/// 通过 WebView 访问图源站点，手动通过 Cloudflare 验证，
/// 验证通过后将 Cookie 同步到应用的 CookieJar，使后续请求正常。
class WebViewLoginScreen extends StatefulWidget {
  const WebViewLoginScreen({super.key});

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController(text: 'https://mycomic.com');
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            setState(() => _loading = false);
            // 将 WebView 中的 Cookie 同步到应用的 CookieJar
            await _syncCookies();
          },
        ),
      )
      ..loadRequest(Uri.parse(_urlController.text));
  }

  Future<void> _syncCookies() async {
    try {
      final cookies = await _controller.runJavaScriptReturningResult('document.cookie');
      if (cookies is String && cookies.isNotEmpty) {
        final uri = Uri.parse(_urlController.text);
        final cookieJar = HttpClient().cookieJar;
        final cookieList = cookies.split(';').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        await cookieJar.saveFromResponse(uri, cookieList.map((c) {
          final idx = c.indexOf('=');
          if (idx > 0) {
            return Cookie(c.substring(0, idx), c.substring(idx + 1));
          }
          return Cookie(c, '');
        }).toList());
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
          IconButton(icon: const Icon(Icons.check), tooltip: '验证完成', onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cookie 已同步，返回即可正常使用')));
            Navigator.pop(context);
          }),
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
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
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
