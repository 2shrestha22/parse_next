// expect: RETURN_OF_INVALID_TYPE_FROM_CLOSURE
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Query<Post, PostFields, PostOps> f(
  Collection<Post, PostFields, PostOps> posts,
) => posts.query().include((f) => f.title);
