// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadTaskAdapter extends TypeAdapter<DownloadTask> {
  @override
  final int typeId = 3;

  @override
  DownloadTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadTask(
      taskId: fields[0] as String,
      comicName: fields[1] as String,
      chapterName: fields[2] as String,
      chapterUrl: fields[3] as String,
      sourceUrl: fields[4] as String,
      sourceName: fields[5] as String,
      coverUrl: fields[6] as String,
      totalPages: fields[7] as int,
      downloadedPages: fields[8] as int,
      status: fields[9] as int,
      savePath: fields[10] as String,
      createTime: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadTask obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.taskId)
      ..writeByte(1)
      ..write(obj.comicName)
      ..writeByte(2)
      ..write(obj.chapterName)
      ..writeByte(3)
      ..write(obj.chapterUrl)
      ..writeByte(4)
      ..write(obj.sourceUrl)
      ..writeByte(5)
      ..write(obj.sourceName)
      ..writeByte(6)
      ..write(obj.coverUrl)
      ..writeByte(7)
      ..write(obj.totalPages)
      ..writeByte(8)
      ..write(obj.downloadedPages)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.savePath)
      ..writeByte(11)
      ..write(obj.createTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
