import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/comic.dart';
import '../models/download.dart';
import '../services/download_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/glass.dart';
import '../widgets/state_views.dart';
import 'reader_screen.dart';

/// 侧滑删除确认：返回 true 才真正移除任务
Future<bool> _confirmSwipeDelete(BuildContext context, DownloadTask task) async {
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
  return ok == true;
}

/// 侧滑时露出的红色删除背景
class _SwipeDeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.delete_outline, color: scheme.onErrorContainer, size: 26),
    );
  }
}

/// 下载管理：查看章节下载进度、清理已下载内容。
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();
    final tasks = downloadService.tasks;

    return Scaffold(
      appBar: GlassAppBar(
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
              // 侧滑删除：向左滑出删除按钮，确认后删除本地缓存
              itemBuilder: (_, i) => Dismissible(
                key: ValueKey(tasks[i].taskId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmSwipeDelete(context, tasks[i]),
                background: _SwipeDeleteBackground(),
                onDismissed: (_) {
                  context.read<DownloadService>().deleteTask(tasks[i]);
                  showToast(context, '已删除「${tasks[i].chapterName}」');
                },
                child: _DownloadTile(task: tasks[i]),
              ),
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
    final completed = status == DownloadStatus.completed;

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
              if (completed) ...[
                const SizedBox(width: 6),
                Icon(Icons.offline_bolt, size: 12, color: scheme.primary),
              ],
            ],
          ),
        ],
      ),
      trailing: completed
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: '离线阅读',
                  onPressed: () => _openOffline(context),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除',
                  onPressed: () => _confirmDelete(context, task),
                ),
              ],
            )
          : IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: () => _confirmDelete(context, task),
            ),
      onTap: completed ? () => _openOffline(context) : null,
    );
  }

  Future<void> _openOffline(BuildContext context) async {
    if (task.savePath.isEmpty) return;
    final dir = Directory(task.savePath);
    if (!await dir.exists()) {
      if (!context.mounted) return;
      showToast(context, '本地缓存已丢失，请重新下载', isError: true);
      return;
    }
    final files = await dir.list().toList();
    final isNovel = files.any((f) => f.path.endsWith('.txt'));

    final comic = Comic(
      name: task.comicName,
      coverUrl: task.coverUrl,
      noteUrl: task.chapterUrl,
      sourceUrl: task.sourceUrl,
      sourceName: task.sourceName,
    );

    if (isNovel) {
      final textFile = files.firstWhere(
        (f) => f.path.endsWith('.txt'),
        orElse: () => File(''),
      );
      final text = textFile is File ? await textFile.readAsString() : '';
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen.offline(comic: comic, text: text),
        ),
      );
    } else {
      files.sort((a, b) => a.path.compareTo(b.path));
      final imagePaths = files.whereType<File>().map((f) => f.path).toList();
      if (imagePaths.isEmpty && context.mounted) {
        showToast(context, '本地缓存为空，请重新下载', isError: true);
        return;
      }
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen.offline(comic: comic, images: imagePaths),
        ),
      );
    }
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
