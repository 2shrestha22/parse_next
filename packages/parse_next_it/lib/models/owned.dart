import 'package:parse_next/parse_next.dart';

import 'user.dart';

part 'owned.parse.dart';

/// How the afterSave trigger in cloud/main.js reaches the users it points to.
enum Touch { save, fetchThenSave }

@ParseClass('Owned')
final class Owned {
  const Owned({
    required this.owner,
    required this.helpers,
    required this.touch,
  });

  final Pointer<User> owner;
  final List<Pointer<User>> helpers;
  final Touch touch;
}
