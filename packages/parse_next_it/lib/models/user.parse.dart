part of 'user.dart';

final class UserOps {
  const UserOps();

  SetOps<String> get username => const SetOps('username');
  NullableSetOps<String> get displayName =>
      const NullableSetOps('display_name');
  NullableNumOps<int> get karma => const NullableNumOps('karma');
}

final class $UserSchema implements ParseSchema<User, UserOps> {
  const $UserSchema();

  @override
  String get className => '_User';

  @override
  User decode(Json json) => User(
        username: json.require<String>('username'),
        displayName: json.opt<String>('display_name'),
        karma: json.opt<int>('karma'),
      );

  @override
  Json encode(User value) => Json({
        'username': value.username,
        'display_name': value.displayName,
        'karma': value.karma,
      });

  @override
  UserOps get ops => const UserOps();
}
