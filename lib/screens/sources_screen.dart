import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/source_service.dart';
import '../models/source.dart';
import '../widgets/glass.dart';
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

  /// 类型筛选：'' = 全部，其余为「漫画 / 小说 / 视频」
  String _typeFilter = '';

  @override
  Widget build(BuildContext context) {
    final sourceService = context.watch<SourceService>();
    final allSources = sourceService.allSources;
    final scheme = Theme.of(context).colorScheme;

    final counts = <String, int>{'': allSources.length};
    for (final s in allSources) {
      final label = s.kindLabel;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final sources = _typeFilter.isEmpty
        ? allSources
        : allSources.where((s) => s.kindLabel == _typeFilter).toList();
    // 只有「全部」视图允许拖拽排序：筛选后重排会把未显示的图源顺序打乱。
    final canReorder = _typeFilter.isEmpty && sources.length > 1;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('图源管理'),
        actions: [
          if (allSources.isNotEmpty)
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
          if (allSources.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: '导出全部图源',
              onPressed: () => _exportSources(context, allSources),
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
      body: allSources.isEmpty
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
          : Column(
              children: [
                // 类型筛选条：全部 / 漫画 / 小说 / 视频
                _TypeFilterBar(
                  selected: _typeFilter,
                  counts: counts,
                  onSelected: (t) => setState(() => _typeFilter = t),
                ),
                if (canReorder)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Icon(Icons.drag_indicator,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '长按拖动可调整图源顺序（越靠前搜索越优先）',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: sources.isEmpty
                      ? const EmptyView(
                          icon: Icons.filter_alt_off_outlined,
                          title: '该类型下暂无图源',
                          subtitle: '切换到「全部」查看所有图源',
                        )
                      : canReorder
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.only(top: 4, bottom: 24),
                              itemCount: sources.length,
                              buildDefaultDragHandles: false,
                              onReorder: (oldIndex, newIndex) =>
                                  _onReorder(context, allSources, oldIndex, newIndex),
                              itemBuilder: (context, index) {
                                final source = sources[index];
                                return _SourceTile(
                                  key: ValueKey(source.bookSourceUrl),
                                  source: source,
                                  index: index,
                                  dragHandleIndex: index,
                                  showDragHandle: true,
                                  onTap: () => _openDiscover(context, source),
                                  onToggle: () => sourceService.toggleSource(source),
                                  onMenu: (v) => _onMenuSelected(context, v, source),
                                );
                              },
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(top: 4, bottom: 24),
                              itemCount: sources.length,
                              itemBuilder: (context, index) {
                                final source = sources[index];
                                return _SourceTile(
                                  key: ValueKey(source.bookSourceUrl),
                                  source: source,
                                  index: index,
                                  showDragHandle: false,
                                  onTap: () => _openDiscover(context, source),
                                  onToggle: () => sourceService.toggleSource(source),
                                  onMenu: (v) => _onMenuSelected(context, v, source),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }

  void _openDiscover(BuildContext context, ComicSource source) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SourceDiscoverScreen(source: source)),
    );
  }

  /// 拖拽排序：把新顺序写回 weight，使搜索 / 发现页同步生效。
  void _onReorder(BuildContext context, List<ComicSource> allSources,
      int oldIndex, int newIndex) {
    // ReorderableListView 的 newIndex 是「插入位置」，向下移动时需要减一
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final list = List<ComicSource>.from(allSources);
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    context.read<SourceService>().reorderSources(list);
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

/// 单个图源条目：类型徽标 + 名称 + 地址 / 分类数 + 启用开关 + 更多菜单。
class _SourceTile extends StatelessWidget {
  final ComicSource source;
  final int index;

  /// 拖拽手柄使用的索引（ReorderableListView 要求）
  final int? dragHandleIndex;
  final bool showDragHandle;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final ValueChanged<String> onMenu;

  const _SourceTile({
    super.key,
    required this.source,
    required this.index,
    this.dragHandleIndex,
    required this.showDragHandle,
    required this.onTap,
    required this.onToggle,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = source.enable ? scheme.primary : scheme.onSurfaceVariant;
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _kindColor(source.kind, scheme).withValues(alpha: 0.15),
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
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      isThreeLine: source.findCategories.isNotEmpty,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: source.enable,
            onChanged: (_) => onToggle(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: onMenu,
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
          if (showDragHandle && dragHandleIndex != null)
            ReorderableDragStartListener(
              index: dragHandleIndex!,
              child: const Padding(
                padding: EdgeInsets.only(left: 2, right: 4),
                child: Icon(Icons.drag_handle, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(ComicSource source) {
    final cats = source.findCategories;
    if (cats.isEmpty) return source.bookSourceUrl;
    return '${source.bookSourceUrl}\n${cats.length} 个分类 · 点击浏览';
  }
}

/// 图源类型筛选条：全部 / 漫画 / 小说 / 视频，带数量统计。
class _TypeFilterBar extends StatelessWidget {
  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  const _TypeFilterBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  static const _tabs = <String, (IconData, String)>{
    '': (Icons.apps, '全部'),
    '漫画': (Icons.image_outlined, '漫画'),
    '小说': (Icons.auto_stories_outlined, '小说'),
    '视频': (Icons.smart_display_outlined, '视频'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: _tabs.entries.map((e) {
          final active = selected == e.key;
          final count = counts[e.key] ?? 0;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelected(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primaryContainer.withValues(alpha: 0.7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(e.value.$1,
                        size: 15,
                        color: active ? scheme.primary : scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${e.value.$2}$count',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color:
                              active ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
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
