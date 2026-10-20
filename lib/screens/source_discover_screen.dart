import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/glass.dart';
import '../widgets/state_views.dart';
import 'comic_detail_screen.dart';

/// 图源「分类 / 发现」页：展示该图源的分类，浏览、收藏、阅读漫画。
class SourceDiscoverScreen extends StatefulWidget {
  final ComicSource source;

  /// 可选：进入时默认选中的分类标题（用于从详情页点击分类跳转）
  final String? initialCategory;

  const SourceDiscoverScreen({super.key, required this.source, this.initialCategory});

  @override
  State<SourceDiscoverScreen> createState() => _SourceDiscoverScreenState();
}

class _SourceDiscoverScreenState extends State<SourceDiscoverScreen> {
  final List<FindCategory> _categories = [];
  FindCategory? _selected;
  List<Comic> _comics = [];
  bool _loading = false;
  int _page = 1;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _categories.addAll(widget.source.findCategories);
    // 图源未配置分类（ruleFindUrl / exploreUrl）时，用图源首页兜底，
    // 避免直接提示「该图源未配置分类」而完全无法浏览。
    if (_categories.isEmpty && widget.source.bookSourceUrl.isNotEmpty) {
      _categories.add(FindCategory('首页', widget.source.bookSourceUrl));
    }
    if (_categories.isNotEmpty) {
      // 优先使用传入的初始分类，找不到则回退到第一个
      final initTitle = widget.initialCategory;
      if (initTitle != null) {
        _selected = _categories.firstWhere(
          (c) => c.title == initTitle,
          orElse: () => _categories.first,
        );
      } else {
        _selected = _categories.first;
      }
      _load(reset: true);
    }
    // 滚动接近底部时自动加载更多
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final category = _selected;
    if (category == null) return;
    final service = context.read<ComicService>();
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
        _comics = [];
        _page = 1;
        _hasMore = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final list = await service.categoryComics(widget.source, category.url, page: _page);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _comics = list;
        } else {
          _comics = [..._comics, ...list];
        }
        _loading = false;
        _loadingMore = false;
        _hasMore = list.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
        if (!reset) _hasMore = false;
      });
    }
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore) return;
    _page += 1;
    _load(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(widget.source.bookSourceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '在图源内搜索',
            onPressed: () => _showSearchDialog(),
          ),
        ],
        bottom: _categories.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final c = _categories[index];
                      final selected = c == _selected;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: ChoiceChip(
                          label: Text(c.title),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selected = c);
                            _load(reset: true);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
      ),
      body: _categories.isEmpty ? _buildNoCategories() : _buildContent(),
    );
  }

  Widget _buildNoCategories() {
    return EmptyView(
      icon: Icons.category_outlined,
      title: '该图源未配置分类',
      subtitle: '可使用右上角搜索，或导入带有 ruleFindUrl 的图源',
      action: FilledButton.icon(
        icon: const Icon(Icons.search),
        label: const Text('搜索漫画'),
        onPressed: () => _showSearchDialog(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const LoadingView(label: '正在加载漫画…');
    if (_error != null && _comics.isEmpty) {
      return ErrorView(message: '加载失败', detail: _error, onRetry: () => _load(reset: true));
    }
    if (_comics.isEmpty) {
      return const EmptyView(icon: Icons.image_search, title: '该分类暂无漫画');
    }
    // 收藏状态整个网格只订阅一次，避免每个 _ComicTile 各自 watch 造成
    // 任何一处收藏变化都重建整页。
    final favKeys = context.watch<ComicService>().favoriteKeys;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        // 预渲染视口外一段，减少快速滑动时的白块。
        cacheExtent: 500,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.62,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
        ),
        itemCount: _comics.length + 1,
        itemBuilder: (context, index) {
          if (index == _comics.length) {
            return _buildLoadMore();
          }
          final comic = _comics[index];
          return _ComicTile(
            comic: comic,
            favorited: favKeys.contains(comic.uniqueKey),
          );
        },
      ),
    );
  }

  Widget _buildLoadMore() {
    return Center(
      child: _loadingMore
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _hasMore
              ? TextButton(onPressed: _loadMore, child: const Text('加载更多'))
              : Text('没有更多了',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
    );
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('在「${widget.source.bookSourceName}」中搜索'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入关键词'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (keyword == null || keyword.trim().isEmpty || !mounted) return;
    _doSourceSearch(keyword.trim());
  }

  Future<void> _doSourceSearch(String keyword) async {
    setState(() {
      _loading = true;
      _error = null;
      _comics = [];
    });
    try {
      final service = context.read<ComicService>();
      final list = await service.searchBySource(widget.source, keyword);
      if (!mounted) return;
      setState(() {
        _comics = list;
        _loading = false;
        _hasMore = false;
      });
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未搜索到结果，可能是该图源搜索规则不匹配此站点')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }
}

class _ComicTile extends StatelessWidget {
  final Comic comic;

  /// 是否已加入书架。由父级一次性算好传入，避免每个网格项各自订阅
  /// [ComicService]。
  final bool favorited;

  const _ComicTile({required this.comic, required this.favorited});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: comic)),
        );
      },
      onLongPress: () => _toggleFavorite(context, favorited),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ComicCover(url: comic.coverUrl, width: double.infinity, radius: 8),
                // 加书架快捷按钮（右下角）
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: GestureDetector(
                    onTap: () => _toggleFavorite(context, favorited),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        favorited ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color: favorited ? Colors.redAccent : Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            comic.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(BuildContext context, bool favorited) async {
    final service = context.read<ComicService>();
    if (favorited) {
      await service.removeFavorite(comic);
      if (context.mounted) showToast(context, '已从书架移除');
    } else {
      await service.addFavorite(comic);
      if (context.mounted) showToast(context, '已加入书架', icon: Icons.favorite);
    }
  }
}
