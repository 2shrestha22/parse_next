// expect: ARGUMENT_TYPE_NOT_ASSIGNABLE
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Future<UpdateResult<Post>> f(Collection<Post, PostFields, PostOps> posts) =>
    posts.update('id', (o) => [o.count.set('3')]);
