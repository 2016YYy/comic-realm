import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/source_service.dart';
import '../models/source.dart';
import '../widgets/state_views.dart';
import 'source_import_screen.dart';
import 'source_discover_screen.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sourceService = context.watch<SourceService>();
    final sources = sourceService.allSources;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图源管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '导入图源',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceImportScreen()));
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
                final color = source.enable ? scheme.primary : scheme.onSurfaceVariant;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.16),
                    child: Icon(
                      source.enable ? Icons.cloud_done : Icons.cloud_off,
                      color: color,
                    ),
                  ),
                  title: Text(source.bookSourceName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _subtitle(source),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  isThreeLine: source.findCategories.isNotEmpty,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SourceDiscoverScreen(source: source)),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: source.enable,
                        onChanged: (_) => sourceService.toggleSource(source),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, sourceService, source),
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
    return '$source.bookSourceUrl\n${cats.length} 个分类 · 点击浏览';
  }

  void _confirmDelete(BuildContext context, SourceService service, ComicSource source) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除图源'),
        content: Text('确定删除「${source.bookSourceName}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
