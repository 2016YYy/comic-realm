import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/device_info.dart';

/// 错误日志记录与反馈：
/// - 本地追加写入日志文件，便于排查
/// - 一键跳转到 GitHub Issues 新建页，预填错误详情与设备信息
class ErrorReportService {
  static const String repo = '2016YYy/comic-realm';

  /// 将一条错误记录追加到本地日志文件
  static Future<void> appendLog({
    required String message,
    required Object? detail,
    StackTrace? stackTrace,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/error_logs.log');
      final ts = DateTime.now().toIso8601String();
      final buf = StringBuffer()
        ..writeln('==============================')
        ..writeln('[$ts] $message')
        ..writeln(detail)
        ..writeln(stackTrace ?? '(no stack trace)')
        ..writeln();
      await file.writeAsString(buf.toString(), mode: FileMode.append, flush: true);
    } catch (_) {
      // 写日志失败静默忽略，避免阻塞 UI
    }
  }

  /// 打开 GitHub Issues 新建页，预填标题与正文（含设备信息）
  static Future<void> openFeedback({
    required String title,
    required String message,
    required Object? detail,
  }) async {
    final device = await DeviceInfo.collect();
    final body = '''
**错误描述**：$message

**错误详情**：
```
${detail.toString()}
```

${device.toMarkdown()}
> 请补充复现步骤与使用的图源，谢谢！
''';
    final uri = Uri.https('github.com', '/$repo/issues/new', {
      'title': '[反馈] $title',
      'body': body,
      'labels': 'bug',
    });
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 将错误信息复制到剪贴板所需的纯文本
  static String copyText(String message, Object? detail) {
    final buf = StringBuffer()
      ..writeln('错误：$message')
      ..writeln('详情：$detail');
    return buf.toString();
  }

  /// 对反馈 URL 做 UTF-8 编码（GitHub 支持中文 issue 标题/正文）
  static String encodeComponent(String s) => Uri.encodeComponent(s);
}
