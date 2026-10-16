import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/database.dart';
import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/state_views.dart';
import 'comic_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

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

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('共 ${_results.length} 条结果',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: Icon(Icons.error_outline, color: scheme.error, size: 18),
                title: Text('${_errors.length} 个图源失败（点击查看原因）',
                    style: TextStyle(fontSize: 12, color: scheme.error)),
                children: _errors
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('· ${e.sourceName}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onSurface)),
                              Text('  ${e.message}',
                                  style: TextStyle(
                                      fontSize: 11, color: scheme.onSurfaceVariant)),
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
    if (_loading) return const LoadingView(label: '正在搜索…');
    if (!_searched) {
      return const EmptyView(
        icon: Icons.search,
        title: '搜索漫画',
        subtitle: '输入关键词后点击搜索，将同时查询所有已启用图源',
      );
    }
    if (_results.isEmpty) {
      return EmptyView(
        icon: Icons.search_off,
        title: '暂无结果',
        subtitle: _errors.isNotEmpty ? '已启用图源均搜索失败，请展开上方查看原因' : '换个关键词再试试',
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final comic = _results[index];
        final isFav = context.watch<ComicService>().isFavoriteComic(comic);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: ComicCover(url: comic.coverUrl, width: 50, height: 70, radius: 6),
          title: Text(comic.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            comic.author.isEmpty ? comic.sourceName : '${comic.author} · ${comic.sourceName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: isFav ? '取消收藏' : '加入书架',
            onPressed: () {
              final service = context.read<ComicService>();
              if (isFav) {
                service.removeFavorite(comic);
                showToast(context, '已从书架移除');
              } else {
                service.addFavorite(comic);
                showToast(context, '已加入书架', icon: Icons.favorite);
              }
            },
          ),
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
