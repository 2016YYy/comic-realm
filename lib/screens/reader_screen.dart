import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import 'package:provider/provider.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadChapter();
  }

  Future<void> _loadChapter() async {
    setState(() => _loading = true);
    final comicService = context.read<ComicService>();
    try {
      final chapter = widget.chapters[_currentIndex];
      final images = await comicService.getContent(widget.source, chapter, widget.comic);
      if (mounted) {
        setState(() {
          _images = images;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(chapter.name, style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.skip_previous), onPressed: _currentIndex > 0 ? _prev : null),
          IconButton(icon: const Icon(Icons.skip_next), onPressed: _currentIndex < widget.chapters.length - 1 ? _next : null),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? const Center(child: Text('没有图片'))
              : ListView.builder(
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    return CachedNetworkImage(
                      imageUrl: _images[index],
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      placeholder: (_, __) => Container(height: 300, color: Colors.grey[900], child: const Center(child: CircularProgressIndicator())),
                      errorWidget: (_, __, ___) => Container(height: 300, color: Colors.grey[900], child: const Icon(Icons.broken_image)),
                    );
                  },
                ),
    );
  }
}
