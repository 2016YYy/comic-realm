// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comic.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ComicAdapter extends TypeAdapter<Comic> {
  @override
  final int typeId = 1;

  @override
  Comic read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Comic(
      name: fields[0] as String,
      author: fields[1] as String,
      coverUrl: fields[2] as String,
      introduce: fields[3] as String,
      kind: fields[4] as String,
      lastChapter: fields[5] as String,
      noteUrl: fields[6] as String,
      sourceUrl: fields[7] as String,
      sourceName: fields[8] as String,
      isFavorite: fields[9] as bool,
      updateTime: fields[10] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Comic obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.author)
      ..writeByte(2)
      ..write(obj.coverUrl)
      ..writeByte(3)
      ..write(obj.introduce)
      ..writeByte(4)
      ..write(obj.kind)
      ..writeByte(5)
      ..write(obj.lastChapter)
      ..writeByte(6)
      ..write(obj.noteUrl)
      ..writeByte(7)
      ..write(obj.sourceUrl)
      ..writeByte(8)
      ..write(obj.sourceName)
      ..writeByte(9)
      ..write(obj.isFavorite)
      ..writeByte(10)
      ..write(obj.updateTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChapterAdapter extends TypeAdapter<Chapter> {
  @override
  final int typeId = 2;

  @override
  Chapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Chapter(
      name: fields[0] as String,
      url: fields[1] as String,
      index: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Chapter obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.index);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
