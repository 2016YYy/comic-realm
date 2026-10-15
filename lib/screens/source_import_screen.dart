import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/source_service.dart';

class SourceImportScreen extends StatefulWidget {
  const SourceImportScreen({super.key});

  @override
  State<SourceImportScreen> createState() => _SourceImportScreenState();
}

class _SourceImportScreenState extends State<SourceImportScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('导入图源 / 书源'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.link), text: '网络地址'),
              Tab(icon: Icon(Icons.folder_open), text: '本地文件'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: '二维码'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUrlTab(),
            _buildLocalTab(),
            _buildQrTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '图源 JSON 地址',
              hintText: 'https://example.com/source.json',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
            label: const Text('导入'),
            onPressed: _importing ? null : _importFromUrl,
          ),
          const SizedBox(height: 16),
          Text(
            '图源 / 书源规则兼容 开源阅读(legado) / 异次元 的 JSON 格式，'
            '支持文本小说源与漫画图源。\n'
            '可在源仓库站获取源地址：\n'
            '• 图源：https://www.yckceo.com/yiciyuan/tuyuans/json/id/50.json\n'
            '• 书源：https://www.yckceo.com/yuedu/shuyuans/json/id/293.json',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalTab() {
    return Center(
      child: FilledButton.icon(
        icon: const Icon(Icons.folder_open),
        label: const Text('选择图源 JSON 文件'),
        onPressed: _importing ? null : _importFromFile,
      ),
    );
  }

  Widget _buildQrTab() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final value = barcode.rawValue;
              if (value != null && value.isNotEmpty) {
                _importFromQr(value);
                return;
              }
            }
          },
        ),
        Positioned(
          bottom: 30,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('将图源二维码对准扫描框',
                      style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册选择'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: _importing ? null : _importFromAlbum,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入地址')));
      return;
    }
    setState(() => _importing = true);
    try {
      final imported = await context.read<SourceService>().importFromUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功导入 ${imported.length} 个图源')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromFile() async {
    final sourceService = context.read<SourceService>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() => _importing = true);
    try {
      final imported = await sourceService.importFromFile(result.files.single.path!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功导入 ${imported.length} 个图源')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromQr(String content) async {
    setState(() => _importing = true);
    try {
      final imported = await context.read<SourceService>().importFromJson(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功导入 ${imported.length} 个图源')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 从系统相册选择图片，识别其中的二维码并导入图源。
  Future<void> _importFromAlbum() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result == null || result.files.single.path == null) {
        if (mounted) setState(() => _importing = false);
        return;
      }
      final imagePath = result.files.single.path!;

      // 使用 mobile_scanner 的 analyzeImage 从图片中解析二维码
      final controller = MobileScannerController();
      final capture = await controller.analyzeImage(imagePath);
      await controller.dispose();

      if (capture == null || capture.barcodes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未在图片中识别到二维码')),
        );
        return;
      }

      final value = capture.barcodes.first.rawValue;
      if (value == null || value.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('二维码内容为空')),
        );
        return;
      }

      if (!mounted) return;
      await _importFromQr(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败：$e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
