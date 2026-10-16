import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/github_mirror.dart';
import '../core/updater.dart';

/// 更新流程所处的阶段
enum UpdatePhase {
  /// 尚未检查
  idle,

  /// 正在检查
  checking,

  /// 检测到新版本，等待用户下载
  available,

  /// 正在下载
  downloading,

  /// 已暂停（可续传）
  paused,

  /// 下载完成，等待安装
  ready,

  /// 下载或检查失败
  failed,
}

/// 安装动作的结果
class InstallResult {
  final bool ok;
  final String message;
  const InstallResult(this.ok, this.message);
}

/// 应用内更新中心：检查 → 更新说明 → 下载（可后台、可暂停、可续传）→ 安装。
///
/// 下载交给 background_downloader：Android 走系统前台服务、iOS 走后台 URLSession，
/// 因此退到后台甚至锁屏都会继续；应用被杀后重启也能按 taskId 从插件数据库恢复进度。
class UpdateService extends ChangeNotifier {
  static const String group = 'comicRealmUpdate';

  final Updater updater;

  UpdateService({Updater? updater})
      : updater = updater ?? Updater(owner: '2016YYy', repo: 'comic-realm') {
    _listen();
    _restore();
  }

  AppUpdate? _update;
  UpdatePhase _phase = UpdatePhase.idle;
  double _progress = 0;
  int _receivedBytes = 0;
  int _expectedBytes = 0;
  double _speed = 0;
  Duration? _remaining;
  String? _error;
  String? _filePath;
  DateTime? _lastCheckedAt;

  /// 下载候选地址（直连 + 镜像），失败时按顺序回退。
  List<String> _downloadCandidates = [];
  int _candidateIndex = 0;
  bool _switchingMirror = false;

  StreamSubscription<TaskUpdate>? _sub;
  bool _disposed = false;

  AppUpdate? get update => _update;
  UpdatePhase get phase => _phase;
  double get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get expectedBytes => _expectedBytes;
  double get speedMBps => _speed;
  Duration? get remaining => _remaining;
  String? get error => _error;
  String? get filePath => _filePath;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// 当前所用下载地址是否为镜像（非 GitHub 直链）时返回镜像名，否则 null。
  String? get mirrorName {
    if (_downloadCandidates.isEmpty ||
        _candidateIndex < 0 ||
        _candidateIndex >= _downloadCandidates.length) {
      return null;
    }
    final url = _downloadCandidates[_candidateIndex];
    final target = _update?.downloadUrl;
    if (target == null || url == target) return null;
    final uri = Uri.tryParse(url);
    return uri?.host;
  }

  /// 检测到比当前更高的版本
  bool get hasUpdate => _update?.isNewer == true;

  bool get isDownloading => _phase == UpdatePhase.downloading;
  bool get isPaused => _phase == UpdatePhase.paused;
  bool get isReady => _phase == UpdatePhase.ready;
  bool get isChecking => _phase == UpdatePhase.checking;

  /// 本机平台有没有可用的安装包直链
  bool get hasDownloadableAsset =>
      _update != null && _update!.downloadUrl.isNotEmpty;

  String get phaseLabel {
    switch (_phase) {
      case UpdatePhase.idle:
        return '未检查';
      case UpdatePhase.checking:
        return '正在检查更新…';
      case UpdatePhase.available:
        return hasDownloadableAsset ? '可下载更新' : '当前平台无安装包';
      case UpdatePhase.downloading:
        return '正在下载 ${(_progress * 100).toStringAsFixed(1)}%';
      case UpdatePhase.paused:
        return '已暂停，可继续下载';
      case UpdatePhase.ready:
        return '下载完成，可安装';
      case UpdatePhase.failed:
        return _error ?? '下载失败';
    }
  }

  static String taskIdFor(String version) => 'comicRealmUpdate-$version';

