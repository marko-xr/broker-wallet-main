// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorites_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CachedFavoriteItemAdapter extends TypeAdapter<CachedFavoriteItem> {
  @override
  final int typeId = 1;

  @override
  CachedFavoriteItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CachedFavoriteItem(
      id: fields[0] as String,
      type: fields[1] as String,
      title: fields[2] as String,
      subtitle: fields[3] as String,
      imageUrl: fields[4] as String?,
      thumbnailUrl: fields[5] as String?,
      addedAt: fields[6] as DateTime,
      cachedAt: fields[7] as DateTime,
      entityData: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CachedFavoriteItem obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.subtitle)
      ..writeByte(4)
      ..write(obj.imageUrl)
      ..writeByte(5)
      ..write(obj.thumbnailUrl)
      ..writeByte(6)
      ..write(obj.addedAt)
      ..writeByte(7)
      ..write(obj.cachedAt)
      ..writeByte(8)
      ..write(obj.entityData);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedFavoriteItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
