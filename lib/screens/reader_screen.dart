import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/comic.dart';
import '../models/source.dart';
import '../services/comic_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../widgets/comic_cover.dart';
import '../widgets/glass.dart';
import '../widgets/state_views.dart';

/// 阅读器：竖向连续滚动（条漫）或横向翻页，均支持上一话 / 下一话切换。
class ReaderScreen extends StatefulWidget {
  final ComicSource? source;
  final Comic comic;
  final List<Chapter>? chapters;
  final int initialIndex;

  /// 离线模式：直接传入已下载的本地内容，不走 source engine。
  final List<String>? offlineImages;
  final String? offlineText;

  const ReaderScreen({
    super.key,
    this.source,
    required this.comic,
    this.chapters,
    this.initialIndex = 0,
    this.offlineImages,
    this.offlineText,
  });

  /// 离线模式快捷构造
  factory ReaderScreen.offline({
    required Comic comic,
    List<String>? images,
    String? text,
    List<Chapter>? chapters,
    int initialIndex = 0,
  }) {
    return ReaderScreen(
      comic: comic,
      chapters: chapters,
      initialIndex: initialIndex,
      offlineImages: images,
      offlineText: text,
    );
  }

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late int _currentIndex;
  List<String> _images = [];
  String _text = '';
  bool _loading = true;
  String? _error;
  bool _chromeVisible = false; // 默认沉浸式，点击中间区域才显示菜单
  // 阅读菜单扩展状态
  bool _chapterReversed = false; // 章节目录倒序
  double _dimming = 0; // 亮度调节（0=最亮，0.6=最暗）
  int _novelBg = 0; // 小说背景色：0=黑 1=米黄 2=浅绿 3=羊皮纸
  final TextEditingController _jumpCtrl = TextEditingController();

  static const _novelBgColors = <Color>[
    Colors.black,
    Color(0xFFF5EFDC),
    Color(0xFFE3EFE3),
    Color(0xFFEAD9C0),
  ];
  static const _novelBgTextColors = <Color>[
    Colors.white,
    Color(0xFF3B3021),
    Color(0xFF263226),
    Color(0xFF403122),
  ];

  bool get _isNovel {
    if (widget.source != null) return widget.source!.isNovel;
    return widget.offlineText != null;
  }