  /// 在 `main()` 中调用一次：配置后台下载通知，并接管上次未完成的任务。
  static Future<void> configureBackground() async {
    if (kIsWeb) return;
    final downloader = FileDownloader();
    downloader.configureNotificationForGroup(
      group,
      running: const TaskNotification('正在下载更新包', '已完成 {progress}'),
      complete: const TaskNotification('更新包下载完成', '点击安装新版本'),
      error: const TaskNotification('更新包下载失败', '可回到应用内重试'),
      paused: const TaskNotification('更新包已暂停', '回到应用内可继续下载'),
      progressBar: true,
      tapOpensFile: true,
    );
    await downloader.start(autoCleanDatabase: true);
  }

  // ---------------- 检查 ----------------

  /// 检查更新。
  /// [silent] 为 true 时不改变可下载状态，仅用于启动后的静默检查。
  /// 用户已「忽略此版本」时静默检查会跳过提示。
  /// [includePrerelease] 为 true 时包含预发布版本。
  Future<bool> checkForUpdate({
    bool silent = false,
    String skippedVersion = '',
    bool includePrerelease = false,
  }) async {
    if (!silent) {
      _phase = UpdatePhase.checking;
      _error = null;
      _notify();
    }
    final result = await updater.checkUpdate(includePrerelease: includePrerelease);
    _lastCheckedAt = DateTime.now();

    if (result == null) {
      _phase = UpdatePhase.failed;
      _error = '无法获取版本信息，请检查网络后重试';
      _notify();
      return false;
    }

    _update = result;
    if (result.isNewer && result.version != skippedVersion) {
      // 若本地已有该版本的成品文件，直接进入可安装状态
      final restored = await _restore();
      _phase = restored ? UpdatePhase.ready : UpdatePhase.available;
      _notify();
      return true;
    }

    _phase = UpdatePhase.idle;
    _error = null;
    _notify();
    return false;
  }

  // ---------------- 下载 ----------------

  /// 开始下载更新包（后台进行）
  Future<void> startDownload() async {
    final target = _update;
    if (target == null || target.downloadUrl.isEmpty) {
      _phase = UpdatePhase.failed;
      _error = '当前平台没有可用的安装包，请到 Release 页面手动下载';
      _notify();
      return;
    }

    // Android 13+ 通知权限：缺少它时下载仍可进行，只是看不到进度通知
    if (AppUpdate.isAndroid) {
      try {
        await FileDownloader().permissions.request(PermissionType.notifications);
      } catch (_) {}
    }

    _error = null;
    _progress = 0;
    _receivedBytes = 0;

    // 生成候选地址（直连 + 各镜像），并发测速后把最快的放到队首。
    _downloadCandidates = GithubMirror.candidates(target.downloadUrl);
    _candidateIndex = 0;
    final fastest = await GithubMirror.pickFastest(_downloadCandidates);
    if (fastest != null) {
      final idx = _downloadCandidates.indexOf(fastest);
      if (idx > 0) {
        _downloadCandidates.insert(0, _downloadCandidates.removeAt(idx));
      }
    }

    await _enqueueCandidate(target);
  }

  /// 用当前候选地址创建下载任务。
  Future<void> _enqueueCandidate(AppUpdate target) async {
    final url = _downloadCandidates.isNotEmpty
        ? _downloadCandidates[_candidateIndex]
        : target.downloadUrl;

    _error = null;

    final task = DownloadTask(
      taskId: taskIdFor(target.version),
      url: url,
      filename: target.fileName,
      directory: 'updates',
      baseDirectory: BaseDirectory.applicationSupport,
      group: group,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      displayName: '漫境 v${target.version}',
      metaData: target.version,
    );

    final ok = await FileDownloader().enqueue(task);
    if (!ok) {
      // 已存在完全相同的任务时 enqueue 返回 false，属于正常情况
      final record = await FileDownloader().database.recordForId(task.taskId);
      if (record != null) {
        _applyStatus(record.status, record.exception);
        _progress = record.progress.clamp(0, 1);
        _notify();
        return;
      }
      _phase = UpdatePhase.failed;
      _error = '无法创建下载任务';
      _notify();
      return;
    }
    _phase = UpdatePhase.downloading;
    _notify();
  }

