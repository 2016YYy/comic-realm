import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/download_service.dart';
import '../services/source_service.dart';
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
  late ComicSource _source;
  late Comic _comic;

  @override
  void initState() {
    super.initState();
    _comic = widget.comic;
    _favorited = context.read<ComicService>().isFavorite(_comic.noteUrl);
    // 找到对应的图源
    final sources = context.read<SourceService>().allSources;
    _source = sources.firstWhere(
      (s) => s.bookSourceUrl == _comic.sourceUrl,
      orElse: () => sources.first,
    );
    _load();
  }

  Future<void> _load() async {
    final comicService = context.read<ComicService>();
    try {
      await comicService.getDetail(_source, _comic);
      final chapters = await comicService.getChapters(_source, _comic);
      if (mounted) {
        setState(() {
          _chapters = chapters;
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

  Future<void> _toggleFavorite() async {
    final comicService = context.read<ComicService>();
    if (_favorited) {
      await comicService.removeFavorite(_comic);
    } else {
      await comicService.addFavorite(_comic);
    }
    setState(() => _favorited = !_favorited);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_comic.name),
        actions: [
          IconButton(
            icon: Icon(_favorited ? Icons.favorite : Icons.favorite_border),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                const Divider(),
                Expanded(child: _buildChapterList()),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 100,
              height: 140,
              child: _comic.coverUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: _comic.coverUrl, fit: BoxFit.cover)
                  : Container(color: Colors.grey[800]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_comic.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('作者：${_comic.author}', style: TextStyle(color: Colors.grey[400])),
                if (_comic.kind.isNotEmpty) Text('类型：${_comic.kind}', style: TextStyle(color: Colors.grey[400])),
                const SizedBox(height: 8),
                if (_comic.introduce.isNotEmpty)
                  Text(_comic.introduce, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterList() {
    return ListView.builder(
      itemCount: _chapters.length,
      itemBuilder: (context, index) {
        final chapter = _chapters[index];
        return ListTile(
          title: Text(chapter.name),
          trailing: IconButton(
            icon: const Icon(Icons.download, size: 20),
            tooltip: '下载该话',
            onPressed: () => _downloadChapter(chapter),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReaderScreen(
                  source: _source,
                  comic: _comic,
                  chapters: _chapters,
                  initialIndex: index,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadChapter(Chapter chapter) async {
    final downloadService = context.read<DownloadService>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('开始下载：${chapter.name}')),
    );
    await downloadService.downloadChapter(source: _source, comic: _comic, chapter: chapter);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载完成')),
      );
    }
  }
}
