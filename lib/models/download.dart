import 'package:hive/hive.dart';

part 'download.g.dart';

enum DownloadStatus { pending, downloading, completed, failed, paused }

@HiveType(typeId: 3)
class DownloadTask extends HiveObject {
  @HiveField(0)
  String taskId;

  @HiveField(1)
  String comicName;

  @HiveField(2)
  String chapterName;

  @HiveField(3)
  String chapterUrl;

  @HiveField(4)
  String sourceUrl;

  @HiveField(5)
  String sourceName;

  @HiveField(6)
  String coverUrl;

  @HiveField(7)
  int totalPages;

  @HiveField(8)
  int downloadedPages;

  @HiveField(9)
  int status; // DownloadStatus index

  @HiveField(10)
  String savePath;

  @HiveField(11)
  DateTime createTime;

  DownloadTask({
    required this.taskId,
    this.comicName = '',
    this.chapterName = '',
    this.chapterUrl = '',
    this.sourceUrl = '',
    this.sourceName = '',
    this.coverUrl = '',
    this.totalPages = 0,
    this.downloadedPages = 0,
    this.status = 0,
    this.savePath = '',
    DateTime? createTime,
  }) : createTime = createTime ?? DateTime.now();

  DownloadStatus get statusEnum => DownloadStatus.values[status.clamp(0, DownloadStatus.values.length - 1)];
  set statusEnum(DownloadStatus s) => status = s.index;

  double get progress => totalPages == 0 ? 0 : downloadedPages / totalPages;
}
