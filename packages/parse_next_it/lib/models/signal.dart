import 'package:parse_next/parse_next.dart';

part 'signal.parse.dart';

/// The only class in the servers' `liveQuery.classNames`.
@ParseClass('Signal')
final class Signal {
  const Signal({
    required this.name,
    this.points,
    this.label,
    this.tags,
    this.at,
    this.place,
    this.links,
  });

  final String name;
  final int? points;
  final String? label;
  final List<String>? tags;
  final DateTime? at;
  final GeoPoint? place;
  final List<Pointer<Signal>>? links;
}
