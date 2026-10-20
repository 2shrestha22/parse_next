part of 'note.dart';

final class NoteOps {
  const NoteOps();

  SetOps<String> get text => const SetOps('text');
  NullableSetOps<bool> get draft => const NullableSetOps('draft');
  NullableSetOps<GeoPoint> get place =>
      NullableSetOps('place', (v) => v.toJson());
}

final class $NoteSchema implements ParseSchema<Note, NoteOps> {
  const $NoteSchema();

  @override
  String get className => 'Note';

  @override
  Note decode(Json json) => Note(
        text: json.require<String>('text'),
        draft: json.opt<bool>('draft'),
        place: json.opt<GeoPoint>('place'),
      );

  @override
  Json encode(Note value) => Json({
        'text': value.text,
        'draft': value.draft,
        'place': value.place?.toJson(),
      });

  @override
  NoteOps get ops => const NoteOps();
}
