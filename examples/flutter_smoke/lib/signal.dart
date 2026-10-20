import 'package:parse_next/parse_next.dart';

part 'signal.parse.dart';

@ParseClass('Signal')
final class Signal {
  const Signal({required this.name, required this.points});

  final String name;
  final int points;
}
