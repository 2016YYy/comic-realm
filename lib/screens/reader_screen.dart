import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/state_views.dart';

/// 阅读器：竖向连续滚动（条漫）或横向翻页，均支持上一话 / 下一话切换。
class ReaderScreen extends StatefulWidget {
  final ComicSource source;
  final Comic comic;
  final List<Chapter> chapters;
  final int initialIndex;

  const ReaderScreen({
    super.key,
    required this.source,
    required this.comic,
    required this.chapters,
    required this.initialIndex,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _currentIndex;
  List<String> _images = [];
  String _text = '';
  bool _loading = true;
  String? _error;
  bool _chromeVisible = true;

  bool get _isNovel => widget.source.isNovel;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    setState(() {
      _loading = true;
      _error = null;
      _images = [];
      _text = '';
    });
    final comicService = context.read<ComicService>();
    final chapter = widget.chapters[_currentIndex];
    try {
      if (_isNovel) {
        final text = await comicService.getContentText(widget.source, chapter, widget.comic);
        if (!mounted) return;
        setState(() {
          _text = text;
          _loading = false;
        });
      } else {
        final images = await comicService.getContent(widget.source, chapter, widget.comic);
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
        _error = e.toString();
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
    if (_currentIndex < widget.chapters.length - 1) {
      setState(() => _currentIndex++);
      _loadChapter();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapters[_currentIndex];
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
                    chapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    '${_currentIndex + 1} / ${widget.chapters.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _currentIndex > 0 ? _prev : null,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _currentIndex < widget.chapters.length - 1 ? _next : null,
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: _buildBody(continuous),
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

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.fitWidth,
      width: double.infinity,
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
