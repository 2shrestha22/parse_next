// expect: UNDEFINED_METHOD
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Future<DateTime> f(Collection<Post, PostFields, PostOps> posts) =>
    posts.update('id', (o) => [o.title.increment(1)]);
