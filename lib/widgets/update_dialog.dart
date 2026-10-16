import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/state_views.dart';

/// 通用更新弹窗：显示版本说明，支持在弹窗内直接下载并安装。
///
/// 用于「关于」页检查更新和主界面自动检测更新两种场景。
class UpdateDialog extends StatefulWidget {
  final bool autoDismissOnInstall;

  const UpdateDialog({super.key, this.autoDismissOnInstall = true});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateService>();
    final settings = context.read<SettingsService>();
    final info = update.update;
    if (info == null) return const SizedBox.shrink();

    final phase = update.phase;
    final isDownloading = phase == UpdatePhase.downloading || phase == UpdatePhase.paused;
    final isReady = phase == UpdatePhase.ready;
    final isFailed = phase == UpdatePhase.failed;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: Icon(
        isReady ? Icons.check_circle_outline : Icons.system_update_alt,
        size: 40,
        color: isReady ? Colors.green : null,
      ),
      title: Text(isReady ? '下载完成' : '有可用更新'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isReady
                  ? 'v${info.version} 已下载完成'
                  : '发现新版本 v${info.version}。',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            if (!isReady) ...[
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes.trim().isEmpty
                        ? '本次更新暂无说明'
                        : info.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
              ),
            ],
            if (isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: update.progress.clamp(0.0, 1.0)),
              const SizedBox(height: 8),
              Text(
                '${(update.progress * 100).toStringAsFixed(0)}%  ·  '
                '${_fmtSize(update.receivedBytes)} / ${_fmtSize(update.expectedBytes)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (isFailed && update.error != null) ...[
              const SizedBox(height: 12),
              Text(
                update.error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!isDownloading && !isReady)
          TextButton(
            onPressed: () {
              settings.skippedVersion = info.version;
              Navigator.pop(context);
            },
            child: const Text('跳过此版本'),
          ),
        if (isDownloading)
          TextButton(
            onPressed: () => update.cancel(),
            child: const Text('取消下载'),
          )
        else if (isFailed)
          TextButton(
            onPressed: () => update.startDownload(),
            child: const Text('重新下载'),
          )
        else if (!isReady)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
        if (isReady)
          FilledButton.icon(
            onPressed: () async {
              final result = await update.install();
              if (!context.mounted) return;
              showToast(
                context,
                result.message,
                icon: result.ok ? Icons.check_circle_outline : Icons.error_outline,
                isError: !result.ok,
              );
              if (widget.autoDismissOnInstall && result.ok) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.install_desktop),
            label: const Text('立即安装'),
          )
        else if (!isDownloading)
          FilledButton.icon(
            onPressed: () => update.startDownload(),
            icon: const Icon(Icons.download),
            label: const Text('下载并安装'),
          ),
      ],
    );
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    var size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }
}

/// 便捷方法：显示更新弹窗
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const UpdateDialog(),
  );
}
