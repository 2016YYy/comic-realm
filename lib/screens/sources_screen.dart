import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/source_service.dart';
import 'source_import_screen.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sourceService = context.watch<SourceService>();
    final sources = sourceService.allSources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图源管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceImportScreen()));
            },
          ),
        ],
      ),
      body: sources.isEmpty
          ? Center(child: Text('还没有图源，点击右上角添加', style: TextStyle(color: Colors.grey[500])))
          : ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                return ListTile(
                  leading: Icon(source.enable ? Icons.cloud_done : Icons.cloud_off,
                      color: source.enable ? Colors.green : Colors.grey),
                  title: Text(source.bookSourceName),
                  subtitle: Text(source.bookSourceUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: source.enable,
                        onChanged: (_) => sourceService.toggleSource(source),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('删除图源'),
                              content: Text('确定删除「${source.bookSourceName}」吗？'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                                TextButton(
                                  onPressed: () {
                                    sourceService.removeSource(source);
                                    Navigator.pop(context);
                                  },
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
