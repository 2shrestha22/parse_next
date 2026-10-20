import 'package:parse_next/parse_next.dart';

part 'user.parse.dart';

@ParseClass('_User')
final class User {
  const User({
    required this.username,
    @ParseKey('display_name') this.displayName,
    this.karma,
  });

  final String username;
  final String? displayName;
  final int? karma;
}
