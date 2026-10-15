import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';

/// 应用内更新：检查 → 更新说明 → 下载（进度条 / 可后台 / 可续传）→ 安装。
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    // 进来就自动检查一次（若还没有结果）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<UpdateService>();
      if (service.update == null) {
        service.checkForUpdate();
      }
    });
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _currentVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<UpdateService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('应用更新'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新检查',
            onPressed: service.isChecking
                ? null
                : () => service.checkForUpdate(
                      skippedVersion: context.read<SettingsService>().skippedVersion,
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _VersionHeader(currentVersion: _currentVersion, service: service),
          const SizedBox(height: 16),
          _buildBody(context, service),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, UpdateService service) {
    switch (service.phase) {
      case UpdatePhase.idle:
        return _StateCard(
          icon: Icons.verified_outlined,
          title: '已是最新版本',
          subtitle: service.lastCheckedAt == null
              ? '点击右上角检查是否有新版本'
              : '上次检查：${_timeLabel(service.lastCheckedAt!)}',
        );
      case UpdatePhase.checking:
        return const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator()),
        );
      case UpdatePhase.available:
        return _AvailableCard(service: service);
      case UpdatePhase.downloading:
      case UpdatePhase.paused:
        return _ProgressCard(service: service);
      case UpdatePhase.ready:
        return _ReadyCard(service: service);
      case UpdatePhase.failed:
        return _FailedCard(service: service);
    }
  }

  String _timeLabel(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

// ---------------------------- 顶部版本信息 ----------------------------

class _VersionHeader extends StatelessWidget {
  final String currentVersion;
  final UpdateService service;

  const _VersionHeader({required this.currentVersion, required this.service});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final update = service.update;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.system_update_alt, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前版本 v$currentVersion',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    update != null && update.isNewer
                        ? '发现新版本 v${update.version}'
                        : '漫境 ComicRealm 应用内更新',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------- 各阶段卡片 ----------------------------

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          children: [
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class _AvailableCard extends StatelessWidget {
  final UpdateService service;

  const _AvailableCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final update = service.update!;
    final settings = context.read<SettingsService>();
    final hasAsset = service.hasDownloadableAsset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.new_releases_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'v${update.version} 更新内容',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (update.releaseNotes.trim().isEmpty)
                  Text(
                    '本次更新暂无说明',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  )
                else
                  SelectableText(
                    update.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (hasAsset) ...[
          FilledButton.icon(
            onPressed: () => service.startDownload(),
            icon: const Icon(Icons.download),
            label: Text('下载 v${update.version}（可在后台进行）'),
          ),
          const SizedBox(height: 8),
          Text(
            '下载过程可切到后台，通知栏会显示实时进度；随时可回到应用暂停 / 继续。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ] else
          _StateCard(
            icon: Icons.devices_other,
            title: '当前平台暂无应用内安装包',
            subtitle: '本次发布未提供与本机平台匹配的安装包，可前往 Release 页面手动下载。',
            action: FilledButton.tonalIcon(
              onPressed: () => service.openReleasePage(),
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开发布页面'),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => service.openReleasePage(),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Release 页面'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  settings.skippedVersion = update.version;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已忽略 v${update.version}，下次不再提示')),
                  );
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('忽略此版本'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final UpdateService service;

  const _ProgressCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paused = service.phase == UpdatePhase.paused;
    final percent = (service.progress * 100).clamp(0, 100);
    final received = service.receivedBytes;
    final expected = service.expectedBytes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  paused ? Icons.pause_circle_outline : Icons.downloading,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  paused ? '已暂停' : '正在下载更新包',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: service.progress > 0 ? service.progress : null,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  expected > 0
                      ? '${_bytes(received)} / ${_bytes(expected)}'
                      : _bytes(received),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                if (!paused && service.speedMBps > 0)
                  Text(
                    '${service.speedMBps.toStringAsFixed(2)} MB/s',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            if (!paused && service.remaining != null) ...[
              const SizedBox(height: 4),
              Text(
                '预计剩余 ${_duration(service.remaining!)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '可切到后台继续下载，通知栏会显示进度',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: paused ? () => service.resume() : () => service.pause(),
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? '继续下载' : '暂停'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => service.cancel(),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('取消'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  final UpdateService service;

  const _ReadyCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '更新包已下载完成',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '点击下方按钮调起系统安装界面完成更新。',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                final result = await service.install();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.message)),
                );
              },
              icon: const Icon(Icons.install_desktop),
              label: const Text('立即安装'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => service.cancel(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新下载'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  final UpdateService service;

  const _FailedCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.error),
                const SizedBox(width: 8),
                Text(
                  '下载 / 检查失败',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: scheme.error),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              service.error ?? '请稍后重试',
              style: TextStyle(fontSize: 13, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: service.hasDownloadableAsset
                  ? () => service.startDownload()
                  : () => service.checkForUpdate(
                        skippedVersion: context.read<SettingsService>().skippedVersion,
                      ),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------- 工具 ----------------------------

String _bytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

String _duration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} 秒';
  if (d.inMinutes < 60) return '${d.inMinutes} 分 ${d.inSeconds % 60} 秒';
  return '${d.inHours} 时 ${d.inMinutes % 60} 分';
}
