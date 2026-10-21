import 'package:parse_next/parse_next.dart';

import 'user.dart';

part 'role.parse.dart';

@ParseClass('_Role')
final class Role {
  const Role({
    required this.name,
    this.users = const Relation(),
    this.roles = const Relation(),
  });

  final String name;
  final Relation<User> users;

  /// Roles whose users get this role's access too.
  final Relation<Role> roles;
}
