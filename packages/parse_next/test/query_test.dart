import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'models.dart';

const at = '2024-01-02T03:04:05.678Z';
final date = DateTime.utc(2024, 1, 2, 3, 4, 5, 678);
const dateJson = {'__type': 'Date', 'iso': at};
const authorPointer = {
  '__type': 'Pointer',
  'className': 'Author',
  'objectId': 'a1',
};

Map<String, Object?> row(String id) => {
  'objectId': id,
  'createdAt': at,
  'updatedAt': at,
  'title': id,
};

Map<String, Object?> results(Iterable<Map<String, Object?>> rows) => {
  'results': rows.toList(),
};

final class Server {
  Server([Map<String, Object?> Function(int call)? respond])
    : _respond = respond ?? ((_) => results([]));

  final Map<String, Object?> Function(int call) _respond;
  final requests = <http.Request>[];

  late final client = ParseClient(
    server: Uri.parse('http://parse.test/parse'),
    appId: 'app',
    httpClient: MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(_respond(requests.length - 1)), 200);
    }),
  );
  late final posts = client.collection(postSchema);
  late final authors = client.collection(authorSchema);

  http.Request get only => requests.single;
  Map<String, String> get params => only.url.queryParameters;
}

void main() {
  group('each constraint compiles to', () {
    final authors = Server().authors;
    for (final (name, Cond<Post> Function(PostFields) build, Object? json) in [
      ('eq', (f) => f.title.eq('a'), {'title': 'a'}),
      (
        'ne',
        (f) => f.count.ne(1),
        {
          'count': {r'$ne': 1},
        },
      ),
      (
        'oneOf',
        (f) => f.status.oneOf(['a', 'b']),
        {
          'status': {
            r'$in': ['a', 'b'],
          },
        },
      ),
      (
        'noneOf',
        (f) => f.status.noneOf(['a']),
        {
          'status': {
            r'$nin': ['a'],
          },
        },
      ),
      (
        'exists',
        (f) => f.meta.exists(),
        {
          'meta': {r'$exists': true},
        },
      ),
      (
        'exists false',
        (f) => f.slug.exists(false),
        {
          'slug': {r'$exists': false},
        },
      ),
      (
        'gt',
        (f) => f.count.gt(1),
        {
          'count': {r'$gt': 1},
        },
      ),
      (
        'gte',
        (f) => f.ratio.gte(0.5),
        {
          'ratio': {r'$gte': 0.5},
        },
      ),
      (
        'lt',
        (f) => f.title.lt('m'),
        {
          'title': {r'$lt': 'm'},
        },
      ),
      (
        'lte',
        (f) => f.score.lte(2),
        {
          'score': {r'$lte': 2.0},
        },
      ),
      (
        'a Date as __type Date',
        (f) => f.publishedAt.gt(date),
        {
          'publishedAt': {r'$gt': dateJson},
        },
      ),
      ('a Date eq', (f) => f.publishedAt.eq(date), {'publishedAt': dateJson}),
      (
        'createdAt as __type Date',
        (f) => f.createdAt.lte(date),
        {
          'createdAt': {r'$lte': dateJson},
        },
      ),
      (
        'updatedAt',
        (f) => f.updatedAt.gte(date),
        {
          'updatedAt': {r'$gte': dateJson},
        },
      ),
      ('id as objectId', (f) => f.id.eq('p1'), {'objectId': 'p1'}),
      (
        'startsWith',
        (f) => f.title.startsWith('a.b'),
        {
          'title': {r'$regex': r'^\Qa.b\E'},
        },
      ),
      (
        'matches',
        (f) => f.title.matches('a.c'),
        {
          'title': {r'$regex': 'a.c'},
        },
      ),
      (
        'matches caseInsensitive',
        (f) => f.title.matches('^a', caseInsensitive: true),
        {
          'title': {r'$regex': '^a', r'$options': 'i'},
        },
      ),
      (
        'fullText',
        (f) => f.title.fullText(' word '),
        {
          'title': {
            r'$text': {
              r'$search': {r'$term': 'word'},
            },
          },
        },
      ),
      (
        'contains',
        (f) => f.tags.contains('a'),
        {
          'tags': {
            r'$all': ['a'],
          },
        },
      ),
      (
        'containsAll',
        (f) => f.tags.containsAll(['a', 'b']),
        {
          'tags': {
            r'$all': ['a', 'b'],
          },
        },
      ),
      (
        'a pointer list contains',
        (f) => f.coauthors.contains(const Pointer('a1')),
        {
          'coauthors': {
            r'$all': [authorPointer],
          },
        },
      ),
      ('isId', (f) => f.author.isId('a1'), {'author': authorPointer}),
      (
        'matchesQuery',
        (f) => f.author.matchesQuery(authors.where((a) => a.name.eq('x'))),
        {
          'author': {
            r'$inQuery': {
              'where': {'name': 'x'},
              'className': 'Author',
            },
          },
        },
      ),
      (
        'matchesQuery without a where',
        (f) => f.author.matchesQuery(authors.query()),
        {
          'author': {
            r'$inQuery': {'where': <String, Object?>{}, 'className': 'Author'},
          },
        },
      ),
      (
        'near',
        (f) => f.location.near(GeoPoint(1, 2)),
        {
          'location': {
            r'$nearSphere': {
              '__type': 'GeoPoint',
              'latitude': 1.0,
              'longitude': 2.0,
            },
          },
        },
      ),
      (
        'near maxKm in radians',
        (f) => f.location.near(GeoPoint(1, 2), maxKm: 6371),
        {
          'location': {
            r'$nearSphere': {
              '__type': 'GeoPoint',
              'latitude': 1.0,
              'longitude': 2.0,
            },
            r'$maxDistance': 1.0,
          },
        },
      ),
      (
        'withinBox',
        (f) => f.location.withinBox(GeoPoint(0, 1), GeoPoint(2, 3)),
        {
          'location': {
            r'$within': {
              r'$box': [
                {'__type': 'GeoPoint', 'latitude': 0.0, 'longitude': 1.0},
                {'__type': 'GeoPoint', 'latitude': 2.0, 'longitude': 3.0},
              ],
            },
          },
        },
      ),
      (
        'withinPolygon as GeoPoints',
        (f) => f.location.withinPolygon(
          Polygon([GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1)]),
        ),
        {
          'location': {
            r'$geoWithin': {
              r'$polygon': [
                {'__type': 'GeoPoint', 'latitude': 0.0, 'longitude': 0.0},
                {'__type': 'GeoPoint', 'latitude': 0.0, 'longitude': 1.0},
                {'__type': 'GeoPoint', 'latitude': 1.0, 'longitude': 1.0},
              ],
            },
          },
        },
      ),
      (
        '& with distinct keys merges in call order',
        (f) => f.title.eq('a') & f.count.gt(1) & f.slug.exists(),
        {
          'title': 'a',
          'count': {r'$gt': 1},
          'slug': {r'$exists': true},
        },
      ),
      (
        '& with a shared key is \$and',
        (f) => f.count.gt(1) & f.count.lt(5),
        {
          r'$and': [
            {
              'count': {r'$gt': 1},
            },
            {
              'count': {r'$lt': 5},
            },
          ],
        },
      ),
      (
        '| is \$or',
        (f) => f.title.eq('a') | f.count.gt(1),
        {
          r'$or': [
            {'title': 'a'},
            {
              'count': {r'$gt': 1},
            },
          ],
        },
      ),
      (
        '| inside &',
        (f) => (f.title.eq('a') | f.title.eq('b')) & f.count.gt(1),
        {
          r'$or': [
            {'title': 'a'},
            {'title': 'b'},
          ],
          'count': {r'$gt': 1},
        },
      ),
      (
        'two | under & is \$and',
        (f) =>
            (f.title.eq('a') | f.title.eq('b')) &
            (f.count.eq(1) | f.count.eq(2)),
        {
          r'$and': [
            {
              r'$or': [
                {'title': 'a'},
                {'title': 'b'},
              ],
            },
            {
              r'$or': [
                {'count': 1},
                {'count': 2},
              ],
            },
          ],
        },
      ),
    ]) {
      test(name, () async {
        final s = Server();
        await s.posts.where(build).find();
        expect(s.only.method, 'GET');
        expect(s.only.url.path, '/parse/classes/Post');
        expect(s.params, {'where': jsonEncode(json), 'limit': '100'});
      });
    }
  });

  test('a relation condition queries the member class', () async {
    final s = Server();
    await s.authors.where((_) => const PostFields().followers.of('p 1')).find();
    expect(s.only.url.path, '/parse/classes/Author');
    expect(
      s.params['where'],
      jsonEncode({
        r'$relatedTo': {
          'object': {
            '__type': 'Pointer',
            'className': 'Post',
            'objectId': 'p 1',
          },
          'key': 'followers',
        },
      }),
    );
  });

  test('repeated where combines with &', () async {
    final s = Server();
    await s.posts
        .where((f) => f.count.gt(1))
        .where((f) => f.title.eq('a'))
        .where((f) => f.count.lt(9))
        .find();
    expect(
      s.params['where'],
      jsonEncode({
        r'$and': [
          {
            'count': {r'$gt': 1},
            'title': 'a',
          },
          {
            'count': {r'$lt': 9},
          },
        ],
      }),
    );
  });

  test('include, orderBy, limit and skip', () async {
    final s = Server();
    await s.posts
        .query()
        .include((f) => f.author)
        .include((f) => f.coauthors)
        .orderBy((f) => f.count.desc)
        .orderBy((f) => f.title.asc)
        .orderBy((f) => f.createdAt.desc)
        .limit(5)
        .skip(10)
        .find();
    expect(s.params, {
      'include': 'author,coauthors',
      'order': '-count,title,-createdAt',
      'limit': '5',
      'skip': '10',
    });
  });

  test('builders leave the original query unchanged', () async {
    final s = Server();
    final base = s.posts.where((f) => f.count.gt(1));
    base.limit(3).include((f) => f.author).orderBy((f) => f.count.asc);
    await base.find();
    expect(s.params, {
      'where': jsonEncode({
        'count': {r'$gt': 1},
      }),
      'limit': '100',
    });
  });

  test('find decodes rows and included pointers', () async {
    final s = Server(
      (_) => results([
        {
          ...row('p1'),
          'author': {
            '__type': 'Object',
            'className': 'Author',
            ...row('a1'),
            'name': 'Ann',
          },
          'coauthors': [authorPointer],
        },
        row('p2'),
      ]),
    );
    final docs = await s.posts.query().include((f) => f.author).find();
    expect([for (final d in docs) d.id], ['p1', 'p2']);
    expect(docs.first.data.author!.loaded!.data.name, 'Ann');
    expect(docs.first.data.coauthors!.single.loaded, isNull);
  });

  test('first sends limit 1 and returns null for no rows', () async {
    final s = Server();
    expect(await s.posts.query().skip(2).first(), isNull);
    expect(s.params, {'limit': '1', 'skip': '2'});

    final t = Server((_) => results([row('p1')]));
    expect((await t.posts.query().first())!.id, 'p1');
  });

  test('count sends count=1 and limit=0 and only the where', () async {
    final s = Server((_) => {'results': <Object?>[], 'count': 7});
    expect(
      await s.posts
          .where((f) => f.count.gt(1))
          .include((f) => f.author)
          .orderBy((f) => f.count.asc)
          .limit(3)
          .skip(1)
          .count(),
      7,
    );
    expect(s.params, {
      'where': jsonEncode({
        'count': {r'$gt': 1},
      }),
      'count': '1',
      'limit': '0',
    });
  });

  test('raw sends keys and returns the rows undecoded', () async {
    final s = Server(
      (_) => results([
        {'objectId': 'p1', 'title': 3},
      ]),
    );
    final rows = await s.posts
        .where((f) => f.count.gt(1))
        .raw(keys: ['title', 'count']);
    expect(rows, [
      {'objectId': 'p1', 'title': 3},
    ]);
    expect(s.params, {
      'where': jsonEncode({
        'count': {r'$gt': 1},
      }),
      'limit': '100',
      'keys': 'title,count',
    });
  });

  group('stream', () {
    test('pages by an objectId cursor, one request per page', () async {
      final ids = [
        for (var i = 0; i < 205; i++) 'id${i.toString().padLeft(3, '0')}',
      ];
      final s = Server(
        (call) => results(ids.skip(call * 100).take(100).map(row)),
      );
      final got = await s.posts
          .where((f) => f.count.gt(1))
          .include((f) => f.author)
          .stream()
          .map((d) => d.id)
          .toList();
      expect(got, ids);
      expect(s.requests, hasLength(3));
      final count = {r'$gt': 1};
      expect(
        [for (final r in s.requests) r.url.queryParameters],
        [
          {
            'where': jsonEncode({'count': count}),
            'include': 'author',
            'order': 'objectId',
            'limit': '100',
          },
          {
            'where': jsonEncode({
              'count': count,
              'objectId': {r'$gt': 'id099'},
            }),
            'include': 'author',
            'order': 'objectId',
            'limit': '100',
          },
          {
            'where': jsonEncode({
              'count': count,
              'objectId': {r'$gt': 'id199'},
            }),
            'include': 'author',
            'order': 'objectId',
            'limit': '100',
          },
        ],
      );
    });

    test('an id condition and the cursor combine with \$and', () async {
      final s = Server(
        (call) => results(
          call == 0 ? [for (var i = 0; i < 100; i++) row('id$i')] : const [],
        ),
      );
      await s.posts.where((f) => f.id.gt('a')).stream().drain<void>();
      expect(s.requests, hasLength(2));
      expect(
        s.requests.last.url.queryParameters['where'],
        jsonEncode({
          r'$and': [
            {
              'objectId': {r'$gt': 'a'},
            },
            {
              'objectId': {r'$gt': 'id99'},
            },
          ],
        }),
      );
    });

    test('sends nothing until listened to', () async {
      final s = Server();
      final stream = s.posts.query().stream();
      expect(s.requests, isEmpty);
      await stream.drain<void>();
      expect(s.requests, hasLength(1));
    });

    for (final (
          name,
          Query<Post, PostFields, PostOps> Function(
            Query<Post, PostFields, PostOps>,
          )
          build,
        )
        in [
          ('orderBy', (q) => q.orderBy((f) => f.count.asc)),
          ('skip', (q) => q.skip(1)),
          ('limit', (q) => q.limit(1)),
        ]) {
      test('throws StateError with $name', () {
        final s = Server();
        expect(() => build(s.posts.query()).stream(), throwsStateError);
        expect(s.requests, isEmpty);
      });
    }
  });

  group('rejects before any request', () {
    test('oneOf with no values', () {
      expect(() => const PostFields().title.oneOf([]), throwsArgumentError);
    });

    test(r'startsWith with \E', () {
      expect(
        () => const PostFields().title.startsWith(r'a\Eb'),
        throwsArgumentError,
      );
    });

    test('fullText with more than one word', () {
      expect(
        () => const PostFields().title.fullText('a b'),
        throwsArgumentError,
      );
      expect(() => const PostFields().title.fullText(' '), throwsArgumentError);
    });

    test('matchesQuery with more than a where', () {
      final s = Server();
      for (final q in [
        s.authors.query().limit(1),
        s.authors.query().skip(1),
        s.authors.query().orderBy((f) => f.name.asc),
      ]) {
        expect(
          () => const PostFields().author.matchesQuery(q),
          throwsArgumentError,
        );
      }
      expect(s.requests, isEmpty);
    });

    test('a negative limit or skip', () {
      final q = Server().posts.query();
      expect(() => q.limit(-1), throwsRangeError);
      expect(() => q.skip(-1), throwsRangeError);
    });
  });
}
