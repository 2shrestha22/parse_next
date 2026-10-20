// expect: ARGUMENT_TYPE_NOT_ASSIGNABLE
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Future<DateTime> f(Collection<Post, PostOps> posts) =>
    posts.update('id', (o) => [o.count.set('3')]);
