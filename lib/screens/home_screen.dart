import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/comic.dart';
import '../services/comic_service.dart';
import 'comic_detail_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final comicService = context.watch<ComicService>();
    final favorites = comicService.favorites;

    return Scaffold(
      appBar: AppBar(
        title: const Text('漫境 ComicRealm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
          ),
        ],
      ),
      body: favorites.isEmpty
          ? const _EmptyFavorites()
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final comic = favorites[index];
                return _ComicGridItem(comic: comic);
              },
            ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book, size: 80, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text('书库空空如也', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('点击右上角搜索，或前往「图源」添加图源', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('去搜索'),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
          ),
        ],
      ),
    );
  }
}

class _ComicGridItem extends StatelessWidget {
  final Comic comic;
  const _ComicGridItem({required this.comic});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: comic)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: comic.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: comic.coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(color: Colors.grey[800]),
                      errorWidget: (_, __, ___) => Container(color: Colors.grey[800], child: const Icon(Icons.broken_image)),
                    )
                  : Container(color: Colors.grey[800], child: const Icon(Icons.image_not_supported)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            comic.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (comic.lastChapter.isNotEmpty)
            Text(comic.lastChapter, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }
}
