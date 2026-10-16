import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';

/// 收集设备与应用信息，用于错误反馈，方便定位问题。
class DeviceInfo {
  final String os;
  final String osVersion;
  final String locale;
  final String appVersion;
  final String buildNumber;
  final String packageName;

  DeviceInfo({
    required this.os,
    required this.osVersion,
    required this.locale,
    required this.appVersion,
    required this.buildNumber,
    required this.packageName,
  });

  static Future<DeviceInfo> collect() async {
    final info = await PackageInfo.fromPlatform();
    return DeviceInfo(
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      locale: Platform.localeName,
      appVersion: info.version,
      buildNumber: info.buildNumber,
      packageName: info.packageName,
    );
  }

  String toMarkdown() {
    return '''
### 设备信息
- 操作系统：`$os`
- 系统版本：`$osVersion`
- 系统语言：`$locale`
- 应用版本：`$appVersion` ($buildNumber)
- 包名：`$packageName`
''';
  }
}
