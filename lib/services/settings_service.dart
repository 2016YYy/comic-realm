import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../core/database.dart';
import '../core/theme.dart';

/// 书库排列方式
enum LibraryViewMode {
  /// 封面网格（默认）
  grid,

  /// 紧凑网格（一行多本，只看封面）
  compact,

  /// 列表（封面 + 简介 + 最新章节）
  list,
}

/// 书库排序方式
enum LibrarySort {
  /// 最近加入
  added,

  /// 最近阅读（无阅读记录时回落到加入时间）
  recent,

  /// 标题
  title,

  /// 图源
  source,
}

/// 全局偏好设置：主题、书库视图、阅读器行为、更新策略。
/// 统一存进 Hive 的 `settings` box，避免各处散落 SharedPreferences 键。
class SettingsService extends ChangeNotifier {
  static const _kThemeMode = 'themeMode';
  static const _kSeedColor = 'seedColor';
  static const _kViewMode = 'libraryViewMode';
  static const _kSort = 'librarySort';
  static const _kAutoCheckUpdate = 'autoCheckUpdate';
  static const _kSkippedVersion = 'skippedVersion';
  static const _kIncludePrerelease = 'includePrerelease';
  static const _kReaderContinuous = 'readerContinuous';
  static const _kReaderFontSize = 'readerFontSize';
  static const _kDisclaimerAccepted = 'disclaimerAccepted';
  static const _kFolders = 'libraryFolders';
  static const _kSearchHistory = 'searchHistory';
  static const _kGlassEffect = 'glassEffect';

  Box get _box => AppDatabase.settings;

  // ---------------- 主题 ----------------

  ThemeMode get themeMode {
    final v = _box.get(_kThemeMode) as String?;
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  set themeMode(ThemeMode mode) {
    _box.put(_kThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    notifyListeners();
  }

  Color get seedColor {
    final v = _box.get(_kSeedColor) as int?;
    if (v == null) return AppTheme.seeds.first.color;
    return Color(v);
  }

  set seedColor(Color color) {
    _box.put(_kSeedColor, color.toARGB32());
    notifyListeners();
  }

  // ---------------- 书库 ----------------

  LibraryViewMode get libraryViewMode {
    final v = _box.get(_kViewMode) as int? ?? 0;
    return LibraryViewMode.values[v.clamp(0, LibraryViewMode.values.length - 1)];
  }

  set libraryViewMode(LibraryViewMode mode) {
    _box.put(_kViewMode, mode.index);
    notifyListeners();
  }

  LibrarySort get librarySort {
    final v = _box.get(_kSort) as int? ?? 0;
    return LibrarySort.values[v.clamp(0, LibrarySort.values.length - 1)];
  }

  set librarySort(LibrarySort sort) {
    _box.put(_kSort, sort.index);
    notifyListeners();
  }

  // ---------------- 阅读器 ----------------

  /// true = 竖向连续滚动（条漫），false = 横向翻页
  bool get readerContinuous => _box.get(_kReaderContinuous) as bool? ?? true;

  set readerContinuous(bool value) {
    _box.put(_kReaderContinuous, value);
    notifyListeners();
  }

  /// 小说正文字号（像素），默认 18。
  double get readerFontSize {
    final v = _box.get(_kReaderFontSize);
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return 18;
  }

  set readerFontSize(double value) {
    _box.put(_kReaderFontSize, value);
    notifyListeners();
  }

  // ---------------- 更新 ----------------

  bool get autoCheckUpdate => _box.get(_kAutoCheckUpdate) as bool? ?? true;

  set autoCheckUpdate(bool value) {
    _box.put(_kAutoCheckUpdate, value);
    notifyListeners();
  }

  /// 用户选择「忽略此版本」后记录，自动检查时不再提示
  String get skippedVersion => _box.get(_kSkippedVersion) as String? ?? '';

  set skippedVersion(String value) {
    _box.put(_kSkippedVersion, value);
    notifyListeners();
  }

  /// 是否包含预发布版本（测试版 / beta）
  bool get includePrerelease => _box.get(_kIncludePrerelease) as bool? ?? false;

  set includePrerelease(bool value) {
    _box.put(_kIncludePrerelease, value);
    notifyListeners();
  }

  // ---------------- 外观 ----------------

  /// 是否启用毛玻璃（Liquid Glass）效果。默认开启；低端设备可关闭以换取更流畅。
  bool get glassEffect => _box.get(_kGlassEffect) as bool? ?? true;

  set glassEffect(bool value) {
    _box.put(_kGlassEffect, value);
    notifyListeners();
  }

  // ---------------- 免责声明 ----------------

  /// 用户是否已同意免责声明（首次启动必须同意才能进入）
  bool get disclaimerAccepted =>
      _box.get(_kDisclaimerAccepted) as bool? ?? false;

  set disclaimerAccepted(bool value) {
    _box.put(_kDisclaimerAccepted, value);
    notifyListeners();
  }

  // ---------------- 书架文件夹 ----------------

  /// 用户自建的书架文件夹名称列表
  List<String> get folders {
    final v = _box.get(_kFolders);
    if (v is List) return List<String>.from(v.map((e) => e.toString()));
    return [];
  }

  void addFolder(String name) {
    final list = folders;
    if (name.trim().isEmpty || list.contains(name)) return;
    list.add(name);
    _box.put(_kFolders, list);
    notifyListeners();
  }

  void removeFolder(String name) {
    final list = folders..remove(name);
    _box.put(_kFolders, list);
    notifyListeners();
  }

  void renameFolder(String oldName, String newName) {
    final list = folders;
    final i = list.indexOf(oldName);
    if (i < 0 || newName.trim().isEmpty || list.contains(newName)) return;
    list[i] = newName;
    _box.put(_kFolders, list);
    notifyListeners();
  }

  // ---------------- 搜索历史 ----------------

  /// 搜索历史关键词上限
  static const int maxSearchHistory = 20;

  /// 最近搜索过的关键词，最新的排在最前
  List<String> get searchHistory {
    final v = _box.get(_kSearchHistory);
    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    return [];
  }

  /// 记录一次搜索：去重后置顶，超出上限截断。
  void addSearchHistory(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final list = searchHistory..remove(k);
    list.insert(0, k);
    if (list.length > maxSearchHistory) {
      list.removeRange(maxSearchHistory, list.length);
    }
    _box.put(_kSearchHistory, list);
    notifyListeners();
  }

  /// 删除单条搜索历史
  void removeSearchHistory(String keyword) {
    final list = searchHistory..remove(keyword);
    _box.put(_kSearchHistory, list);
    notifyListeners();
  }

  /// 清空全部搜索历史
  void clearSearchHistory() {
    _box.put(_kSearchHistory, const <String>[]);
    notifyListeners();
  }
}
