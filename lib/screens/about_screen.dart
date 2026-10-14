import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于漫境')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.menu_book, size: 80, color: Color(0xFF6C5CE7)),
            const SizedBox(height: 16),
            const Text('漫境 ComicRealm', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('v$_version', style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 24),
            const Text(
              '一款支持多图源的开源漫画阅读器。\n'
              '支持自定义图源导入（本地文件 / 二维码 / 网络地址），\n'
              '图源规则兼容 开源阅读(legado) / 异次元 格式。',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('开源仓库'),
              subtitle: const Text('GitHub: comic-realm'),
              onTap: () async {
                final url = Uri.parse('https://github.com/your-github-username/comic-realm');
                if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel),
              title: const Text('开源协议'),
              subtitle: const Text('MIT License'),
              onTap: () async {
                final url = Uri.parse('https://opensource.org/licenses/MIT');
                if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '免责声明\n\n'
                '本软件为开源漫画阅读器，本身不存储、不上传任何漫画内容，'
                '仅作为用户访问第三方图源网站的解析工具。所有漫画作品的版权归原作者及图源网站所有。'
                '本软件仅供个人学习交流使用，严禁用于任何商业用途。'
                '使用者应遵守所在国家或地区的法律法规，因使用本软件产生的一切法律责任由使用者自行承担。'
                '如本软件的任何内容侵犯了您的合法权益，请联系开发者，我们将在第一时间删除相关内容。',
                style: TextStyle(fontSize: 12, height: 1.6, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
