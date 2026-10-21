// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'signal.dart';

final class SignalFields extends Fields<Signal> {
  const SignalFields();

  StringField<Signal> get name => const StringField('name');
  ComparableField<Signal, int> get points => const ComparableField('points');
  StringField<Signal> get label => const StringField('label');
  ListField<Signal, String> get tags => const ListField('tags');
  DateField<Signal> get at => const DateField('at');
  GeoField<Signal> get place => const GeoField('place');
  PointerListField<Signal, Signal, SignalFields> get links =>
      PointerListField('links', const $SignalSchema());
  FileField<Signal> get file => const FileField('file');
}

final class SignalOps {
  const SignalOps();

  SetOps<String> get name => const SetOps('name');
  NullableNumOps<int> get points => const NullableNumOps('points');
  NullableSetOps<String> get label => const NullableSetOps('label');
  NullableListOps<String> get tags => const NullableListOps('tags');
  NullableSetOps<DateTime> get at => const NullableSetOps('at', encodeDate);
  NullableSetOps<GeoPoint> get place =>
      NullableSetOps('place', (v) => v.toJson());
  NullableListOps<Pointer<Signal>> get links =>
      NullableListOps('links', (v) => v.encode(const $SignalSchema()));
  NullableSetOps<ParseFile> get file =>
      NullableSetOps('file', (v) => v.toJson());
}

final class $SignalSchema
    implements ParseSchema<Signal, SignalFields, SignalOps> {
  const $SignalSchema();

  @override
  String get className => 'Signal';

  @override
  Signal decode(Json json) => Signal(
    name: json.require<String>('name'),
    points: json.opt<int>('points'),
    label: json.opt<String>('label'),
    tags: json.optList<String>('tags'),
    at: json.opt<DateTime>('at'),
    place: json.opt<GeoPoint>('place'),
    links: json.optPointerList('links', const $SignalSchema()),
    file: json.opt<ParseFile>('file'),
  );

  @override
  Json encode(Signal value) => Json({
    'name': value.name,
    'points': value.points,
    'label': value.label,
    'tags': value.tags,
    'at': value.at == null ? null : encodeDate(value.at!),
    'place': value.place?.toJson(),
    'links': value.links == null
        ? null
        : [for (final p in value.links!) p.encode(const $SignalSchema())],
    'file': value.file?.toJson(),
  });

  @override
  SignalFields get fields => const SignalFields();

  @override
  SignalOps get ops => const SignalOps();
}
