// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'role.dart';

final class RoleFields extends Fields<Role> {
  const RoleFields();

  StringField<Role> get name => const StringField('name');
  RelationField<Role, User> get users =>
      const RelationField('users', $RoleSchema(), $UserSchema());
  RelationField<Role, Role> get roles =>
      const RelationField('roles', $RoleSchema(), $RoleSchema());
}

final class RoleOps {
  const RoleOps();

  SetOps<String> get name => const SetOps('name');
  RelationOps<User> get users => const RelationOps('users', $UserSchema());
  RelationOps<Role> get roles => const RelationOps('roles', $RoleSchema());
}

final class $RoleSchema implements ParseSchema<Role, RoleFields, RoleOps> {
  const $RoleSchema();

  @override
  String get className => '_Role';

  @override
  Role decode(Json json) => Role(
    name: json.require<String>('name'),
    users: json.relation('users', const $UserSchema()),
    roles: json.relation('roles', const $RoleSchema()),
  );

  @override
  Json encode(Role value) => Json({'name': value.name});

  @override
  RoleFields get fields => const RoleFields();

  @override
  RoleOps get ops => const RoleOps();
}
