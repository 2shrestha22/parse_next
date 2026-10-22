import 'package:parse_next/parse_next.dart';

part 'tally.parse.dart';

/// Only master_test writes it.
@ParseClass('Tally')
final class Tally {
  const Tally({required this.tag, required this.n});

  final String tag;
  final int n;
}
