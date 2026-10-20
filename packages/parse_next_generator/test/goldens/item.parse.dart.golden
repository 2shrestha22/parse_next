// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'item.dart';

final class ItemFields extends Fields<Item> {
  const ItemFields();

  StringField<Item> get name => const StringField('name');
  StringField<Item> get note => const StringField('note');
  ComparableField<Item, int> get rank => const ComparableField('rank');
  ComparableField<Item, double> get score => const ComparableField('score');
  ComparableField<Item, DateTime> get at =>
      const ComparableField('happened_at', encodeDate);
  Field<Item, Kind> get kind => Field('kind', (v) => v.name);
  Field<Item, bool> get flag => const Field('flag');
  ListField<Item, String> get tags => const ListField('tags');
  PointerField<Item, User> get owner =>
      const PointerField('owner', $UserSchema());
  PointerListField<Item, User> get helpers =>
      PointerListField('helpers', const $UserSchema());
  GeoField<Item> get spot => const GeoField('spot');
  RelationField<Item, User> get fans =>
      const RelationField('fans', $ItemSchema());
}

final class ItemOps {
  const ItemOps();

  SetOps<String> get name => const SetOps('name');
  NullableSetOps<String> get note => const NullableSetOps('note');
  NumOps<int> get rank => const NumOps('rank');
  NullableNumOps<double> get score => const NullableNumOps('score');
  SetOps<DateTime> get at => const SetOps('happened_at', encodeDate);
  SetOps<Kind> get kind => SetOps('kind', (v) => v.name);
  SetOps<bool> get flag => const SetOps('flag');
  ListOps<String> get tags => const ListOps('tags');
  SetOps<Pointer<User>> get owner =>
      SetOps('owner', (v) => v.encode(const $UserSchema()));
  ListOps<Pointer<User>> get helpers =>
      ListOps('helpers', (v) => v.encode(const $UserSchema()));
  SetOps<GeoPoint> get spot => SetOps('spot', (v) => v.toJson());
  RelationOps<User> get fans => const RelationOps('fans', $UserSchema());
}

final class $ItemSchema implements ParseSchema<Item, ItemFields, ItemOps> {
  const $ItemSchema();

  @override
  String get className => 'Item';

  @override
  Item decode(Json json) => Item(
    name: json.require<String>('name'),
    note: json.opt<String>('note'),
    rank: json.require<int>('rank'),
    score: json.opt<double>('score'),
    at: json.require<DateTime>('happened_at'),
    kind: json.requireEnum('kind', Kind.values),
    flag: json.require<bool>('flag'),
    tags: json.requireList<String>('tags'),
    owner: json.requirePointer('owner', const $UserSchema()),
    helpers: json.requirePointerList('helpers', const $UserSchema()),
    spot: json.require<GeoPoint>('spot'),
    fans: json.relation('fans', const $UserSchema()),
  );

  @override
  Json encode(Item value) => Json({
    'name': value.name,
    'note': value.note,
    'rank': value.rank,
    'score': value.score,
    'happened_at': encodeDate(value.at),
    'kind': value.kind.name,
    'flag': value.flag,
    'tags': value.tags,
    'owner': value.owner.encode(const $UserSchema()),
    'helpers': [for (final p in value.helpers) p.encode(const $UserSchema())],
    'spot': value.spot.toJson(),
  });

  @override
  ItemFields get fields => const ItemFields();

  @override
  ItemOps get ops => const ItemOps();
}
