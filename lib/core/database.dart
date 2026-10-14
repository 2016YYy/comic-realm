import 'package:hive_flutter/hive_flutter.dart';
import '../models/source.dart';
import '../models/comic.dart';
import '../models/download.dart';

/// 本地数据库封装（Hive）
class AppDatabase {
  static const String sourceBox = 'sources';
  static const String favoriteBox = 'favorites';
  static const String downloadBox = 'downloads';
  static const String settingBox = 'settings';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(ComicSourceAdapter());
    Hive.registerAdapter(ComicAdapter());
    Hive.registerAdapter(ChapterAdapter());
    Hive.registerAdapter(DownloadTaskAdapter());
    await Hive.openBox<ComicSource>(sourceBox);
    await Hive.openBox<Comic>(favoriteBox);
    await Hive.openBox<DownloadTask>(downloadBox);
    await Hive.openBox(settingBox);
  }

  static Box<ComicSource> get sources => Hive.box<ComicSource>(sourceBox);
  static Box<Comic> get favorites => Hive.box<Comic>(favoriteBox);
  static Box<DownloadTask> get downloads => Hive.box<DownloadTask>(downloadBox);
  static Box get settings => Hive.box(settingBox);
}
