// expect: ARGUMENT_TYPE_NOT_ASSIGNABLE
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Query<Post, PostFields, PostOps> f(
  Collection<Post, PostFields, PostOps> posts,
) => posts.where((f) => f.count.gt('3'));
