import 'package:parse_next/parse_next.dart';

part 'user.parse.dart';

@ParseClass('_User')
final class User {
  const User({required this.username});

  final String username;
}
