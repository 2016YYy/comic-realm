import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/source.dart';
import '../services/history_service.dart';
import '../services/source_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';
import 'comic_detail_screen.dart';
import 'search_screen.dart';
import 'source_discover_screen.dart';
import 'source_import_screen.dart';

/// 发现：最近阅读 + 按图源浏览分类，找不到内容时的总入口。
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sources = context.watch<SourceService>().enabledSources;
    final history = context.watch<HistoryService>().entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '导入图源',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SourceImportScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          _SearchBar(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          if (history.isNotEmpty) ...[
            SectionHeader(
              title: '最近阅读',
              trailing: TextButton(
                onPressed: () => _confirmClearHistory(context),
                child: const Text('清空'),
              ),
            ),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: history.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _HistoryCard(entry: history[i]),
              ),
            ),
          ],
          const SectionHeader(title: '图源'),
          if (sources.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyView(
                icon: Icons.dns_outlined,
                title: '还没有启用的图源',
                subtitle: '导入图源后即可在这里按分类浏览漫画',
                action: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SourceImportScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('导入图源'),
                ),
              ),
            )
          else
            ...sources.map((s) => _SourceTile(source: s)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
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
    if (ok == true) await history.clear();
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                '搜索漫画…',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ReadHistoryEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: entry.toComic())),
      ),
      onLongPress: () => context.read<HistoryService>().remove(entry.noteUrl),
      child: SizedBox(
        width: 108,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComicCover(url: entry.coverUrl, width: 108, height: 150),
            const SizedBox(height: 6),
            Text(
              entry.comicName.isEmpty ? '未知漫画' : entry.comicName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: scheme.onSurface,
              ),
            ),
            if (entry.chapterName.isNotEmpty)
              Text(
                '读到 ${entry.chapterName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final ComicSource source;

  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cats = source.findCategories;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.16),
        child: Icon(Icons.collections_bookmark_outlined, color: scheme.primary),
      ),
      title: Text(
        source.bookSourceName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        cats.isEmpty ? '暂未配置分类，可进入后搜索' : '${cats.length} 个分类 · 点击浏览',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SourceDiscoverScreen(source: source)),
      ),
    );
  }
}
