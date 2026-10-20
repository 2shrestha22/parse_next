// expect: ARGUMENT_TYPE_NOT_ASSIGNABLE
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Cond<Post> f() =>
    const PostFields().title.eq('a') & const AuthorFields().name.eq('b');
