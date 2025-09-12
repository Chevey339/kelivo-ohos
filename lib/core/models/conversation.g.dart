// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final int typeId = 1;

  @override
  Conversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Conversation(
      id: fields[0] as String?,
      title: fields[1] as String,
      createdAt: fields[2] as DateTime?,
      updatedAt: fields[3] as DateTime?,
      messageIds: (fields[4] as List?)?.cast<String>(),
      isPinned: fields[5] as bool,
      mcpServerIds: (fields[6] as List?)?.cast<String>(),
      assistantId: fields[7] as String?,
      truncateIndex: (fields[8] as int?) ?? -1,
      versionSelections: (fields[9] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? <String, int>{},
    );
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.messageIds)
      ..writeByte(5)
      ..write(obj.isPinned)
      ..writeByte(6)
      ..write(obj.mcpServerIds)
      ..writeByte(7)
      ..write(obj.assistantId)
      ..writeByte(8)
      ..write(obj.truncateIndex)
      ..writeByte(9)
      ..write(obj.versionSelections);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
