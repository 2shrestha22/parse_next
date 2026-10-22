// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'tally.dart';

final class TallyFields extends Fields<Tally> {
  const TallyFields();

  StringField<Tally> get tag => const StringField('tag');
  ComparableField<Tally, int> get n => const ComparableField('n');
}

final class TallyOps {
  const TallyOps();

  SetOps<String> get tag => const SetOps('tag');
  NumOps<int> get n => const NumOps('n');
}

final class $TallySchema implements ParseSchema<Tally, TallyFields, TallyOps> {
  const $TallySchema();

  @override
  String get className => 'Tally';

  @override
  Tally decode(Json json) =>
      Tally(tag: json.require<String>('tag'), n: json.require<int>('n'));

  @override
  Json encode(Tally value) => Json({'tag': value.tag, 'n': value.n});

  @override
  TallyFields get fields => const TallyFields();

  @override
  TallyOps get ops => const TallyOps();
}
