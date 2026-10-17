import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/source_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';
import 'reader_screen.dart';
import 'search_screen.dart';
import 'source_discover_screen.dart';

class ComicDetailScreen extends StatefulWidget {
  final Comic comic;
  const ComicDetailScreen({super.key, required this.comic});

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  List<Chapter> _chapters = [];
  bool _loading = true;
  bool _favorited = false;
  String? _error;
  ComicSource? _source;
  late Comic _comic;

  /// 批量下载进行中的状态（null 表示空闲）
  bool _batchDownloading = false;
  int _batchDone = 0;
  int _batchTotal = 0;

  @override
  void initState() {
    super.initState();
    _comic = widget.comic;
    _favorited = context.read<ComicService>().isFavoriteComic(_comic);
    _source = _resolveSource();
    if (_source == null) {
      _loading = false;
    } else {
      _load();
    }
  }

  ComicSource? _resolveSource() {
    final sources = context.read<SourceService>().allSources;
    if (sources.isEmpty) return null;
    for (final s in sources) {
      if (s.bookSourceUrl == _comic.sourceUrl) return s;
    }
    return null;
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final comicService = context.read<ComicService>();
    try {
      await comicService.getDetail(source, _comic);
      final chapters = await comicService.getChapters(source, _comic);
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ComicService.friendlyError(e);
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final comicService = context.read<ComicService>();
    if (_favorited) {
      await comicService.removeFavorite(_comic);
    } else {
      await comicService.addFavorite(_comic);
    }
    if (mounted) setState(() => _favorited = !_favorited);
  }

  Future<void> _openChapter(int index) async {
    final source = _source;
    if (source == null) return;
    // 视频源：不走图片阅读器，直接解析出播放地址交给系统播放器 / 浏览器
    if (source.isVideo) {
      await _playVideo(source, _chapters[index]);
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          source: source,
          comic: _comic,
          chapters: _chapters,
          initialIndex: index,
        ),
      ),
    );
  }

  /// 解析视频源章节的播放地址并用外部应用打开。
  ///
  /// 优先尝试系统能直接处理的 mp4 / m3u8 地址；解析不到时退化为
  /// 在浏览器里打开章节页，让站点自己的播放器接管。
  Future<void> _playVideo(ComicSource source, Chapter chapter) async {
    final comicService = context.read<ComicService>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text('正在解析播放地址…'),
          ],
        ),
      ),
    );
    try {
      final urls =
          await comicService.getVideoUrls(source, chapter, _comic);
      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading
      final target = urls.isNotEmpty ? urls.first : chapter.url;
      final ok = await launchUrl(
        Uri.parse(target),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!ok) {
        showToast(context, '无法调起播放器，请复制地址后手动打开', isError: true);
      } else if (urls.isEmpty) {
        showToast(context, '未解析到直链，已在浏览器打开章节页',
            icon: Icons.open_in_new);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, ComicService.friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_comic.name),
        actions: [
          IconButton(
            icon: Icon(_favorited ? Icons.favorite : Icons.favorite_border),
            tooltip: _favorited ? '取消收藏' : '加入书架',
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _source == null ? () async {} : _load,
        child: ListView(
          children: [
            _buildHeader(),
            const Divider(height: 1),
            _buildContinueButton(),
            if (_source == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyView(
                  icon: Icons.link_off,
                  title: '未找到对应图源',
                  subtitle: '该漫画来源的图源可能已被删除，无法加载章节列表。\n可前往「图源」重新导入后重试。',
                ),
              )
            else if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: LoadingView(
                  label: (_source?.isNovel ?? false) ? '正在加载书源…' : '正在加载章节…',
                ),
              )
            else if (_error != null)
              ErrorView(message: '章节加载失败', detail: _error, onRetry: _load)
            else if (_chapters.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyView(icon: Icons.list_alt, title: '没有找到章节'),
              )
            else
              ..._buildChapterList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: _comic.heroTag,
            child: ComicCover(url: _comic.coverUrl, width: 108, height: 150),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _comic.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                if (_comic.author.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        '作者：',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                      ..._comic.author.split(RegExp(r'[,，/、\s]+')).where((a) => a.isNotEmpty).map(
                            (a) => _buildTagChip(a, scheme, isAuthor: true),
                          ),
                    ],
                  ),
                if (_comic.kind.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        '分类：',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                      ..._comic.kind.split(RegExp(r'[,，/、\s]+')).where((k) => k.isNotEmpty).map(
                            (k) => _buildTagChip(k, scheme),
                          ),
                    ],
                  ),
                ],
                if (_comic.sourceName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SourceBadge(label: _comic.sourceName),
                ],
                const SizedBox(height: 10),
                if (_comic.introduce.isNotEmpty)
                  Text(
                    _comic.introduce,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 可点击的标签/作者胶囊
  /// - 分类：在当前图源内浏览该分类（不是搜索）
  /// - 作者：跨已启用图源搜索该作者
  Widget _buildTagChip(String text, ColorScheme scheme, {bool isAuthor = false}) {
    return InkWell(
      onTap: () {
        if (isAuthor) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SearchScreen(initialQuery: text)),
          );
          return;
        }
        final source = _source;
        if (source == null) {
          showToast(context, '未找到对应图源，无法浏览分类');
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SourceDiscoverScreen(source: source, initialCategory: text),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    final entry = context.watch<HistoryService>().entryFor(_comic.noteUrl);
    if (entry == null || _chapters.isEmpty) return const SizedBox.shrink();
    final index = entry.chapterIndex.clamp(0, _chapters.length - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: FilledButton.icon(
        onPressed: () => _openChapter(index),
        icon: const Icon(Icons.play_arrow),
        label: Text(
          entry.chapterName.isEmpty ? '继续阅读' : '继续阅读：${entry.chapterName}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  List<Widget> _buildChapterList() {
    final scheme = Theme.of(context).colorScheme;
    final downloadService = context.watch<DownloadService>();
    final source = _source;
    return [
      SectionHeader(
        title: '章节（${_chapters.length}）',
        trailing: _buildBatchDownloadButton(scheme),
      ),
      if (_batchDownloading)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _batchTotal > 0 ? _batchDone / _batchTotal : null,
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 4),
              Text('正在批量下载 $_batchDone / $_batchTotal',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ..._chapters.asMap().entries.map((e) {
        final chapter = e.value;
        final downloaded = source != null &&
            downloadService.isChapterDownloaded(source, chapter);
        return ListTile(
          leading: Text(
            '${e.key + 1}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          title: Text(chapter.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: downloaded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.offline_bolt, size: 12, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text('已下载',
                        style: TextStyle(fontSize: 11, color: scheme.primary)),
                  ],
                )
              : null,
          trailing: downloaded
              ? Icon(Icons.check_circle, size: 20, color: scheme.primary)
              : IconButton(
                  icon: const Icon(Icons.download_outlined, size: 20),
                  tooltip: '下载本话',
                  onPressed: _batchDownloading
                      ? null
                      : () => _downloadChapter(chapter),
                ),
          onTap: () => _openChapter(e.key),
        );
      }),
      const SizedBox(height: 24),
    ];
  }

  /// 批量下载入口按钮（视频源不支持离线缓存，隐藏）
  Widget _buildBatchDownloadButton(ColorScheme scheme) {
    if (_source == null || _source!.isVideo) return const SizedBox.shrink();
    if (_batchDownloading) {
      return TextButton(
        onPressed: null,
        child: Text('$_batchDone/$_batchTotal',
            style: const TextStyle(fontSize: 12)),
      );
    }
    return TextButton.icon(
      onPressed: _pickChaptersAndDownload,
      icon: const Icon(Icons.download_for_offline_outlined, size: 18),
      label: const Text('批量下载', style: TextStyle(fontSize: 12)),
    );
  }

  /// 弹出章节多选，确认后顺序下载（跳过已完成的章节）。
  Future<void> _pickChaptersAndDownload() async {
    final source = _source;
    if (source == null || _chapters.isEmpty) return;
    final downloadService = context.read<DownloadService>();
    final pending = _chapters
        .where((c) => !downloadService.isChapterDownloaded(source, c))
        .toList();
    if (pending.isEmpty) {
      showToast(context, '全部章节都已下载',
          icon: Icons.check_circle_outline);
      return;
    }
    final selected = await showModalBottomSheet<List<Chapter>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChapterPickerSheet(
        chapters: pending,
        comicName: _comic.name,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _batchDownload(source, selected);
  }

  Future<void> _batchDownload(
      ComicSource source, List<Chapter> chapters) async {
    final downloadService = context.read<DownloadService>();
    setState(() {
      _batchDownloading = true;
      _batchDone = 0;
      _batchTotal = chapters.length;
    });
    var failed = 0;
    for (final chapter in chapters) {
      try {
        await downloadService.downloadChapter(
            source: source, comic: _comic, chapter: chapter);
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
      setState(() => _batchDone++);
    }
    if (!mounted) return;
    setState(() => _batchDownloading = false);
    showToast(
      context,
      failed == 0
          ? '批量下载完成：${chapters.length} 个章节'
          : '下载完成：成功 ${chapters.length - failed} 个，失败 $failed 个',
      icon: failed == 0 ? Icons.check_circle_outline : Icons.error_outline,
      isError: failed > 0,
    );
  }

  Future<void> _downloadChapter(Chapter chapter) async {
    final source = _source;
    if (source == null) return;
    final downloadService = context.read<DownloadService>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('开始下载：${chapter.name}')),
    );
    await downloadService.downloadChapter(source: source, comic: _comic, chapter: chapter);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成，可在「下载」页查看')),
      );
    }
  }
}

/// 章节多选弹窗：可全选 / 反选，确认后返回选中的章节列表。
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
    final allSelected =
        widget.chapters.isNotEmpty && _selected.length == widget.chapters.length;
    final scheme = Theme.of(context).colorScheme;
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
            Divider(height: 1, color: scheme.outlineVariant),
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
            Divider(height: 1, color: scheme.outlineVariant),
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
