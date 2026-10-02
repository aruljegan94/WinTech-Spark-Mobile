// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ShopSettingsAdapter extends TypeAdapter<ShopSettings> {
  @override
  final int typeId = 10;

  @override
  ShopSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ShopSettings(
      shopName: fields[0] as String,
      location: fields[1] as String,
      invoicePrefix: fields[2] as String,
      invoiceSuffix: fields[3] as String,
      invoiceCounter: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ShopSettings obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.shopName)
      ..writeByte(1)
      ..write(obj.location)
      ..writeByte(2)
      ..write(obj.invoicePrefix)
      ..writeByte(3)
      ..write(obj.invoiceSuffix)
      ..writeByte(4)
      ..write(obj.invoiceCounter);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
