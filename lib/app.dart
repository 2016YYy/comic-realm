import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/settings_screen.dart';
import 'services/comic_service.dart';
import 'services/download_service.dart';
import 'services/source_service.dart';

class ComicRealmApp extends StatelessWidget {
  const ComicRealmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SourceService()),
        ChangeNotifierProvider(create: (_) => ComicService()),
        ChangeNotifierProvider(create: (_) => DownloadService()),
      ],
      child: MaterialApp(
        title: '漫境 ComicRealm',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C5CE7),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF12121A),
          cardColor: const Color(0xFF1E1E2E),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _pages = const [
    HomeScreen(),
    SourcesScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '书库'),
          NavigationDestination(icon: Icon(Icons.language), label: '图源'),
          NavigationDestination(icon: Icon(Icons.download), label: '下载'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
