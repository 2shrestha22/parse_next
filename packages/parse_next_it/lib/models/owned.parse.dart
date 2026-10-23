// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'owned.dart';

final class OwnedFields extends Fields<Owned> {
  const OwnedFields();

  PointerField<Owned, User, UserFields> get owner =>
      const PointerField('owner', $UserSchema());
  PointerListField<Owned, User, UserFields> get helpers =>
      PointerListField('helpers', const $UserSchema());
  Field<Owned, Touch> get touch => Field('touch', (v) => v.name);
}

final class OwnedOps {
  const OwnedOps();

  SetOps<Pointer<User>> get owner =>
      SetOps('owner', (v) => v.encode(const $UserSchema()));
  ListOps<Pointer<User>> get helpers =>
      ListOps('helpers', (v) => v.encode(const $UserSchema()));
  SetOps<Touch> get touch => SetOps('touch', (v) => v.name);
}

final class $OwnedSchema implements ParseSchema<Owned, OwnedFields, OwnedOps> {
  const $OwnedSchema();

  @override
  String get className => 'Owned';

  @override
  Owned decode(Json json) => Owned(
    owner: json.requirePointer('owner', const $UserSchema()),
    helpers: json.requirePointerList('helpers', const $UserSchema()),
    touch: json.requireEnum('touch', Touch.values),
  );

  @override
  Json encode(Owned value) => Json({
    'owner': value.owner.encode(const $UserSchema()),
    'helpers': [for (final p in value.helpers) p.encode(const $UserSchema())],
    'touch': value.touch.name,
  });

  @override
  OwnedFields get fields => const OwnedFields();

  @override
  OwnedOps get ops => const OwnedOps();
}
