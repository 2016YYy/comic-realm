import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/download.dart';
import '../services/download_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';

/// 下载管理：查看章节下载进度、清理已下载内容。
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();
    final tasks = downloadService.tasks;

    return Scaffold(
      appBar: AppBar(
        title: Text(tasks.isEmpty ? '下载' : '下载 · ${tasks.length}'),
      ),
      body: tasks.isEmpty
          ? const EmptyView(
              icon: Icons.download_outlined,
              title: '还没有下载任务',
              subtitle: '在漫画详情页点击章节右侧的下载按钮，即可离线缓存',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, i) => _DownloadTile(task: tasks[i]),
            ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadTask task;

  const _DownloadTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = task.statusEnum;
    final downloading = status == DownloadStatus.downloading;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: ComicCover(url: task.coverUrl, width: 44, height: 62, radius: 8),
      title: Text(
        task.chapterName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${task.comicName} · ${task.sourceName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          if (downloading)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.totalPages > 0 ? task.progress : null,
                minHeight: 4,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(_statusIcon(status), size: 13, color: _statusColor(status, scheme)),
              const SizedBox(width: 4),
              Text(
                _statusText(status, task),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除',
        onPressed: () => _confirmDelete(context, task),
      ),
    );
  }

  IconData _statusIcon(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.downloading:
        return Icons.downloading;
      case DownloadStatus.completed:
        return Icons.check_circle;
      case DownloadStatus.failed:
        return Icons.error_outline;
      case DownloadStatus.paused:
        return Icons.pause_circle_outline;
      case DownloadStatus.pending:
        return Icons.hourglass_empty;
    }
  }

  Color _statusColor(DownloadStatus s, ColorScheme scheme) {
    switch (s) {
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return scheme.error;
      default:
        return scheme.primary;
    }
  }

  String _statusText(DownloadStatus s, DownloadTask task) {
    switch (s) {
      case DownloadStatus.downloading:
        return '下载中 ${task.downloadedPages}/${task.totalPages}';
      case DownloadStatus.completed:
        return '已完成 · ${task.totalPages} 页';
      case DownloadStatus.failed:
        return '下载失败';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.pending:
        return '等待中';
    }
  }

  Future<void> _confirmDelete(BuildContext context, DownloadTask task) async {
    final service = context.read<DownloadService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除下载'),
        content: Text('确定删除「${task.chapterName}」的本地缓存吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await service.deleteTask(task);
  }
}

/// 让下载页复用统一的圆角卡片间距常量，避免硬编码。
const double kDownloadGap = AppTheme.gap;
