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

/// 书架：收藏的漫画，支持自定义文件夹、网格 / 紧凑 / 列表视图与两种排序。
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedFolder = ''; // '' 表示「全部」

  @override
  Widget build(BuildContext context) {
    final comicService = context.watch<ComicService>();
    final settings = context.watch<SettingsService>();
    final history = context.watch<HistoryService>();
    final folders = settings.folders;
    final all = _sorted(comicService.favorites, settings, history);
    final comics = _selectedFolder.isEmpty
        ? all
        : all.where((c) => c.folder == _selectedFolder).toList();

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
      body: Column(
        children: [
          _FolderBar(
            folders: folders,
            selected: _selectedFolder,
            onSelected: (f) => setState(() => _selectedFolder = f),
            onAdd: _createFolder,
            onRename: _renameFolder,
            onDelete: _deleteFolder,
          ),
          Expanded(
            child: RefreshIndicator(
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
          ),
        ],
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
        break;
    }
    return list;
  }

  Future<void> _createFolder() async {
    final name = await _promptFolderName(context, title: '新建文件夹');
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    context.read<SettingsService>().addFolder(name.trim());
  }

  Future<void> _renameFolder(String old) async {
    final name = await _promptFolderName(context, title: '重命名文件夹', initial: old);
    if (name == null || name.trim().isEmpty || name.trim() == old) return;
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final comicService = context.read<ComicService>();
    settings.renameFolder(old, name.trim());
    // 同步移动该文件夹下漫画的 folder 字段
    await comicService.moveFolderContents(old, name.trim());
    if (_selectedFolder == old) {
      setState(() => _selectedFolder = name.trim());
    }
  }

  Future<void> _deleteFolder(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确定删除「$name」吗？其中的漫画将移回「全部」。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final comicService = context.read<ComicService>();
    await comicService.moveFolderContents(name, '');
    settings.removeFolder(name);
    if (_selectedFolder == name) setState(() => _selectedFolder = '');
  }
}

/// 文件夹切换条：全部 + 各文件夹 + 新建
class _FolderBar extends StatelessWidget {
  final List<String> folders;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdd;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onDelete;

  const _FolderBar({
    required this.folders,
    required this.selected,
    required this.onSelected,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _chip(context, '全部', ''),
          ...folders.map((f) => _chip(context, f, f, folder: f)),
          _addButton(context),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String value, {String? folder}) {
    final active = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelected(value),
        onLongPress: folder == null ? null : () => _folderMenu(context, folder),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: active
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.add, size: 16, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  void _folderMenu(BuildContext context, String folder) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                onRename(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除文件夹'),
              onTap: () {
                Navigator.pop(ctx);
                onDelete(folder);
              },
            ),
          ],
        ),
      ),
    );
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
      onLongPress: () => _showActions(context, comic),
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
      onLongPress: () => _showActions(context, comic),
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
  };

  static const _available = [LibrarySort.added, LibrarySort.recent];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LibrarySort>(
      icon: const Icon(Icons.sort),
      tooltip: '排序：${_labels[current] ?? '最近加入'}',
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (context) => _available
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

/// 长按漫画：弹出「移动到文件夹」/「从书架移除」
Future<void> _showActions(BuildContext context, Comic comic) async {
  final folders = context.read<SettingsService>().folders;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              comic.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('移动到文件夹'),
            onTap: () => Navigator.pop(ctx, '__move__'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('从书架移除'),
            onTap: () => Navigator.pop(ctx, '__remove__'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(ctx, null),
          ),
        ],
      ),
    ),
  );

  if (action == '__remove__') {
    await context.read<ComicService>().removeFavorite(comic);
    if (context.mounted) showToast(context, '已从书架移除');
    return;
  }

  if (action == '__move__') {
    if (!context.mounted) return;
    final target = await _pickFolder(context, folders, current: comic.folder);
    if (target == null) return;
    if (!context.mounted) return;
    await context.read<ComicService>().setComicFolder(comic, target);
    if (context.mounted) {
      showToast(context, target.isEmpty ? '已移回「全部」' : '已移动到「$target」');
    }
  }
}

/// 选择目标文件夹（含「全部」「新建文件夹」）
Future<String?> _pickFolder(
  BuildContext context,
  List<String> folders, {
  required String current,
}) async {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inbox),
              title: Text('全部${current.isEmpty ? '  · 当前' : ''}'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            ...folders.map((f) => ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text('$f${f == current ? '  · 当前' : ''}'),
                  onTap: () => Navigator.pop(ctx, f),
                )),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建文件夹…'),
              onTap: () async {
                final name = await _promptFolderName(ctx, title: '新建文件夹');
                if (name != null && name.trim().isNotEmpty && ctx.mounted) {
                  Navigator.pop(ctx, name.trim());
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

/// 输入文件夹名对话框
Future<String?> _promptFolderName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '文件夹名称'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
