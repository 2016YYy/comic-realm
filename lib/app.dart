import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/disclaimer_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sources_screen.dart';
import 'services/comic_service.dart';
import 'services/download_service.dart';
import 'services/history_service.dart';
import 'services/settings_service.dart';
import 'services/source_service.dart';
import 'services/update_service.dart';
import 'widgets/state_views.dart';
import 'widgets/update_dialog.dart';

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
            // 首次启动必须先同意免责声明，未同意前不进入主界面
            home: settings.disclaimerAccepted
                ? const MainShell()
                : DisclaimerScreen(
                    onAccepted: () {}, // 写入设置后由 Consumer 自动切换到主界面
                  ),
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
  bool _updateDialogShown = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoCheckUpdate();
      _listenUpdatePhase();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 监听更新下载状态：下载完成（ready）时若弹窗已打开则自动刷新为安装态
  void _listenUpdatePhase() {
    final updateService = context.read<UpdateService>();
    updateService.addListener(() {
      if (!mounted) return;
      // 进入 ready 状态时若弹窗未显示，则自动弹出安装弹窗
      if (updateService.phase == UpdatePhase.ready && !_updateDialogShown) {
        _updateDialogShown = true;
        showUpdateDialog(context).then((_) => _updateDialogShown = false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台回到前台：刷新后台下载进度（下载本身在后台继续）
    if (state == AppLifecycleState.resumed) {
      context.read<UpdateService>().refreshFromBackground();
    }
  }

  /// 启动后的静默检查：有新版本直接弹窗；已是最新版本则吐司提示
  Future<void> _autoCheckUpdate() async {
    if (_autoCheckStarted || !mounted) return;
    _autoCheckStarted = true;
    final settings = context.read<SettingsService>();
    if (!settings.autoCheckUpdate) return;

    final updateService = context.read<UpdateService>();
    final hasNew = await updateService.checkForUpdate(
      silent: true,
      skippedVersion: settings.skippedVersion,
      includePrerelease: settings.includePrerelease,
    );
    if (!mounted) return;

    if (hasNew) {
      if (!_updateDialogShown) {
        _updateDialogShown = true;
        showUpdateDialog(context).then((_) => _updateDialogShown = false);
      }
    } else {
      // 已是最新版本（或被忽略）：吐司轻提示
      showToast(
        context,
        '当前已是最新版本',
        icon: Icons.check_circle_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