  Future<void> pause() async {
    final version = _update?.version;
    if (version == null) return;
    final task = await FileDownloader().taskForId(taskIdFor(version));
    if (task is DownloadTask) {
      await FileDownloader().pause(task);
      _phase = UpdatePhase.paused;
      _notify();
    }
  }

  Future<void> resume() async {
    final version = _update?.version;
    if (version == null) return;
    final task = await FileDownloader().taskForId(taskIdFor(version));
    if (task is DownloadTask) {
      final ok = await FileDownloader().resume(task);
      _phase = ok ? UpdatePhase.downloading : UpdatePhase.failed;
      if (!ok) _error = '续传失败，请重新下载';
      _notify();
    }
  }

  Future<void> cancel() async {
    final version = _update?.version;
    if (version == null) return;
    await FileDownloader().cancelTasksWithIds([taskIdFor(version)]);
    _phase = UpdatePhase.available;
    _progress = 0;
    _receivedBytes = 0;
    _filePath = null;
    _downloadCandidates = [];
    _candidateIndex = 0;
    _notify();
  }

  // ---------------- 安装 ----------------

  Future<InstallResult> install() async {
    // 若文件路径尚未解析（下载刚完成时可能存在时序问题），重新解析一次
    if (_filePath == null || _filePath!.isEmpty) {
      await _resolveFilePath();
    }
    final path = _filePath;
    if (path == null || path.isEmpty) {
      return const InstallResult(false, '安装包尚未下载完成，请稍后重试');
    }
    if (!await File(path).exists()) {
      _filePath = null;
      _phase = UpdatePhase.available;
      _notify();
      return const InstallResult(false, '安装包已不存在，请重新下载');
    }

    if (AppUpdate.isAndroid) {
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      return switch (result.type) {
        ResultType.done => const InstallResult(true, '已调起系统安装界面'),
        ResultType.permissionDenied =>
          const InstallResult(false, '请允许「安装未知应用」后重试'),
        ResultType.noAppToOpen =>
          const InstallResult(false, '系统未找到可处理安装包的应用'),
        ResultType.fileNotFound =>
          const InstallResult(false, '安装包已不存在，请重新下载'),
        ResultType.error => InstallResult(false, '安装失败：${result.message}'),
      };
    }

    if (AppUpdate.isIOS) {
      // iOS 免签名 ipa 无法在设备内自装，引导到 Release 页面
      return const InstallResult(false, 'iOS 需通过 AltStore / 自签工具安装，请到 Release 页面下载');
    }

    final result = await OpenFilex.open(path);
    return result.type == ResultType.done
        ? const InstallResult(true, '已打开安装包')
        : InstallResult(false, '打开失败：${result.message}');
  }

