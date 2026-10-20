// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'memo.dart';

final class MemoFields extends Fields<Memo> {
  const MemoFields();

  StringField<Memo> get text => const StringField('text');
  DateField<Memo> get dueAt => const DateField('due_at');
  ListField<Memo, String> get tags => const ListField('tags');
  Field<Memo, Mood> get mood => Field('mood', (v) => v.name);
}

final class MemoOps {
  const MemoOps();

  SetOps<String> get text => const SetOps('text');
  NullableSetOps<DateTime> get dueAt =>
      const NullableSetOps('due_at', encodeDate);
  ListOps<String> get tags => const ListOps('tags');
  NullableSetOps<Mood> get mood => NullableSetOps('mood', (v) => v.name);
}

final class $MemoSchema implements ParseSchema<Memo, MemoFields, MemoOps> {
  const $MemoSchema();

  @override
  String get className => 'Memo';

  @override
  Memo decode(Json json) => Memo(
    text: json.require<String>('text'),
    dueAt: json.opt<DateTime>('due_at'),
    tags: json.requireList<String>('tags'),
    mood: json.optEnum('mood', Mood.values),
  );

  @override
  Json encode(Memo value) => Json({
    'text': value.text,
    'due_at': value.dueAt == null ? null : encodeDate(value.dueAt!),
    'tags': value.tags,
    'mood': value.mood?.name,
  });

  @override
  MemoFields get fields => const MemoFields();

  @override
  MemoOps get ops => const MemoOps();
}
