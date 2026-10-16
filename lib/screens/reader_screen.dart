import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';

/// 阅读器：竖向连续滚动（条漫）或横向翻页，均支持上一话 / 下一话切换。
class ReaderScreen extends StatefulWidget {
  final ComicSource? source;
  final Comic comic;
  final List<Chapter>? chapters;
  final int initialIndex;

  /// 离线模式：直接传入已下载的本地内容，不走 source engine。
  final List<String>? offlineImages;
  final String? offlineText;

  const ReaderScreen({
    super.key,
    this.source,
    required this.comic,
    this.chapters,
    this.initialIndex = 0,
    this.offlineImages,
    this.offlineText,
  });

  /// 离线模式快捷构造
  factory ReaderScreen.offline({
    required Comic comic,
    List<String>? images,
    String? text,
    List<Chapter>? chapters,
    int initialIndex = 0,
  }) {
    return ReaderScreen(
      comic: comic,
      chapters: chapters,
      initialIndex: initialIndex,
      offlineImages: images,
      offlineText: text,
    );
  }

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _currentIndex;
  List<String> _images = [];
  String _text = '';
  bool _loading = true;
  String? _error;
  bool _chromeVisible = false; // 默认沉浸式，点击中间区域才显示菜单

  bool get _isNovel {
    if (widget.source != null) return widget.source!.isNovel;
    return widget.offlineText != null;
  }

