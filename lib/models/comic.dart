import 'package:hive/hive.dart';

part 'comic.g.dart';

@HiveType(typeId: 1)
class Comic extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String author;

  @HiveField(2)
  String coverUrl;

  @HiveField(3)
  String introduce;

  @HiveField(4)
  String kind;

  @HiveField(5)
  String lastChapter;

  @HiveField(6)
  String noteUrl;

  @HiveField(7)
  String sourceUrl;

  @HiveField(8)
  String sourceName;

  @HiveField(9)
  bool isFavorite;

  @HiveField(10)
  DateTime? updateTime;

  /// 所属自定义书架文件夹，空字符串表示「全部」（未归类）
  @HiveField(11)
  String folder;

  Comic({
    this.name = '',
    this.author = '',
    this.coverUrl = '',
    this.introduce = '',
    this.kind = '',
    this.lastChapter = '',
    this.noteUrl = '',
    this.sourceUrl = '',
    this.sourceName = '',
    this.isFavorite = false,
    this.updateTime,
    this.folder = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'author': author,
        'coverUrl': coverUrl,
        'introduce': introduce,
        'kind': kind,
        'lastChapter': lastChapter,
        'noteUrl': noteUrl,
        'sourceUrl': sourceUrl,
        'sourceName': sourceName,
        'isFavorite': isFavorite,
        'folder': folder,
      };
}

@HiveType(typeId: 2)
class Chapter extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String url;

  @HiveField(2)
  int index;

  Chapter({this.name = '', this.url = '', this.index = 0});
}
