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
import 'widgets/state_views.dart';

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
  bool _installDialogShown = false;

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

  /// 监听更新下载状态：下载完成后自动弹出安装弹窗
  void _listenUpdatePhase() {
    final updateService = context.read<UpdateService>();
    updateService.addListener(() {
      if (!mounted) return;
      // 下载完成（ready）且尚未弹窗 → 自动弹出安装确认
      if (updateService.phase == UpdatePhase.ready && !_installDialogShown) {
        _installDialogShown = true;
        _showInstallDialog();
      }
      // 离开 ready 状态后重置标记，允许下次下载完成再次弹窗
      if (updateService.phase != UpdatePhase.ready) {
        _installDialogShown = false;
      }
    });
  }

  void _showInstallDialog() {
    final updateService = context.read<UpdateService>();
    final version = updateService.update?.version ?? '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 40),
        title: const Text('更新包下载完成'),
        content: Text('新版本 v$version 已下载完成，是否立即安装？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await updateService.install();
              if (!ctx.mounted) return;
              showToast(
                ctx,
                result.message,
                icon: result.ok ? Icons.check_circle_outline : Icons.error_outline,
                isError: !result.ok,
              );
            },
            icon: const Icon(Icons.install_desktop),
            label: const Text('立即安装'),
          ),
        ],
      ),
    );
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
      includePrerelease: settings.includePrerelease,
    );
    if (!hasNew || !mounted) return;

    final version = updateService.update?.version ?? '';
    showToast(
      context,
      '发现新版本 v$version',
      icon: Icons.new_releases_outlined,
      duration: const Duration(seconds: 6),
    );
    // 延迟后跳转到更新页
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UpdateScreen()),
      );
    });
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
