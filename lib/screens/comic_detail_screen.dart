import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/source_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';
import 'reader_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _comic = widget.comic;
    _favorited = context.read<ComicService>().isFavorite(_comic.noteUrl);
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

  void _openChapter(int index) {
    final source = _source;
    if (source == null) return;
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: LoadingView(label: '正在加载章节…'),
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
            tag: 'cover-${_comic.noteUrl}',
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
                  Text(
                    '作者：${_comic.author}',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                if (_comic.kind.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '类型：${_comic.kind}',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
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
    return [
      SectionHeader(title: '章节（${_chapters.length}）'),
      ..._chapters.asMap().entries.map((e) {
        final chapter = e.value;
        return ListTile(
          leading: Text(
            '${e.key + 1}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          title: Text(chapter.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined, size: 20),
            tooltip: '下载本话',
            onPressed: () => _downloadChapter(chapter),
          ),
          onTap: () => _openChapter(e.key),
        );
      }),
      const SizedBox(height: 24),
    ];
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