  bool get _isOffline {
    return widget.offlineImages != null || widget.offlineText != null;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // 沉浸式：隐藏状态栏与导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_isOffline) {
      _images = widget.offlineImages ?? [];
      _text = widget.offlineText ?? '';
      _loading = false;
    } else {
      _loadChapter();
    }
  }

  @override
  void dispose() {
    // 退出阅读器时恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<void> _loadChapter() async {
    final source = widget.source;
    final chapters = widget.chapters;
    if (source == null || chapters == null || chapters.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _images = [];
      _text = '';
    });
    final comicService = context.read<ComicService>();
    final chapter = chapters[_currentIndex];
    try {
      if (_isNovel) {
        final text = await comicService.getContentText(source, chapter, widget.comic);
        if (!mounted) return;
        setState(() {
          _text = text;
          _loading = false;
        });
      } else {
        final images = await comicService.getContent(source, chapter, widget.comic);
        if (!mounted) return;
        setState(() {
          _images = images;
          _loading = false;
        });
      }
      // 记录阅读历史
      context.read<HistoryService>().record(
            comic: widget.comic,
            chapterName: chapter.name,
            chapterIndex: _currentIndex,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ComicService.friendlyError(e);
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _loadChapter();
    }
  }

  void _next() {
    final count = widget.chapters?.length ?? 0;
    if (_currentIndex < count - 1) {
      setState(() => _currentIndex++);
      _loadChapter();
    }
  }

  /// 阅读设置底部弹窗：阅读模式 + 字号（小说）
  Future<void> _showReaderSettings() async {
    final settings = context.read<SettingsService>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('阅读设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              const Text('阅读模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: settings,
                builder: (_, __) => SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('连续滚动'), icon: Icon(Icons.view_agenda_outlined)),
                    ButtonSegment(value: false, label: Text('横向翻页'), icon: Icon(Icons.swipe_outlined)),
                  ],
                  selected: {settings.readerContinuous},
                  onSelectionChanged: (v) => settings.readerContinuous = v.first,
                ),
              ),
              if (_isNovel) ...[
                const SizedBox(height: 20),
                ListenableBuilder(
                  listenable: settings,
                  builder: (_, __) => Row(
                    children: [
                      const Icon(Icons.text_fields, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          min: 12,
                          max: 28,
                          divisions: 16,
                          value: settings.readerFontSize,
                          label: '${settings.readerFontSize.round()}',
                          onChanged: (v) => settings.readerFontSize = v,
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('${settings.readerFontSize.round()}',
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// 章节目录弹窗：快速跳转到指定章节。
  Future<void> _showChapterList() async {
    final chapters = widget.chapters;
    if (chapters == null || chapters.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChapterListSheet(
        chapters: chapters,
        currentIndex: _currentIndex,
      ),
    );
    if (selected == null || !mounted || selected == _currentIndex) return;
    setState(() => _currentIndex = selected);
    _loadChapter();
  }

  @override
  Widget build(BuildContext context) {
    final chapterCount = widget.chapters?.length ?? 0;
    final chapterName = widget.chapters != null && _currentIndex < chapterCount
        ? widget.chapters![_currentIndex].name
        : widget.comic.name;
    final continuous = context.watch<SettingsService>().readerContinuous;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapterName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  if (chapterCount > 0)
                    Text(
                      '${_currentIndex + 1} / $chapterCount${_isOffline ? ' · 离线' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                ],
              ),
              actions: [
                if (!_isOffline && chapterCount > 0) ...[
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: _currentIndex > 0 ? _prev : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: _currentIndex < chapterCount - 1 ? _next : null,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '阅读设置',
                  onPressed: _showReaderSettings,
                ),
              ],
            )
          : null,
      bottomNavigationBar: _chromeVisible ? _buildBottomBar() : null,
      body: Stack(
        children: [
          _buildBody(continuous),
          // 点击分区：左侧上一话，中间切换菜单，右侧下一话
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (!_isOffline && _currentIndex > 0) _prev();
                    },
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      final count = widget.chapters?.length ?? 0;
                      if (!_isOffline && _currentIndex < count - 1) _next();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏：上一话 / 目录 / 下一话（与顶部菜单一同显示）。
  Widget _buildBottomBar() {
    final chapterCount = widget.chapters?.length ?? 0;
    final style = TextButton.styleFrom(foregroundColor: Colors.white);
    return Material(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed:
                      (!_isOffline && _currentIndex > 0) ? _prev : null,
                  icon: const Icon(Icons.skip_previous, size: 20),
                  label: const Text('上一话'),
                  style: style,
                ),
              ),
              if (chapterCount > 0 && !_isOffline)
                TextButton.icon(
                  onPressed: _showChapterList,
                  icon: const Icon(Icons.menu_book_outlined, size: 20),
                  label: Text('目录 ${_currentIndex + 1}/$chapterCount'),
                  style: style,
                ),
              Expanded(
                child: TextButton.icon(
                  onPressed: (!_isOffline && _currentIndex < chapterCount - 1)
                      ? _next
                      : null,
                  icon: const Icon(Icons.skip_next, size: 20),
                  label: const Text('下一话'),
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool continuous) {
    if (_loading) return const LoadingView(label: '正在加载本章…');
    if (_error != null) {
      return ErrorView(message: '本章加载失败', detail: _error, onRetry: _loadChapter);
    }

    if (_isNovel) {
      if (_text.trim().isEmpty) {
        return const EmptyView(icon: Icons.article_outlined, title: '本章没有内容');
      }
      return _buildNovelText();
    }

    if (_images.isEmpty) {
      return const EmptyView(icon: Icons.image_not_supported_outlined, title: '本章没有图片');
    }

    if (continuous) {
      return ListView.builder(
        itemCount: _images.length,
        itemBuilder: (_, i) => _ReaderImage(url: _images[i]),
      );
    }

    return PageView.builder(
      itemCount: _images.length,
      itemBuilder: (_, i) => InteractiveViewer(
        maxScale: 4,
        child: Center(child: _ReaderImage(url: _images[i])),
      ),
    );
  }

  Widget _buildNovelText() {
    final settings = context.watch<SettingsService>();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      children: [
        Text(
          _text,
          style: TextStyle(
            fontSize: settings.readerFontSize.toDouble(),
            height: 1.8,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ReaderImage extends StatelessWidget {
  final String url;

  const _ReaderImage({required this.url});

  bool get _isLocal => File(url).existsSync();

  @override
  Widget build(BuildContext context) {
    if (_isLocal) {
      return Image.file(
        File(url),
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 320,
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      // 与封面一致：按图片域名补同源 Referer，绕过常见防盗链。
      httpHeaders: ComicCover.imageHeaders(url),
      placeholder: (_, __) => const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (_, __, ___) => const SizedBox(
        height: 320,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
        ),
      ),
    );
  }
}

/// 章节目录弹窗：列出全部章节，点击跳转。
class _ChapterListSheet extends StatelessWidget {
  final List<Chapter> chapters;
  final int currentIndex;

  const _ChapterListSheet({
    required this.chapters,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView.builder(
          itemCount: chapters.length,
          itemBuilder: (_, i) {
            final active = i == currentIndex;
            return ListTile(
              selected: active,
              leading: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              title: Text(
                chapters[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: active
                  ? Icon(Icons.play_arrow, color: scheme.primary, size: 20)
                  : null,
              onTap: () => Navigator.pop(context, i),
            );
          },
        ),
      ),
    );
  }
}
