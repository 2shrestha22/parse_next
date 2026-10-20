// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'user.dart';

final class UserFields extends Fields<User> {
  const UserFields();

  StringField<User> get username => const StringField('username');
  StringField<User> get displayName => const StringField('display_name');
  ComparableField<User, int> get karma => const ComparableField('karma');
  StringField<User> get email => const StringField('email');
}

final class UserOps {
  const UserOps();

  SetOps<String> get username => const SetOps('username');
  NullableSetOps<String> get displayName =>
      const NullableSetOps('display_name');
  NullableNumOps<int> get karma => const NullableNumOps('karma');
  NullableSetOps<String> get email => const NullableSetOps('email');
}

final class $UserSchema implements ParseSchema<User, UserFields, UserOps> {
  const $UserSchema();

  @override
  String get className => '_User';

  @override
  User decode(Json json) => User(
    username: json.require<String>('username'),
    displayName: json.opt<String>('display_name'),
    karma: json.opt<int>('karma'),
    email: json.opt<String>('email'),
  );

  @override
  Json encode(User value) => Json({
    'username': value.username,
    'display_name': value.displayName,
    'karma': value.karma,
    'email': value.email,
  });

  @override
  UserFields get fields => const UserFields();

  @override
  UserOps get ops => const UserOps();
}
