import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/discover_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/update_screen.dart';
import 'services/comic_service.dart';
import 'services/download_service.dart';
import 'services/history_service.dart';
import 'services/settings_service.dart';
import 'services/source_service.dart';
import 'services/update_service.dart';

class ComicRealmApp extends StatelessWidget {
  const ComicRealmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProvider(create: (_) => SourceService()),
        ChangeNotifierProvider(create: (_) => ComicService()),
        ChangeNotifierProvider(create: (_) => DownloadService()),
        ChangeNotifierProvider(create: (_) => HistoryService()),
        ChangeNotifierProvider(create: (_) => UpdateService()),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: '漫境 ComicRealm',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: AppTheme.theme(Brightness.light, settings.seedColor),
            darkTheme: AppTheme.theme(Brightness.dark, settings.seedColor),
            home: const MainShell(),
          );
        },
      ),
    );
  }
}

/// 主框架：书库 / 发现 / 下载 / 图源 / 设置
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _autoCheckStarted = false;

  static const _pages = <Widget>[
    LibraryScreen(),
    DiscoverScreen(),
    DownloadsScreen(),
    SourcesScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台回到前台：刷新后台下载进度（下载本身在后台继续）
    if (state == AppLifecycleState.resumed) {
      context.read<UpdateService>().refreshFromBackground();
    }
  }

  /// 启动后的静默检查：只在确实有新版本且未被忽略时提示
  Future<void> _autoCheckUpdate() async {
    if (_autoCheckStarted || !mounted) return;
    _autoCheckStarted = true;
    final settings = context.read<SettingsService>();
    if (!settings.autoCheckUpdate) return;

    final updateService = context.read<UpdateService>();
    final hasNew = await updateService.checkForUpdate(
      silent: true,
      skippedVersion: settings.skippedVersion,
    );
    if (!hasNew || !mounted) return;

    final version = updateService.update?.version ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('发现新版本 v$version'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UpdateScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: '书架',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          const NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          const NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: '图源',
          ),
          NavigationDestination(
            icon: Consumer<UpdateService>(
              builder: (context, update, _) => _UpdateBadge(
                show: update.hasUpdate,
                child: const Icon(Icons.settings_outlined),
              ),
            ),
            selectedIcon: Consumer<UpdateService>(
              builder: (context, update, _) => _UpdateBadge(
                show: update.hasUpdate,
                child: const Icon(Icons.settings),
              ),
            ),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// 有新版本时给小圆点提示
class _UpdateBadge extends StatelessWidget {
  final Widget child;
  final bool show;

  const _UpdateBadge({required this.child, required this.show});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Badge(child: child);
  }
}