  bool get _isOffline {
    return widget.offlineImages != null || widget.offlineText != null;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // 沉浸式：隐藏状态栏与导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (_isOffline) {
      _images = widget.offlineImages ?? [];
      _text = widget.offlineText ?? '';
      _loading = false;
    } else {
      _loadChapter();
    }
  }

  @override
  void dispose() {
    // 退出阅读器时恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    _jumpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChapter() async {
    final source = widget.source;
    final chapters = widget.chapters;
    if (source == null || chapters == null || chapters.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _images = [];
      _text = '';
    });
    final comicService = context.read<ComicService>();
    final chapter = chapters[_currentIndex];
    try {
      if (_isNovel) {
        final text = await comicService.getContentText(source, chapter, widget.comic);
        if (!mounted) return;
        setState(() {
          _text = text;
          _loading = false;
        });
      } else {
        final images = await comicService.getContent(source, chapter, widget.comic);
        if (!mounted) return;
        setState(() {
          _images = images;
          _loading = false;
        });
      }
      // 记录阅读历史
      context.read<HistoryService>().record(
            comic: widget.comic,
            chapterName: chapter.name,
            chapterIndex: _currentIndex,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ComicService.friendlyError(e);
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _loadChapter();
    }
  }

  void _next() {
    final count = widget.chapters?.length ?? 0;
    if (_currentIndex < count - 1) {
      setState(() => _currentIndex++);
      _loadChapter();
    }
  }

  /// 阅读设置底部弹窗：阅读模式 + 字号（小说）+ 亮度 + 背景色
  Future<void> _showReaderSettings() async {
    final settings = context.read<SettingsService>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('阅读设置',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                const Text('阅读模式',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ListenableBuilder(
                  listenable: settings,
                  builder: (_, __) => SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          label: Text('连续滚动'),
                          icon: Icon(Icons.view_agenda_outlined)),
                      ButtonSegment(
                          value: false,
                          label: Text('横向翻页'),
                          icon: Icon(Icons.swipe_outlined)),
                    ],
                    selected: {settings.readerContinuous},
                    onSelectionChanged: (v) =>
                        settings.readerContinuous = v.first,
                  ),
                ),
                const SizedBox(height: 20),
                // 亮度调节（参照开源阅读：屏幕遮罩变暗）
                Row(
                  children: [
                    const Icon(Icons.brightness_4_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Text('亮度', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 0.6,
                        value: _dimming,
                        label: _dimming == 0
                            ? '最亮'
                            : '${(100 - _dimming / 0.6 * 100).round()}%',
                        onChanged: (v) {
                          setSheet(() => _dimming = v);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                if (_isNovel) ...[
                  const Text('背景色',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(_novelBgColors.length, (i) {
                      final active = _novelBg == i;
                      return GestureDetector(
                        onTap: () {
                          setSheet(() => _novelBg = i);
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 12),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _novelBgColors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Colors.grey,
                              width: active ? 3 : 1,
                            ),
                          ),
                          child: active
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: _novelBgTextColors[i],
                                )
                              : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  // 字号
                  ListenableBuilder(
                    listenable: settings,
                    builder: (_, __) => Row(
                      children: [
                        const Icon(Icons.text_fields, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            min: 12,
                            max: 28,
                            divisions: 16,
                            value: settings.readerFontSize,
                            label: '${settings.readerFontSize.round()}',
                            onChanged: (v) {
                              settings.readerFontSize = v;
                              setSheet(() {});
                            },
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text('${settings.readerFontSize.round()}',
                              textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 章节目录弹窗：快速跳转到指定章节，支持倒序与章节号跳转。
  Future<void> _showChapterList() async {
    final chapters = widget.chapters;
    if (chapters == null || chapters.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChapterListSheet(
        chapters: chapters,
        currentIndex: _currentIndex,
        reversed: _chapterReversed,
        jumpCtrl: _jumpCtrl,
        onToggleReversed: () => setState(() => _chapterReversed = !_chapterReversed),
      ),
    );
    if (selected == null || !mounted || selected == _currentIndex) return;
    setState(() => _currentIndex = selected);
    _loadChapter();
  }

  @override
  Widget build(BuildContext context) {
    final chapterCount = widget.chapters?.length ?? 0;
    final chapterName = widget.chapters != null && _currentIndex < chapterCount
        ? widget.chapters![_currentIndex].name
        : widget.comic.name;
    final continuous = context.watch<SettingsService>().readerContinuous;

    return Scaffold(
      backgroundColor: Colors.black,
      // 顶 / 底菜单改为悬浮在画面之上，毛玻璃可实时模糊漫画内容
      body: Stack(
        children: [
          _buildBody(continuous),
          // 亮度遮罩：数值越大越暗（阅读菜单中调节）
          if (_dimming > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _dimming,
                  duration: const Duration(milliseconds: 200),
                  child: Container(color: Colors.black),
                ),
              ),
            ),
          // 点击分区：左侧上一话，中间切换菜单，右侧下一话
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (!_isOffline && _currentIndex > 0) _prev();
                    },
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _chromeVisible = !_chromeVisible),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      final count = widget.chapters?.length ?? 0;
                      if (!_isOffline && _currentIndex < count - 1) _next();
                    },
                  ),
                ),
              ],
            ),
          ),
          // 顶栏 / 底栏悬浮于画面之上（放在最上层，优先响应点击）
          if (_chromeVisible) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: _buildTopBar(chapterName, chapterCount),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(),
            ),
          ],
        ],
      ),
    );
  }

  /// 顶部悬浮栏：毛玻璃顶栏，展示章节名与上一话 / 下一话 / 设置。
  Widget _buildTopBar(String chapterName, int chapterCount) {
    final glass = context.watch<SettingsService>().glassEffect;
    final inner = Material(
      type: MaterialType.transparency,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '返回',
                onPressed: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                    if (chapterCount > 0)
                      Text(
                        '${_currentIndex + 1} / $chapterCount${_isOffline ? ' · 离线' : ''}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                  ],
                ),
              ),
              if (!_isOffline && chapterCount > 0) ...[
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _currentIndex > 0 ? _prev : null,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _currentIndex < chapterCount - 1 ? _next : null,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                tooltip: '阅读设置',
                onPressed: _showReaderSettings,
              ),
            ],
          ),
        ),
      ),
    );
    if (!glass) {
      return ColoredBox(color: Colors.black, child: inner);
    }
    return GlassBlur(
      blur: 22,
      border: false,
      tint: Colors.black.withValues(alpha: 0.42),
      child: inner,
    );
  }

  /// 底部操作栏：上一话 / 目录 / 阅读模式 / 亮度 / 设置 / 下一话（与顶部菜单一同显示）。
  Widget _buildBottomBar() {
    final chapterCount = widget.chapters?.length ?? 0;
    final glass = context.watch<SettingsService>().glassEffect;
    final style = TextButton.styleFrom(foregroundColor: Colors.white);
    final bar = Material(
      color: glass ? Colors.transparent : Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed:
                          (!_isOffline && _currentIndex > 0) ? _prev : null,
                      icon: const Icon(Icons.skip_previous, size: 20),
                      label: const Text('上一话'),
                      style: style,
                    ),
                  ),
                  if (chapterCount > 0 && !_isOffline)
                    TextButton.icon(
                      onPressed: _showChapterList,
                      icon: const Icon(Icons.menu_book_outlined, size: 20),
                      label: Text('目录 ${_currentIndex + 1}/$chapterCount'),
                      style: style,
                    ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: (!_isOffline && _currentIndex < chapterCount - 1)
                          ? _next
                          : null,
                      icon: const Icon(Icons.skip_next, size: 20),
                      label: const Text('下一话'),
                      style: style,
                    ),
                  ),
                ],
              ),
              // 第二行工具条（参照开源阅读）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      final settings = context.read<SettingsService>();
                      settings.readerContinuous = !settings.readerContinuous;
                      setState(() {});
                    },
                    icon: Icon(
                      context.watch<SettingsService>().readerContinuous
                          ? Icons.view_agenda
                          : Icons.swipe,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: Text(
                      context.watch<SettingsService>().readerContinuous
                          ? '滚动'
                          : '翻页',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    style: style,
                  ),
                  IconButton(
                    tooltip: '亮度调节',
                    onPressed: _showReaderSettings,
                    icon: const Icon(Icons.brightness_4_outlined,
                        color: Colors.white, size: 20),
                  ),
                  IconButton(
                    tooltip: '夜间 / 日间',
                    onPressed: () {
                      setState(() {
                        if (_dimming > 0) {
                          _dimming = 0;
                        } else {
                          _dimming = 0.45;
                        }
                      });
                    },
                    icon: Icon(
                      _dimming > 0 ? Icons.wb_sunny : Icons.nights_stay,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: '阅读设置',
                    onPressed: _showReaderSettings,
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!glass) return bar;
    return GlassBlur(
      blur: 22,
      border: false,
      tint: Colors.black.withValues(alpha: 0.42),
      child: bar,
    );
  }

  Widget _buildBody(bool continuous) {
    if (_loading) return const LoadingView(label: '正在加载本章…');
    if (_error != null) {
      return ErrorView(message: '本章加载失败', detail: _error, onRetry: _loadChapter);
    }

    if (_isNovel) {
      if (_text.trim().isEmpty) {
        return const EmptyView(icon: Icons.article_outlined, title: '本章没有内容');
      }
      return _buildNovelText();
    }

    if (_images.isEmpty) {
      return const EmptyView(icon: Icons.image_not_supported_outlined, title: '本章没有图片');
    }

    if (continuous) {
      return ListView.builder(
        itemCount: _images.length,
        // 预渲染视口外一段距离，减少快速上下拖动时的白屏与掉帧。
        cacheExtent: 1200,
        itemBuilder: (_, i) => _ReaderImage(url: _images[i]),
      );
    }

    return PageView.builder(
      itemCount: _images.length,
      itemBuilder: (_, i) => InteractiveViewer(
        maxScale: 4,
        child: Center(child: _ReaderImage(url: _images[i])),
      ),
    );
  }

  Widget _buildNovelText() {
    final settings = context.watch<SettingsService>();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      color: _novelBgColors[_novelBg],
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          Text(
            _text,
            style: TextStyle(
              fontSize: settings.readerFontSize.toDouble(),
              height: 1.8,
              color: _novelBgTextColors[_novelBg],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderImage extends StatelessWidget {
  final String url;

  const _ReaderImage({required this.url});

  /// 网络地址直接判定为非本地，避免每次 build 都对 http(s) 地址做一次
  /// 同步文件探测（同步 IO 会阻塞 UI 线程，长图列表滚动时尤其明显）。
  bool get _isLocal => !url.startsWith('http') && File(url).existsSync();

  @override
  Widget build(BuildContext context) {
    if (_isLocal) {
      return Image.file(
        File(url),
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 320,
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      // 与封面一致：按图片域名补同源 Referer，绕过常见防盗链。
      httpHeaders: ComicCover.imageHeaders(url),
      placeholder: (_, __) => const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (_, __, ___) => const SizedBox(
        height: 320,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
        ),
      ),
    );
  }
}

/// 章节目录弹窗：列出全部章节，支持正序/倒序切换与章节号跳转。
///
/// 用 StatefulWidget 持有 [ScrollController]，随弹窗销毁一起释放（此前在
/// build 内新建且从不 dispose，反复打开目录会持续泄漏）。倒序状态改为弹窗
/// 内部维护，点击后立即刷新列表（此前只改父页状态，弹窗本身不会重建）。
class _ChapterListSheet extends StatefulWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final bool reversed;
  final TextEditingController jumpCtrl;
  final VoidCallback onToggleReversed;

  const _ChapterListSheet({
    required this.chapters,
    required this.currentIndex,
    required this.reversed,
    required this.jumpCtrl,
    required this.onToggleReversed,
  });

  @override
  State<_ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends State<_ChapterListSheet> {
  final ScrollController _controller = ScrollController();
  late bool _reversed = widget.reversed;

  List<int> get _display {
    final indices = List<int>.generate(widget.chapters.length, (i) => i);
    return _reversed ? indices.reversed.toList() : indices;
  }

  @override
  void initState() {
    super.initState();
    // 打开目录后立即定位到当前章节
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final pos = _display.indexOf(widget.currentIndex);
      if (pos > 0) {
        _controller.jumpTo(
          (pos * 48.0).clamp(0, _controller.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleReversed() {
    setState(() => _reversed = !_reversed);
    widget.onToggleReversed();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chapters = widget.chapters;
    final display = _display;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  // 章节号跳转
                  Expanded(
                    child: TextField(
                      controller: widget.jumpCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '跳转到章节号（1-${chapters.length}）',
                        prefixIcon: const Icon(Icons.tag, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onSubmitted: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n >= 1 && n <= chapters.length) {
                          Navigator.pop(context, n - 1);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _reversed ? '当前：倒序' : '当前：正序',
                    onPressed: _toggleReversed,
                    icon: Icon(_reversed
                        ? Icons.arrow_upward
                        : Icons.arrow_downward),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _controller,
                itemCount: display.length,
                itemExtent: 48,
                itemBuilder: (_, pos) {
                  final i = display[pos];
                  final active = i == widget.currentIndex;
                  return ListTile(
                    dense: true,
                    selected: active,
                    leading: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: active ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      chapters[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: active
                        ? Icon(Icons.play_arrow, color: scheme.primary, size: 20)
                        : null,
                    onTap: () => Navigator.pop(context, i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
