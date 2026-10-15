// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ComicSourceAdapter extends TypeAdapter<ComicSource> {
  @override
  final int typeId = 0;

  @override
  ComicSource read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ComicSource(
      bookSourceUrl: fields[0] as String,
      bookSourceName: fields[1] as String,
      bookSourceGroup: fields[2] as String,
      bookSourceType: fields[3] as String,
      httpUserAgent: fields[4] as String,
      ruleSearchUrl: fields[5] as String,
      ruleSearchList: fields[6] as String,
      ruleSearchName: fields[7] as String,
      ruleSearchAuthor: fields[8] as String,
      ruleSearchCoverUrl: fields[9] as String,
      ruleSearchNoteUrl: fields[10] as String,
      ruleBookName: fields[11] as String,
      ruleCoverUrl: fields[12] as String,
      ruleBookAuthor: fields[13] as String,
      ruleBookKind: fields[14] as String,
      ruleIntroduce: fields[15] as String,
      ruleChapterList: fields[16] as String,
      ruleChapterName: fields[17] as String,
      ruleContentUrl: fields[18] as String,
      ruleChapterUrl: fields[24] as String,
      ruleBookContent: fields[19] as String,
      ruleFindUrl: fields[20] as String,
      enable: fields[21] as bool,
      sourceRemark: fields[22] as String,
      weight: fields[23] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ComicSource obj) {
    writer
      ..writeByte(25)
      ..writeByte(0)
      ..write(obj.bookSourceUrl)
      ..writeByte(1)
      ..write(obj.bookSourceName)
      ..writeByte(2)
      ..write(obj.bookSourceGroup)
      ..writeByte(3)
      ..write(obj.bookSourceType)
      ..writeByte(4)
      ..write(obj.httpUserAgent)
      ..writeByte(5)
      ..write(obj.ruleSearchUrl)
      ..writeByte(6)
      ..write(obj.ruleSearchList)
      ..writeByte(7)
      ..write(obj.ruleSearchName)
      ..writeByte(8)
      ..write(obj.ruleSearchAuthor)
      ..writeByte(9)
      ..write(obj.ruleSearchCoverUrl)
      ..writeByte(10)
      ..write(obj.ruleSearchNoteUrl)
      ..writeByte(11)
      ..write(obj.ruleBookName)
      ..writeByte(12)
      ..write(obj.ruleCoverUrl)
      ..writeByte(13)
      ..write(obj.ruleBookAuthor)
      ..writeByte(14)
      ..write(obj.ruleBookKind)
      ..writeByte(15)
      ..write(obj.ruleIntroduce)
      ..writeByte(16)
      ..write(obj.ruleChapterList)
      ..writeByte(17)
      ..write(obj.ruleChapterName)
      ..writeByte(18)
      ..write(obj.ruleContentUrl)
      ..writeByte(24)
      ..write(obj.ruleChapterUrl)
      ..writeByte(19)
      ..write(obj.ruleBookContent)
      ..writeByte(20)
      ..write(obj.ruleFindUrl)
      ..writeByte(21)
      ..write(obj.enable)
      ..writeByte(22)
      ..write(obj.sourceRemark)
      ..writeByte(23)
      ..write(obj.weight);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
