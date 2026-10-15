import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/comic.dart';
import '../services/comic_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';
import 'comic_detail_screen.dart';
import 'search_screen.dart';

/// 书架：收藏的漫画，支持网格 / 紧凑 / 列表三种视图与多种排序。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final comicService = context.watch<ComicService>();
    final settings = context.watch<SettingsService>();
    final history = context.watch<HistoryService>();
    final comics = _sorted(comicService.favorites, settings, history);

    return Scaffold(
      appBar: AppBar(
        title: Text(comics.isEmpty ? '书架' : '书架 · ${comics.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          _SortMenu(
            current: settings.librarySort,
            onChanged: (s) => settings.librarySort = s,
          ),
          _ViewModeButton(
            current: settings.libraryViewMode,
            onChanged: (m) => settings.libraryViewMode = m,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => comicService.reload(),
        child: comics.isEmpty
            ? _EmptyLibrary(
                onSearch: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                ),
              )
            : _LibraryBody(comics: comics, mode: settings.libraryViewMode),
      ),
    );
  }

  List<Comic> _sorted(
    List<Comic> source,
    SettingsService settings,
    HistoryService history,
  ) {
    final list = List<Comic>.from(source);
    switch (settings.librarySort) {
      case LibrarySort.title:
        list.sort((a, b) => a.name.compareTo(b.name));
      case LibrarySort.source:
        list.sort((a, b) {
          final c = a.sourceName.compareTo(b.sourceName);
          return c != 0 ? c : a.name.compareTo(b.name);
        });
      case LibrarySort.recent:
        list.sort((a, b) {
          final ta = history.entryFor(a.noteUrl)?.readAt ?? a.updateTime;
          final tb = history.entryFor(b.noteUrl)?.readAt ?? b.updateTime;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
      case LibrarySort.added:
        // Hive 的 values 本身按加入顺序返回，保持原样
        break;
    }
    return list;
  }
}

class _LibraryBody extends StatelessWidget {
  final List<Comic> comics;
  final LibraryViewMode mode;

  const _LibraryBody({required this.comics, required this.mode});

  @override
  Widget build(BuildContext context) {
    if (mode == LibraryViewMode.list) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: comics.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
        itemBuilder: (_, i) => _LibraryListTile(comic: comics[i]),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = mode == LibraryViewMode.compact;
        final targetWidth = compact ? 96.0 : 116.0;
        final columns =
            (constraints.maxWidth / targetWidth).floor().clamp(2, compact ? 6 : 4);
        return GridView.builder(
          padding: const EdgeInsets.all(AppTheme.gap),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: compact ? 0.58 : 0.56,
            crossAxisSpacing: AppTheme.gap,
            mainAxisSpacing: AppTheme.gap,
          ),
          itemCount: comics.length,
          itemBuilder: (_, i) =>
              _LibraryGridItem(comic: comics[i], compact: compact),
        );
      },
    );
  }
}

class _LibraryGridItem extends StatelessWidget {
  final Comic comic;
  final bool compact;

  const _LibraryGridItem({required this.comic, required this.compact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: () => _open(context, comic),
      onLongPress: () => _confirmRemove(context, comic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: 'cover-${comic.noteUrl}',
              child: ComicCover(url: comic.coverUrl, width: double.infinity),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            comic.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: scheme.onSurface,
            ),
          ),
          if (!compact && comic.lastChapter.isNotEmpty)
            Text(
              comic.lastChapter,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _LibraryListTile extends StatelessWidget {
  final Comic comic;

  const _LibraryListTile({required this.comic});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ComicCover(url: comic.coverUrl, width: 56, height: 78),
      title: Text(
        comic.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comic.author.isNotEmpty)
              Text(
                comic.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            if (comic.lastChapter.isNotEmpty)
              Text(
                '最新：${comic.lastChapter}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            if (comic.sourceName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SourceBadge(label: comic.sourceName),
              ),
          ],
        ),
      ),
      onTap: () => _open(context, comic),
      onLongPress: () => _confirmRemove(context, comic),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onSearch;

  const _EmptyLibrary({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        EmptyView(
          icon: Icons.menu_book_outlined,
          title: '书架空空如也',
          subtitle: '搜索漫画并收藏后，就会出现在这里\n也可以先到「图源」导入更多图源',
          action: FilledButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search),
            label: const Text('去搜索'),
          ),
        ),
      ],
    );
  }
}

class _SortMenu extends StatelessWidget {
  final LibrarySort current;
  final ValueChanged<LibrarySort> onChanged;

  const _SortMenu({required this.current, required this.onChanged});

  static const _labels = {
    LibrarySort.added: '最近加入',
    LibrarySort.recent: '最近阅读',
    LibrarySort.title: '标题',
    LibrarySort.source: '图源',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibrarySort>(
      icon: const Icon(Icons.sort),
      tooltip: '排序：${_labels[current]}',
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (context) => LibrarySort.values
          .map((s) => PopupMenuItem(
                value: s,
                child: Row(
                  children: [
                    if (s == current)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(_labels[s] ?? ''),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final LibraryViewMode current;
  final ValueChanged<LibraryViewMode> onChanged;

  const _ViewModeButton({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final next = switch (current) {
      LibraryViewMode.grid => LibraryViewMode.compact,
      LibraryViewMode.compact => LibraryViewMode.list,
      LibraryViewMode.list => LibraryViewMode.grid,
    };
    final icon = switch (current) {
      LibraryViewMode.grid => Icons.grid_view_rounded,
      LibraryViewMode.compact => Icons.apps_rounded,
      LibraryViewMode.list => Icons.view_list_rounded,
    };
    return IconButton(
      icon: Icon(icon),
      tooltip: '切换视图',
      onPressed: () => onChanged(next),
    );
  }
}

void _open(BuildContext context, Comic comic) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: comic)),
  );
}

Future<void> _confirmRemove(BuildContext context, Comic comic) async {
  final service = context.read<ComicService>();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('从书架移除'),
            subtitle: Text(comic.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    ),
  );
  if (ok == true) await service.removeFavorite(comic);
}
