// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'user.dart';

final class UserFields extends Fields<User> {
  const UserFields();

  StringField<User> get username => const StringField('username');
}

final class UserOps {
  const UserOps();

  SetOps<String> get username => const SetOps('username');
}

final class $UserSchema implements ParseSchema<User, UserFields, UserOps> {
  const $UserSchema();

  @override
  String get className => '_User';

  @override
  User decode(Json json) => User(username: json.require<String>('username'));

  @override
  Json encode(User value) => Json({'username': value.username});

  @override
  UserFields get fields => const UserFields();

  @override
  UserOps get ops => const UserOps();
}
