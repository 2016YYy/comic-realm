import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/source_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';
import 'comic_detail_screen.dart';
import 'search_screen.dart';

/// 书架「已下载」筛选的哨兵值（与文件夹名区分）。
const String _kDownloadedFilter = '__downloaded__';

/// 书架：收藏的漫画，支持自定义文件夹、多选批量移动、
/// 全部 / 已下载筛选、网格 / 紧凑 / 列表视图与两种排序。
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedFolder = ''; // '' = 全部；_kDownloadedFilter = 已下载；其他 = 文件夹名
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final comicService = context.watch<ComicService>();
    final settings = context.watch<SettingsService>();
    final history = context.watch<HistoryService>();
    final downloadService = context.watch<DownloadService>();
    final folders = settings.folders;
    final all = _sorted(comicService.favorites, settings, history);
    final comics = _applyFilter(all, downloadService);

    return Scaffold(
      appBar: _selecting
          ? _buildSelectionAppBar(comics)
          : _buildDefaultAppBar(comics),
      body: Column(
        children: [
          if (!_selecting)
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
                  : _LibraryBody(
                      comics: comics,
                      mode: settings.libraryViewMode,
                      selecting: _selecting,
                      selected: _selected,
                      onToggle: _toggleSelect,
                      onLongPress: _showActions,
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selecting ? _buildSelectionBar() : null,
    );
  }

  AppBar _buildDefaultAppBar(List<Comic> comics) {
    return AppBar(
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
          current: context.watch<SettingsService>().librarySort,
          onChanged: (s) => context.read<SettingsService>().librarySort = s,
        ),
        _ViewModeButton(
          current: context.watch<SettingsService>().libraryViewMode,
          onChanged: (m) => context.read<SettingsService>().libraryViewMode = m,
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar(List<Comic> comics) {
    final allSelected = comics.isNotEmpty && _selected.length == comics.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: '退出多选',
        onPressed: _exitSelection,
      ),
      title: Text('已选 ${_selected.length}'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? '取消全选' : '全选',
          onPressed: () => _selectAll(comics, allSelected),
        ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exitSelection,
                icon: const Icon(Icons.close),
                label: const Text('取消'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _moveSelectedToFolder,
                icon: const Icon(Icons.drive_file_move_outline),
                label: Text('移动到文件夹（${_selected.length}）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Comic> _applyFilter(List<Comic> all, DownloadService downloadService) {
    if (_selectedFolder == _kDownloadedFilter) {
      return all.where((c) => downloadService.hasDownloadsFor(c)).toList();
    }
    if (_selectedFolder.isEmpty) return all;
    return all.where((c) => c.folder == _selectedFolder).toList();
  }

  void _enterSelection(Comic comic) {
    setState(() {
      _selecting = true;
      _selected.add(comic.uniqueKey);
    });
  }

  void _toggleSelect(Comic comic) {
    setState(() {
      if (!_selected.remove(comic.uniqueKey)) {
        _selected.add(comic.uniqueKey);
      }
    });
  }

  void _selectAll(List<Comic> comics, bool allSelected) {
    setState(() {
      if (allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(comics.map((c) => c.uniqueKey));
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
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
    if (!mounted) return;
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
    if (!mounted) return;
    if (_selectedFolder == name) setState(() => _selectedFolder = '');
  }

  /// 将多选中的漫画批量移动到目标文件夹（可新建）。
  Future<void> _moveSelectedToFolder() async {
    final folders = context.read<SettingsService>().folders;
    final target = await _pickFolder(context, folders, current: null);
    if (target == null) return;
    if (!mounted) return;
    final comicService = context.read<ComicService>();
    final keys = _selected.toList();
    for (final c in comicService.favorites) {
      if (keys.contains(c.uniqueKey)) {
        await comicService.setComicFolder(c, target);
      }
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    showToast(context, target.isEmpty ? '已移回「全部」' : '已移动到「$target」');
  }

  /// 长按漫画：下载 / 移动到文件夹 / 多选 / 从书架移除。
  Future<void> _showActions(Comic comic) async {
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
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载'),
              onTap: () => Navigator.pop(ctx, '__download__'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('移动到文件夹'),
              onTap: () => Navigator.pop(ctx, '__move__'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('多选'),
              onTap: () => Navigator.pop(ctx, '__multi__'),
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
    if (!mounted || action == null) return;

    switch (action) {
      case '__download__':
        await _downloadComic(comic);
      case '__move__':
        final folders = context.read<SettingsService>().folders;
        final target = await _pickFolder(context, folders, current: comic.folder);
        if (target == null || !mounted) return;
        await context.read<ComicService>().setComicFolder(comic, target);
        if (!mounted) return;
        showToast(context, target.isEmpty ? '已移回「全部」' : '已移动到「$target」');
      case '__multi__':
        _enterSelection(comic);
      case '__remove__':
        await context.read<ComicService>().removeFavorite(comic);
        if (!mounted) return;
        showToast(context, '已从书架移除');
    }
  }

  /// 从书架直接下载：先拉取章节，弹出多选后批量下载。
  Future<void> _downloadComic(Comic comic) async {
    ComicSource? source;
    for (final s in context.read<SourceService>().allSources) {
      if (s.bookSourceUrl == comic.sourceUrl) {
        source = s;
        break;
      }
    }
    if (source == null) {
      showToast(context, '未找到该漫画对应的图源，无法下载', isError: true);
      return;
    }

    final comicService = context.read<ComicService>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    List<Chapter> chapters = const <Chapter>[];
    try {
      chapters = await comicService.getChapters(source, comic);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, ComicService.friendlyError(e), isError: true);
      return;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (chapters.isEmpty) {
      showToast(context, '该漫画没有可下载的章节', isError: true);
      return;
    }

    final selected = await showModalBottomSheet<List<Chapter>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChapterPickerSheet(
        chapters: chapters,
        comicName: comic.name,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final downloadService = context.read<DownloadService>();
    showToast(context, '开始下载 ${selected.length} 个章节');
    for (final ch in selected) {
      await downloadService.downloadChapter(
        source: source,
        comic: comic,
        chapter: ch,
      );
    }
    if (!mounted) return;
    showToast(context, '下载完成，可在「下载」页查看');
  }
}

/// 文件夹切换条：全部 + 已下载 + 各文件夹 + 新建
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
          _chip(context, '已下载', _kDownloadedFilter),
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
  final bool selecting;
  final Set<String> selected;
  final ValueChanged<Comic> onToggle;
  final ValueChanged<Comic> onLongPress;

  const _LibraryBody({
    required this.comics,
    required this.mode,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == LibraryViewMode.list) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: comics.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
        itemBuilder: (_, i) => _LibraryListTile(
          comic: comics[i],
          selecting: selecting,
          isSelected: selected.contains(comics[i].uniqueKey),
          onToggle: () => onToggle(comics[i]),
          onLongPress: () => onLongPress(comics[i]),
        ),
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
          itemBuilder: (_, i) => _LibraryGridItem(
            comic: comics[i],
            compact: compact,
            selecting: selecting,
            isSelected: selected.contains(comics[i].uniqueKey),
            onToggle: () => onToggle(comics[i]),
            onLongPress: () => onLongPress(comics[i]),
          ),
        );
      },
    );
  }
}

class _LibraryGridItem extends StatelessWidget {
  final Comic comic;
  final bool compact;
  final bool selecting;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const _LibraryGridItem({
    required this.comic,
    required this.compact,
    required this.selecting,
    required this.isSelected,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: selecting ? onToggle : () => _open(context, comic),
      onLongPress: selecting ? onToggle : onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Hero(
                  tag: comic.heroTag,
                  child: ComicCover(url: comic.coverUrl, width: double.infinity),
                ),
                if (selecting)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _SelectBadge(selected: isSelected),
                  ),
              ],
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
  final bool selecting;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const _LibraryListTile({
    required this.comic,
    required this.selecting,
    required this.isSelected,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: selecting
          ? Checkbox(value: isSelected, onChanged: (_) => onToggle())
          : ComicCover(url: comic.coverUrl, width: 56, height: 78),
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
      onTap: selecting ? onToggle : () => _open(context, comic),
      onLongPress: selecting ? onToggle : onLongPress,
    );
  }
}

/// 网格多选时右上角的圆形选中角标。
class _SelectBadge extends StatelessWidget {
  final bool selected;
  const _SelectBadge({required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : Colors.white,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 15, color: scheme.onPrimary)
          : null,
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

/// 下载章节选择弹窗：可全选 / 单选后批量下载。
class _ChapterPickerSheet extends StatefulWidget {
  final List<Chapter> chapters;
  final String comicName;

  const _ChapterPickerSheet({required this.chapters, required this.comicName});

  @override
  State<_ChapterPickerSheet> createState() => _ChapterPickerSheetState();
}

class _ChapterPickerSheetState extends State<_ChapterPickerSheet> {
  final Set<int> _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == widget.chapters.length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '下载 · ${widget.comicName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(List.generate(
                              widget.chapters.length, (i) => i));
                      }
                    }),
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.chapters.length,
                itemBuilder: (_, i) {
                  final checked = _selected.contains(i);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (_) => setState(() {
                      if (checked) {
                        _selected.remove(i);
                      } else {
                        _selected.add(i);
                      }
                    }),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      widget.chapters[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () {
                          final list = (_selected.toList()..sort())
                              .map((i) => widget.chapters[i])
                              .toList();
                          Navigator.pop(context, list);
                        },
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_selected.isEmpty
                      ? '请选择要下载的章节'
                      : '下载 ${_selected.length} 个章节'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _open(BuildContext context, Comic comic) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: comic)),
  );
}

/// 选择目标文件夹（含「全部」「新建文件夹」）。
///
/// [current] 为 null 时不标注任何「当前」项（批量移动时使用）。
Future<String?> _pickFolder(
  BuildContext context,
  List<String> folders, {
  required String? current,
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
              title: Text('全部${current == '' ? '  · 当前' : ''}'),
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
