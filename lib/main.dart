import 'package:flutter/material.dart';
import 'app.dart';
import 'core/database.dart';
import 'core/http_client.dart';
import 'core/js_runtime.dart';
import 'services/source_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.init();
  await HttpClient().init();
  await JsRuntime().init();
  await SourceService().loadBuiltInSources();
  runApp(const ComicRealmApp());
}
