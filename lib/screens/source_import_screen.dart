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
          title: const Text('导入图源'),
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
            '图源规则格式兼容 开源阅读(legado) / 异次元 的 JSON 图源。\n'
            '可在 https://www.yckceo.com/yiciyuan/tuyuan/index.html 等图源站找到图源链接。',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: const Text('将图源二维码对准扫描框', style: TextStyle(color: Colors.white)),
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() => _importing = true);
    try {
      final imported = await context.read<SourceService>().importFromFile(result.files.single.path!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功导入 ${imported.length} 个图源')));
      Navigator.pop(context);
    } catch (e) {
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
}
