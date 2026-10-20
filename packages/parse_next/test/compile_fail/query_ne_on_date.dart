// expect: UNDEFINED_METHOD
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Cond<Post> c() => const PostFields().publishedAt.ne(DateTime.utc(2024));
