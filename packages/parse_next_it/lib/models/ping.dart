import 'package:parse_next/parse_next.dart';

part 'ping.parse.dart';

/// Only transport_test writes it.
@ParseClass('Ping')
final class Ping {
  const Ping({required this.name});

  final String name;
}
