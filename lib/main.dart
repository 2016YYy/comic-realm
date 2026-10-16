import 'package:flutter/material.dart';

import 'app.dart';
import 'core/database.dart';
import 'core/http_client.dart';
import 'core/js_runtime.dart';
import 'services/comic_service.dart';
import 'services/source_service.dart';
import 'services/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.init();
  // 收藏键迁移：旧版仅用 noteUrl，新版用 sourceUrl + noteUrl 复合键
  await ComicService.migrateFavorites();
  await HttpClient().init();
  await JsRuntime().init();
  // 接管上次未完成的更新下载任务，并配置后台下载通知
  await UpdateService.configureBackground();
  await SourceService().loadBuiltInSources();
  runApp(const ComicRealmApp());
}
