// expect: NON_EXHAUSTIVE_SWITCH_EXPRESSION
import 'package:parse_next/parse_next.dart';

String name(LiveEvent<Object?> e) => switch (e) {
  Created() => 'created',
  Entered() => 'entered',
  Updated() => 'updated',
  Left() => 'left',
  Deleted() => 'deleted',
};
