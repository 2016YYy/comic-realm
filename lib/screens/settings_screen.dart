import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/backup_service.dart';
import '../services/comic_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/source_service.dart';
import '../services/update_service.dart';
import 'about_screen.dart';
import 'update_screen.dart';
import 'webview_login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final update = context.watch<UpdateService>();
    final historyCount = context.watch<HistoryService>().entries.length;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---------- 外观 ----------
          const _SectionTitle('外观'),
          _ThemeModeTile(settings: settings),
          _SeedColorTile(settings: settings),

          // ---------- 阅读 ----------
          const _SectionTitle('阅读'),
          SwitchListTile(
            secondary: const Icon(Icons.swap_vert),
            title: const Text('竖向连续滚动'),
            subtitle: const Text('关闭后使用横向翻页（按章节）'),
            value: settings.readerContinuous,
            onChanged: (v) => settings.readerContinuous = v,
          ),

          // ---------- 更新 ----------
          const _SectionTitle('更新'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_none),
            title: const Text('启动时自动检查更新'),
            subtitle: const Text('发现新版本时在应用内提示'),
            value: settings.autoCheckUpdate,
            onChanged: (v) => settings.autoCheckUpdate = v,
          ),
          ListTile(
            leading: Badge(
              isLabelVisible: update.hasUpdate,
              child: const Icon(Icons.system_update_alt),
            ),
            title: const Text('检查更新'),
            subtitle: Text(update.phaseLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UpdateScreen()),
            ),
          ),
          if (settings.skippedVersion.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text('已忽略版本 v${settings.skippedVersion}'),
              subtitle: const Text('点击恢复提示'),
              trailing: const Icon(Icons.undo, size: 20),
              onTap: () => settings.skippedVersion = '',
            ),

          // ---------- 图源 ----------
          const _SectionTitle('图源'),
          ListTile(
            leading: const Icon(Icons.web),
            title: const Text('WebView 通过验证'),
            subtitle: const Text('访问受 Cloudflare 保护的站点时使用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebViewLoginScreen()),
            ),
          ),

          // ---------- 数据 ----------
          const _SectionTitle('数据'),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出备份'),
            subtitle: const Text('图源 / 收藏 / 阅读历史 / 偏好设置'),
            trailing: _backupBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _backupBusy ? null : _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('从备份恢复'),
            subtitle: const Text('选择之前导出的 JSON 备份文件'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_backupBusy,
            onTap: _restoreBackup,
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('清空阅读历史'),
            subtitle: Text('共 $historyCount 条记录'),
            trailing: const Icon(Icons.delete_outline),
            onTap: historyCount == 0 ? null : _clearHistory,
          ),

          // ---------- 关于 ----------
          const _SectionTitle('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于漫境'),
            subtitle: Text('当前版本 v$_version'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '免责声明：\n'
              '本软件为开源漫画阅读器，仅提供图源解析与阅读功能，本身不存储任何漫画内容。'
              '所有漫画版权归原作者及图源网站所有。请遵守当地法律法规，仅用于个人学习交流，'
              '请勿用于商业用途。',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 备份 / 恢复 ----------------

  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      final json = BackupService().buildBackupJson(appVersion: _version);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出备份',
        fileName: BackupService().suggestedFileName(),
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(json),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? '已取消导出' : '备份已导出')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() => _backupBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path != null ? await _readFile(file.path!) : null);
      if (bytes == null) {
        throw const FormatException('无法读取所选文件');
      }
      final summary = await BackupService().restore(utf8.decode(bytes));
      if (!mounted) return;
      context.read<SourceService>().reload();
      context.read<ComicService>().reload();
      context.read<HistoryService>().reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复完成：$summary')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<List<int>> _readFile(String path) async {
    return await File(path).readAsBytes();
  }

  Future<void> _clearHistory() async {
    final history = context.read<HistoryService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空阅读历史'),
        content: const Text('确定要清空全部阅读历史吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await history.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('阅读历史已清空')),
        );
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
      child: Text(
        title,
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

class _ThemeModeTile extends StatelessWidget {
  final SettingsService settings;

  const _ThemeModeTile({required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('主题模式'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
          ],
          selected: {settings.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => settings.themeMode = s.first,
        ),
      ),
    );
  }
}

class _SeedColorTile extends StatelessWidget {
  final SettingsService settings;

  const _SeedColorTile({required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('主题色'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppTheme.seeds.map((seed) {
            final selected = settings.seedColor.toARGB32() == seed.color.toARGB32();
            return Tooltip(
              message: seed.label,
              child: GestureDetector(
                onTap: () => settings.seedColor = seed.color,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: seed.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
