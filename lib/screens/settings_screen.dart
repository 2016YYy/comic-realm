import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/updater.dart';
import 'webview_login_screen.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = info.version);
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    // 仓库名需与实际 GitHub 仓库一致
    final updater = Updater(owner: '2016YYy', repo: 'comic-realm');
    final update = await updater.checkUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检查更新失败')));
    } else if (update.isNewer) {
      _showUpdateDialog(update);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已是最新版本')));
    }
  }

  void _showUpdateDialog(AppUpdate update) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('发现新版本 v${update.version}'),
        content: SingleChildScrollView(
          child: Text(update.releaseNotes.isEmpty ? '暂无更新说明' : update.releaseNotes),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('稍后')),
          FilledButton(
            onPressed: () async {
              final url = update.downloadUrl;
              if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
              Navigator.pop(context);
            },
            child: const Text('去下载'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.web),
            title: const Text('WebView 过 Cloudflare 验证'),
            subtitle: const Text('访问受 Cloudflare 保护的图源时使用'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WebViewLoginScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.update),
            title: const Text('检查更新'),
            subtitle: Text(_checking ? '正在检查…' : '当前版本 v$_version'),
            trailing: _checking ? const CircularProgressIndicator() : null,
            onTap: _checking ? null : _checkUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '免责声明：\n'
              '本软件为开源漫画阅读器，仅提供图源解析与阅读功能，本身不存储任何漫画内容。'
              '所有漫画版权归原作者及图源网站所有。请遵守当地法律法规，仅用于个人学习交流，'
              '请勿用于商业用途。如本软件侵犯了您的权益，请联系开发者删除相关图源。',
              style: TextStyle(color: Colors.grey[500], fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
