import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';
import 'state_views.dart';

/// 通用更新弹窗（CloudDrive 风格）：
///  - 顶部居中图标
///  - 居中加粗大标题
///  - 版本号一行
///  - 可滚动 Release Notes
///  - 下载中状态：带下载进度条
///  - 底部按钮文字风格，次要居左/中、主要居右
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

    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部图标
            Icon(
              isReady
                  ? Icons.check_circle_outline
                  : isDownloading
                      ? Icons.downloading
                      : Icons.system_update_alt,
              size: 44,
              color: isReady
                  ? Colors.green
                  : isFailed
                      ? scheme.error
                      : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),

            // 标题
            Text(
              _title(isDownloading, isReady, isFailed),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 14),

            // 描述
            Text(
              _subtitle(info.version, isDownloading, isReady),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),

            // 进度条（仅下载中显示）
            if (isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: update.progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${(update.progress * 100).toStringAsFixed(0)}%  ·  '
                  '${_fmtSize(update.receivedBytes)} / ${_fmtSize(update.expectedBytes)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (update.mirrorName != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '加速镜像：${update.mirrorName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],

            // Release Notes（可滚动）
            if (!isDownloading && !isReady)
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(
                      info.releaseNotes.trim().isEmpty
                          ? '本次更新暂无说明'
                          : info.releaseNotes,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.65,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),

            if (isReady) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle, size: 36, color: scheme.primary),
            ],

            if (isFailed && update.error != null) ...[
              const SizedBox(height: 4),
              Text(
                update.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.error,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 底部按钮行
            Row(
              children: [
                // 下载中：左侧「隐藏」
                if (isDownloading)
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('隐藏'),
                    ),
                  )
                // 未下载：左侧「跳过此版本」
                else if (!isReady)
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        settings.skippedVersion = info.version;
                        Navigator.pop(context);
                      },
                      child: const Text('跳过此版本'),
                    ),
                  ),
                // 已就绪：左侧空出
                if (isDownloading)
                  const SizedBox(width: 12),

                // 主按钮
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () {
                      if (isDownloading) {
                        update.cancel();
                      } else if (isFailed) {
                        update.startDownload();
                      } else if (isReady) {
                        _install(context, update);
                      } else {
                        update.startDownload();
                      }
                    },
                    child: Text(
                      isDownloading
                          ? '取消下载'
                          : isFailed
                              ? '重新下载'
                              : isReady
                                  ? '立即安装'
                                  : '下载并安装',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _title(bool downloading, bool ready, bool failed) {
    if (ready) return '下载完成';
    if (downloading) return '正在下载更新';
    if (failed) return '下载失败';
    return '有可用更新';
  }

  String _subtitle(String version, bool downloading, bool ready) {
    if (ready) return '新版本 v$version 已下载完成';
    if (downloading) return '正在下载 v$version，完成后可立即安装';
    return '发现新版本 v$version';
  }

  Future<void> _install(BuildContext ctx, UpdateService update) async {
    final result = await update.install();
    if (!ctx.mounted) return;
    showToast(
      ctx,
      result.message,
      icon: result.ok ? Icons.check_circle_outline : Icons.error_outline,
      isError: !result.ok,
    );
    if (widget.autoDismissOnInstall && result.ok) {
      Navigator.pop(ctx);
    }
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
