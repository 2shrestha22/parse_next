// expect: UNDEFINED_METHOD
import 'package:parse_next/parse_next.dart';

import '../models.dart';

Future<UpdateResult<Author>> f(
  Collection<Author, AuthorFields, AuthorOps> authors,
) => authors.update('id', (o) => [o.name.unset()]);
