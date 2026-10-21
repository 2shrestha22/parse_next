// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'note.dart';

final class NoteFields extends Fields<Note> {
  const NoteFields();

  StringField<Note> get text => const StringField('text');
  Field<Note, bool> get draft => const Field('draft');
  GeoField<Note> get place => const GeoField('place');
  FileField<Note> get attachment => const FileField('attachment');
}

final class NoteOps {
  const NoteOps();

  SetOps<String> get text => const SetOps('text');
  NullableSetOps<bool> get draft => const NullableSetOps('draft');
  NullableSetOps<GeoPoint> get place =>
      NullableSetOps('place', (v) => v.toJson());
  NullableSetOps<ParseFile> get attachment =>
      NullableSetOps('attachment', (v) => v.toJson());
}

final class $NoteSchema implements ParseSchema<Note, NoteFields, NoteOps> {
  const $NoteSchema();

  @override
  String get className => 'Note';

  @override
  Note decode(Json json) => Note(
    text: json.require<String>('text'),
    draft: json.opt<bool>('draft'),
    place: json.opt<GeoPoint>('place'),
    attachment: json.opt<ParseFile>('attachment'),
  );

  @override
  Json encode(Note value) => Json({
    'text': value.text,
    'draft': value.draft,
    'place': value.place?.toJson(),
    'attachment': value.attachment?.toJson(),
  });

  @override
  NoteFields get fields => const NoteFields();

  @override
  NoteOps get ops => const NoteOps();
}
