import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/state_views.dart';
import 'update_screen.dart';

/// 关于页：参考 CloudDrive 风格，包含系统信息、应用更新、外部链接。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';
  String _osInfo = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion} on ${Platform.localHostname}';
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
      _osInfo = os;
    });
  }

  Future<void> _checkUpdate() async {
    final updateService = context.read<UpdateService>();
    final settings = context.read<SettingsService>();
    setState(() => _checking = true);
    final hasNew = await updateService.checkForUpdate(
      includePrerelease: settings.includePrerelease,
    );
    if (!mounted) return;
    setState(() => _checking = false);
    if (hasNew) {
      _showUpdateDialog();
    } else {
      showToast(context, '当前已是最新版本', icon: Icons.verified_outlined);
    }
  }

  void _showUpdateDialog() {
    final updateService = context.read<UpdateService>();
    final settings = context.read<SettingsService>();
    final update = updateService.update;
    if (update == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.system_update_alt, size: 40),
        title: const Text('有可用更新'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '发现新版本 v${update.version}。',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    update.releaseNotes.trim().isEmpty
                        ? '本次更新暂无说明'
                        : update.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              settings.skippedVersion = update.version;
              Navigator.pop(ctx);
            },
            child: const Text('跳过此版本'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UpdateScreen()),
              );
            },
            child: const Text('下载并安装'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final update = context.watch<UpdateService>();

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          // ---------- 应用标识 ----------
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.menu_book, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text(
                  '漫境 ComicRealm',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '支持多图源的开源漫画阅读器',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // ---------- 系统信息 ----------
          const _SectionLabel('系统信息'),
          const _InfoRow(label: '产品名称', value: '漫境 ComicRealm'),
          _InfoRow(label: '版本', value: '$_version ($_buildNumber)'),
          _InfoRow(label: '操作系统', value: _osInfo),

          // ---------- 应用更新 ----------
          const _SectionLabel('应用更新'),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            subtitle: Text(update.hasUpdate
                ? '发现新版本 v${update.update?.version}'
                : '从 GitHub 检查新版本'),
            trailing: _checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkUpdate,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: const Text('包含预发布版本'),
            subtitle: const Text('在正式版之前获取测试版'),
            value: settings.includePrerelease,
            onChanged: (v) => settings.includePrerelease = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_none),
            title: const Text('启动时自动检查更新'),
            subtitle: const Text('发现新版本时在应用内提示'),
            value: settings.autoCheckUpdate,
            onChanged: (v) => settings.autoCheckUpdate = v,
          ),
          if (settings.skippedVersion.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text('已忽略版本 v${settings.skippedVersion}'),
              subtitle: const Text('点击恢复提示'),
              trailing: const Icon(Icons.undo, size: 20),
              onTap: () => settings.skippedVersion = '',
            ),

          // ---------- 外部链接 ----------
          const _SectionLabel('外部链接'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源仓库'),
            subtitle: const Text('GitHub: comic-realm'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final url = Uri.parse('https://github.com/2016YYy/comic-realm');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel),
            title: const Text('开源协议'),
            subtitle: const Text('MIT License'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final url = Uri.parse('https://opensource.org/licenses/MIT');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),

          // ---------- 免责声明 ----------
          const _SectionLabel('免责声明'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              '本软件为开源漫画阅读器，本身不存储、不上传任何漫画内容，'
              '仅作为用户访问第三方图源网站的解析工具。所有漫画作品的版权归原作者及图源网站所有。'
              '本软件仅供个人学习交流使用，严禁用于任何商业用途。'
              '使用者应遵守所在国家或地区的法律法规，因使用本软件产生的一切法律责任由使用者自行承担。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
