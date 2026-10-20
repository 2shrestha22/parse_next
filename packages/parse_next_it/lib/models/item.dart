import 'package:parse_next/parse_next.dart';

import 'user.dart';

part 'item.parse.dart';

enum Kind { red, green, blue }

final class Item {
  const Item({
    required this.name,
    this.note,
    required this.rank,
    this.score,
    required this.at,
    required this.kind,
    required this.flag,
    required this.tags,
    required this.owner,
    required this.helpers,
    required this.spot,
    this.fans = const Relation(),
  });

  final String name;
  final String? note;
  final int rank;
  final double? score;
  final DateTime at;
  final Kind kind;
  final bool flag;
  final List<String> tags;
  final Pointer<User> owner;
  final List<Pointer<User>> helpers;
  final GeoPoint spot;
  final Relation<User> fans;
}
