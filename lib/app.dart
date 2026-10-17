import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
            // 中文本地化：文本选择菜单（剪切/复制/粘贴/全选等）显示中文
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
              Locale('zh', 'HK'),
              Locale('en', 'US'),
            ],
            locale: const Locale('zh', 'CN'),
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
      // 自定义底部导航：点击时图标与文字同步变色，并带缩放/颜色过渡动画
      bottomNavigationBar: Material(
        color: scheme.surface,
        elevation: 2,
        child: SafeArea(
          child: Row(
            children: List.generate(_navItems.length, (i) {
              return _AnimatedNavItem(
                item: _navItems[i],
                selected: _index == i,
                onTap: () => setState(() => _index = i),
                badge: i == 4 ? context.watch<UpdateService>().hasUpdate : false,
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 底部导航数据项
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

const _navItems = <_NavItem>[
  _NavItem(Icons.video_library_outlined, Icons.video_library, '书架'),
  _NavItem(Icons.explore_outlined, Icons.explore, '发现'),
  _NavItem(Icons.download_outlined, Icons.download, '下载'),
  _NavItem(Icons.dns_outlined, Icons.dns, '图源'),
  _NavItem(Icons.settings_outlined, Icons.settings, '设置'),
];

/// 单个导航项：选中时图标+文字同时变色（主题色），带弹性缩放动画。
class _AnimatedNavItem extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool badge;

  const _AnimatedNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: selected ? 1.12 : 1.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        selected ? item.activeIcon : item.icon,
                        key: ValueKey(selected),
                        size: 24,
                        // 点击变色：图标颜色随选中态平滑过渡
                        color: color,
                      ),
                    ),
                    if (badge)
                      const Positioned(
                        right: -6,
                        top: -2,
                        child: Badge(),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    // 点击变色：文字颜色随选中态平滑过渡
                    color: color,
                  ),
                  child: Text(item.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
