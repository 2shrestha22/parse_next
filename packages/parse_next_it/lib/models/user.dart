import 'package:parse_next/parse_next.dart';

part 'user.parse.dart';

final class User {
  const User({required this.username, this.displayName, this.karma});

  final String username;
  final String? displayName;
  final int? karma;
}
