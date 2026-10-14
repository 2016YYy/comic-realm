import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download.dart';
import '../services/download_service.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();
    final tasks = downloadService.tasks;

    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: tasks.isEmpty
          ? Center(child: Text('还没有下载任务', style: TextStyle(color: Colors.grey[500])))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  leading: Icon(_statusIcon(task.statusEnum), color: _statusColor(task.statusEnum)),
                  title: Text(task.chapterName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${task.comicName} · ${task.sourceName}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      if (task.statusEnum == DownloadStatus.downloading || task.totalPages > 0)
                        LinearProgressIndicator(value: task.progress),
                      const SizedBox(height: 4),
                      Text(
                        task.statusEnum == DownloadStatus.downloading
                            ? '下载中 ${task.downloadedPages}/${task.totalPages}'
                            : _statusText(task.statusEnum),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  trailing: task.statusEnum == DownloadStatus.completed
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => downloadService.deleteTask(task),
                        )
                      : null,
                );
              },
            ),
    );
  }

  IconData _statusIcon(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.downloading:
        return Icons.downloading;
      case DownloadStatus.completed:
        return Icons.download_done;
      case DownloadStatus.failed:
        return Icons.error;
      case DownloadStatus.paused:
        return Icons.pause;
      default:
        return Icons.hourglass_empty;
    }
  }

  Color _statusColor(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.downloading:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _statusText(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '下载失败';
      case DownloadStatus.paused:
        return '已暂停';
      default:
        return '等待中';
    }
  }
}
