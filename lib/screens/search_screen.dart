import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/database.dart';
import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import 'comic_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Comic> _results = [];
  List<SourceError> _errors = [];
  bool _loading = false;
  bool _searched = false;
  String? _sourceFilter; // null = 全部图源

  List<ComicSource> get _enabledSources =>
      AppDatabase.sources.values.where((s) => s.enable).toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _loading = true;
      _results = [];
      _errors = [];
      _searched = true;
    });
    final service = context.read<ComicService>();
    try {
      if (_sourceFilter == null) {
        final outcome = await service.searchAllWithErrors(keyword);
        if (!mounted) return;
        setState(() {
          _results = outcome.comics;
          _errors = outcome.errors;
          _loading = false;
        });
      } else {
        final source = _enabledSources.firstWhere(
          (s) => s.bookSourceUrl == _sourceFilter,
          orElse: () => _enabledSources.first,
        );
        final list = await service.searchBySource(source, keyword);
        if (!mounted) return;
        setState(() {
          _results = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [SourceError('搜索', e.toString())];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = _enabledSources;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索漫画…',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: Column(
        children: [
          if (sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Text('图源：', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _sourceFilter,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部图源', style: TextStyle(fontSize: 13)),
                          ),
                          ...sources.map((s) => DropdownMenuItem<String?>(
                                value: s.bookSourceUrl,
                                child: Text(s.bookSourceName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                              )),
                        ],
                        onChanged: (v) => setState(() => _sourceFilter = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_searched && !_loading)
            _buildStatusBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('共 ${_results.length} 条结果', style: const TextStyle(fontSize: 12)),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline, color: Colors.orange, size: 18),
                title: Text('${_errors.length} 个图源失败（点击查看原因）',
                    style: const TextStyle(fontSize: 12, color: Colors.orange)),
                children: _errors
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('· ${e.sourceName}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              Text('  ${e.message}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_searched) {
      return Center(
        child: Text('输入关键词后点击搜索', style: TextStyle(color: Colors.grey[500])),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text('暂无结果', style: TextStyle(color: Colors.grey[500])),
            if (_errors.isNotEmpty)
              Text('已启用图源均搜索失败，请展开上方查看原因',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final comic = _results[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 50,
              height: 70,
              child: comic.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: comic.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
                    )
                  : Container(color: Colors.grey[800]),
            ),
          ),
          title: Text(comic.name),
          subtitle: Text('${comic.author} · ${comic.sourceName}'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: comic)),
            );
          },
        );
      },
    );
  }
}
