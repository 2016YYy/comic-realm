import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

/// 首次启动的免责声明页：用户必须点击「同意」才能进入主界面，
/// 点击「不同意」则直接退出应用。
class DisclaimerScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const DisclaimerScreen({super.key, required this.onAccepted});

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _checked = false;

  static const _items = <String>[
    '本软件为开源漫画阅读器，本身不存储、不上传任何漫画内容，'
        '仅作为用户访问第三方图源网站的解析工具。',
    '所有漫画作品的版权归原作者及图源网站所有，本软件不拥有任何内容版权。',
    '本软件仅供个人学习交流使用，严禁用于任何商业用途。',
    '使用者应遵守所在国家或地区的法律法规，因使用本软件产生的一切法律责任由使用者自行承担。',
    '软件中的所有图源/书源均由用户自行导入，导入来源的合法性与合规性由用户自行负责。',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 32),
              Icon(Icons.balance, size: 56, color: scheme.primary),
              const SizedBox(height: 16),
              const Text(
                '免责声明',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '使用本软件前请仔细阅读并同意以下条款',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _items[i],
                                  style: const TextStyle(fontSize: 14, height: 1.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: scheme.primary),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '继续使用即表示你已理解并接受上述全部条款。',
                                style: TextStyle(fontSize: 12.5, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // 同意勾选
              InkWell(
                onTap: () => setState(() => _checked = !_checked),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _checked,
                        onChanged: (v) => setState(() => _checked = v ?? false),
                      ),
                      const Expanded(
                        child: Text('我已阅读并同意上述免责声明', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _exitApp,
                        child: const Text('不同意并退出'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _checked ? _accept : null,
                        child: const Text('同意并进入'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _accept() {
    context.read<SettingsService>().disclaimerAccepted = true;
    widget.onAccepted();
  }

  /// 不同意：退出应用
  void _exitApp() {
    SystemNavigator.pop();
  }
}
