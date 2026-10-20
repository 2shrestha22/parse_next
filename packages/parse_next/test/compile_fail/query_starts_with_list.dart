// expect: UNDEFINED_METHOD
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Query<Post, PostFields, PostOps> f(
        Collection<Post, PostFields, PostOps> posts) =>
    posts.where((f) => f.tags.startsWith('a'));
