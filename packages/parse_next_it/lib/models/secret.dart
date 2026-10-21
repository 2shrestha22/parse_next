import 'package:parse_next/parse_next.dart';

part 'secret.parse.dart';

/// Only role_test writes it.
@ParseClass('Secret')
final class Secret {
  const Secret({required this.text});

  final String text;
}