  /// 打开发布页面（手动下载兜底）
  Future<bool> openReleasePage() async {
    final url = _update?.releasePageUrl;
    if (url == null || url.isEmpty) return false;
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ---------------- 内部 ----------------

  void _listen() {
    if (kIsWeb) return;
    _sub = FileDownloader().updates.listen((update) async {
      final version = _update?.version;
      if (version == null) return;
      if (update.task.taskId != taskIdFor(version)) return;

      if (update is TaskProgressUpdate) {
        if (update.progress >= 0) {
          _progress = update.progress.clamp(0.0, 1.0);
        }
        if (update.expectedFileSize > 0) {
          _expectedBytes = update.expectedFileSize;
        }
        _receivedBytes = (_expectedBytes * _progress).round();
        _speed = update.networkSpeed > 0 ? update.networkSpeed : 0;
        _remaining = update.timeRemaining.inSeconds >= 0 ? update.timeRemaining : null;
        if (_phase != UpdatePhase.paused && _phase != UpdatePhase.ready) {
          _phase = UpdatePhase.downloading;
        }
        _notify();
        return;
      }

      if (update is TaskStatusUpdate) {
        // 镜像回退过程中主动取消旧任务，忽略其 canceled 事件，避免状态被覆盖。
        if (update.status == TaskStatus.canceled && _switchingMirror) {
          return;
        }
        _applyStatus(update.status, update.exception);
        if (update.status == TaskStatus.complete) {
          _progress = 1;
          await _resolveFilePath();
        } else if ((update.status == TaskStatus.failed ||
                update.status == TaskStatus.notFound) &&
            _candidateIndex + 1 < _downloadCandidates.length) {
          // 当前镜像下载失败：自动切换到下一个候选地址重试。
          final target = _update;
          if (target != null) {
            _candidateIndex++;
            _progress = 0;
            _receivedBytes = 0;
            _switchingMirror = true;
            try {
              await FileDownloader()
                  .cancelTasksWithIds([taskIdFor(target.version)]);
              await _enqueueCandidate(target);
            } finally {
              _switchingMirror = false;
            }
            return;
          }
        }
        _notify();
      }
    }, onError: (_) {});
  }

  void _applyStatus(TaskStatus status, TaskException? exception) {
    switch (status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
        _phase = UpdatePhase.downloading;
        _error = null;
      case TaskStatus.complete:
        _phase = UpdatePhase.ready;
        _error = null;
      case TaskStatus.paused:
        _phase = UpdatePhase.paused;
      case TaskStatus.canceled:
        _phase = UpdatePhase.available;
        _progress = 0;
      case TaskStatus.failed:
      case TaskStatus.notFound:
        _phase = UpdatePhase.failed;
        _error = exception?.description ?? '下载失败，请重试';
      case TaskStatus.waitingToRetry:
        _phase = UpdatePhase.downloading;
        _error = '网络异常，正在自动重试…';
    }
  }

  /// 从插件数据库恢复上次的下载状态（应用重启 / 从后台回来时调用）
  Future<bool> _restore() async {
    if (kIsWeb) return false;
    final version = _update?.version;
    if (version == null) return false;
    try {
      final record = await FileDownloader().database.recordForId(taskIdFor(version));
      if (record == null) return false;

      _progress = record.progress.clamp(0.0, 1.0);
      _expectedBytes = record.expectedFileSize > 0 ? record.expectedFileSize : 0;
      _receivedBytes = (_expectedBytes * _progress).round();
      _applyStatus(record.status, record.exception);

      if (record.status == TaskStatus.complete) {
        final path = await _resolveFilePath();
        return path != null;
      }
      _notify();
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 解析已下载文件的本地绝对路径（多种方式兜底，确保可靠性）
  Future<String?> _resolveFilePath() async {
    final version = _update?.version;
    final fileName = _update?.fileName;
    if (version == null) return null;

    // 方式一：从下载任务对象获取
    try {
      final task = await FileDownloader().taskForId(taskIdFor(version));
      if (task != null) {
        final path = await task.filePath();
        if (path.isNotEmpty && await File(path).exists()) {
          _filePath = path;
          return path;
        }
      }
    } catch (_) {}

    // 方式二：从数据库记录获取
    try {
      final record = await FileDownloader().database.recordForId(taskIdFor(version));
      if (record != null) {
        // 尝试用 record 的 task 重新获取路径
      }
    } catch (_) {}

    // 方式三：手动拼接路径（applicationSupport/updates/<filename>）
    if (fileName != null && fileName.isNotEmpty) {
      try {
        final dir = await getApplicationSupportDirectory();
        final path = '${dir.path}/updates/$fileName';
        if (await File(path).exists()) {
          _filePath = path;
          return path;
        }
      } catch (_) {}
    }

    return _filePath;
  }

  /// 应用从后台回到前台时刷新进度
  Future<void> refreshFromBackground() async {
    await _restore();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
