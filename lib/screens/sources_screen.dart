import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/source_service.dart';
import '../models/source.dart';
import '../widgets/state_views.dart';
import 'source_import_screen.dart';
import 'source_discover_screen.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  bool _detectingAll = false;

  @override
  Widget build(BuildContext context) {
    final sourceService = context.watch<SourceService>();
    final sources = sourceService.allSources;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图源管理'),
        actions: [
          if (sources.isNotEmpty)
            IconButton(
              icon: _detectingAll
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.health_and_safety_outlined),
              tooltip: '一键检测全部图源',
              onPressed: _detectingAll ? null : () => _detectAll(context),
            ),
          if (sources.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: '导出全部图源',
              onPressed: () => _exportSources(context, sources),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '导入图源',
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SourceImportScreen()));
            },
          ),
        ],
      ),
      body: sources.isEmpty
          ? EmptyView(
              icon: Icons.dns_outlined,
              title: '还没有图源',
              subtitle: '导入图源后即可搜索、按分类浏览漫画\n支持本地文件 / 二维码 / 网络地址',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SourceImportScreen())),
                icon: const Icon(Icons.add),
                label: const Text('导入图源'),
              ),
            )
          : ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                final color =
                    source.enable ? scheme.primary : scheme.onSurfaceVariant;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.16),
                    child: Icon(
                      source.enable ? Icons.cloud_done : Icons.cloud_off,
                      color: color,
                    ),
                  ),
                  title: Row(
                    children: [
                      // 源类型标识：漫画 / 小说 / 视频
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kindColor(source.kind, scheme)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          source.kindLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: _kindColor(source.kind, scheme),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(source.bookSourceName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _subtitle(source),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  isThreeLine: source.findCategories.isNotEmpty,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SourceDiscoverScreen(source: source)),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: source.enable,
                        onChanged: (_) => sourceService.toggleSource(source),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) =>
                            _onMenuSelected(context, value, source),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'detect',
                            child: Row(
                              children: [
                                Icon(Icons.health_and_safety_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('检测有效性'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'export',
                            child: Row(
                              children: [
                                Icon(Icons.file_download_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('导出此图源'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 20),
                                SizedBox(width: 12),
                                Text('删除'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _subtitle(ComicSource source) {
    final cats = source.findCategories;
    if (cats.isEmpty) return source.bookSourceUrl;
    return '${source.bookSourceUrl}\n${cats.length} 个分类 · 点击浏览';
  }

  void _onMenuSelected(
      BuildContext context, String value, ComicSource source) {
    if (value == 'detect') {
      _detectOne(context, source);
    } else if (value == 'export') {
      _exportSources(context, [source]);
    } else if (value == 'delete') {
      _confirmDelete(context, source);
    }
  }

  Future<void> _exportSources(BuildContext context, List<ComicSource> sources) async {
    final service = context.read<SourceService>();
    try {
      final path = await service.exportSourcesToFile(sources);
      if (!context.mounted) return;
      showToast(
        context,
        '已导出 ${sources.length} 个图源：$path',
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      if (!context.mounted) return;
      showToast(context, '导出失败：$e', isError: true);
    }
  }

  Future<void> _detectOne(BuildContext context, ComicSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<SourceService>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在检测图源…'),
          ],
        ),
      ),
    );
    final result = await service.detectAndHandle(source);
    if (!context.mounted) return;
    Navigator.pop(context); // 关闭 loading

    if (result.valid) {
      final msg = result.updated ? '图源有效，已自动更新规则' : '图源有效';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } else {
      messenger.showSnackBar(SnackBar(
          content: Text('图源已失效（${result.error}），已自动删除')));
    }
  }

  Future<void> _detectAll(BuildContext context) async {
    final service = context.read<SourceService>();
    setState(() => _detectingAll = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Flexible(child: Text('正在检测全部图源，失效的将自动删除…')),
          ],
        ),
      ),
    );
    final summary = await service.detectAndCleanAll();
    if (!context.mounted) {
      setState(() => _detectingAll = false);
      return;
    }
    Navigator.pop(context); // 关闭 loading
    setState(() => _detectingAll = false);

    final detail = StringBuffer();
    detail.writeln('共 ${summary.total} 个图源');
    detail.writeln('有效：${summary.valid} 个${summary.updated > 0 ? '（其中 ${summary.updated} 个已更新规则）' : ''}');
    detail.write('已删除失效：${summary.deleted} 个');
    if (summary.failures.isNotEmpty) {
      detail.writeln();
      detail.writeln('失效详情：');
      for (final f in summary.failures) {
        detail.writeln('• ${f.sourceName}：${f.error}');
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('检测完成'),
        content: Text(detail.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, ComicSource source) {
    final service = context.read<SourceService>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除图源'),
        content: Text('确定删除「${source.bookSourceName}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              service.removeSource(source);
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 源类型对应的徽标颜色
Color _kindColor(SourceKind kind, ColorScheme scheme) {
  switch (kind) {
    case SourceKind.comic:
      return scheme.primary;
    case SourceKind.novel:
      return Colors.orange;
    case SourceKind.video:
      return Colors.teal;
  }
}
