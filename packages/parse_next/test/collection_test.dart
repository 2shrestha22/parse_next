import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'models.dart';

const updatedAt = '2024-01-02T03:04:05.678Z';
const delete = {'__op': 'Delete'};

final class Server {
  Server([this.response = const {'updatedAt': updatedAt}]);

  final Map<String, Object?> response;
  final requests = <http.Request>[];

  late final posts = ParseClient(
    server: Uri.parse('http://parse.test/parse'),
    appId: 'app',
    httpClient: MockClient((r) async {
      requests.add(r);
      return http.Response(jsonEncode(response), 200);
    }),
  ).collection(postSchema);

  http.Request get only => requests.single;
  Object? get body => jsonDecode(only.body);
}

void main() {
  group('update sends', () {
    final author = {
      '__type': 'Pointer',
      'className': 'Author',
      'objectId': 'a1',
    };
    for (final (name, List<Op> Function(PostOps) build, Object? json) in [
      ('set String', (o) => [o.title.set('hi')], {'title': 'hi'}),
      ('set int', (o) => [o.count.set(3)], {'count': 3}),
      ('set double', (o) => [o.ratio.set(1.5)], {'ratio': 1.5}),
      ('set bool', (o) => [o.published.set(false)], {'published': false}),
      (
        'set Date',
        (o) => [o.publishedAt.set(DateTime.utc(2024, 1, 2, 3, 4, 5, 678))],
        {
          'publishedAt': {'__type': 'Date', 'iso': updatedAt},
        },
      ),
      (
        'set List',
        (o) => [
          o.tags.set(['a']),
        ],
        {
          'tags': ['a'],
        },
      ),
      (
        'set Map',
        (o) => [
          o.meta.set(Json({'n': 1})),
        ],
        {
          'meta': {'n': 1},
        },
      ),
      (
        'set GeoPoint',
        (o) => [o.location.set(GeoPoint(1, 2))],
        {
          'location': {'__type': 'GeoPoint', 'latitude': 1, 'longitude': 2},
        },
      ),
      (
        'set Polygon',
        (o) => [
          o.area.set(Polygon([GeoPoint(0, 0), GeoPoint(0, 1), GeoPoint(1, 1)])),
        ],
        {
          'area': {
            '__type': 'Polygon',
            'coordinates': [
              [0, 0],
              [0, 1],
              [1, 1],
            ],
          },
        },
      ),
      (
        'set File',
        (o) => [o.attachment.set(const ParseFile(name: 'f.txt', url: 'u'))],
        {
          'attachment': {'__type': 'File', 'name': 'f.txt'},
        },
      ),
      (
        'set Bytes',
        (o) => [
          o.data.set(Uint8List.fromList([0, 255])),
        ],
        {
          'data': {'__type': 'Bytes', 'base64': 'AP8='},
        },
      ),
      (
        'set Pointer',
        (o) => [o.author.set(const Pointer('a1'))],
        {'author': author},
      ),
      (
        'set List<Pointer>',
        (o) => [
          o.coauthors.set(const [Pointer('a1')]),
        ],
        {
          'coauthors': [author],
        },
      ),
      ('unset', (o) => [o.title.unset()], {'title': delete}),
      ('unset num', (o) => [o.count.unset()], {'count': delete}),
      ('unset List', (o) => [o.tags.unset()], {'tags': delete}),
      (
        'increment',
        (o) => [o.count.increment(-2)],
        {
          'count': {'__op': 'Increment', 'amount': -2},
        },
      ),
      (
        'add',
        (o) => [
          o.tags.add(['a', 'b']),
        ],
        {
          'tags': {
            '__op': 'Add',
            'objects': ['a', 'b'],
          },
        },
      ),
      (
        'addUnique',
        (o) => [
          o.tags.addUnique(['a']),
        ],
        {
          'tags': {
            '__op': 'AddUnique',
            'objects': ['a'],
          },
        },
      ),
      (
        'remove',
        (o) => [
          o.coauthors.remove(const [Pointer('a1')]),
        ],
        {
          'coauthors': {
            '__op': 'Remove',
            'objects': [author],
          },
        },
      ),
      (
        'relation add',
        (o) => [
          o.followers.add(const [Pointer('a1')]),
        ],
        {
          'followers': {
            '__op': 'AddRelation',
            'objects': [author],
          },
        },
      ),
      (
        'relation remove',
        (o) => [
          o.followers.remove(const [Pointer('a1')]),
        ],
        {
          'followers': {
            '__op': 'RemoveRelation',
            'objects': [author],
          },
        },
      ),
      (
        'several ops in one request',
        (o) => [o.title.set('hi'), o.count.increment(1)],
        {
          'title': 'hi',
          'count': {'__op': 'Increment', 'amount': 1},
        },
      ),
    ]) {
      test(name, () async {
        final s = Server();
        expect(
          await s.posts.update('p 1', build),
          DateTime.utc(2024, 1, 2, 3, 4, 5, 678),
        );
        expect(s.only.method, 'PUT');
        expect(
          s.only.url.toString(),
          'http://parse.test/parse/classes/Post/p%201',
        );
        expect(s.body, json);
      });
    }
  });

  group('update rejects before any request', () {
    test('two ops on one key', () async {
      final s = Server();
      await expectLater(
        () => s.posts.update(
          'p1',
          (o) => [o.count.increment(1), o.count.unset()],
        ),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('a relation op with no targets', () async {
      final s = Server();
      await expectLater(
        () => s.posts.update('p1', (o) => [o.followers.add([])]),
        throwsArgumentError,
      );
      await expectLater(
        () => s.posts.update('p1', (o) => [o.followers.remove([])]),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });

    test('no ops', () async {
      final s = Server();
      await expectLater(
        () => s.posts.update('p1', (o) => []),
        throwsArgumentError,
      );
      expect(s.requests, isEmpty);
    });
  });

  test(
    'replace sends every null field as Delete and never the relation',
    () async {
      final s = Server();
      await s.posts.replace(
        'p1',
        const Post(title: 'kept'),
        acl: const Acl().withPublic(),
      );
      expect(s.only.method, 'PUT');
      expect(s.body, {
        for (final key in postSchema.encode(const Post()).keys) key: delete,
        'title': 'kept',
        'ACL': {
          '*': {'read': true},
        },
      });
    },
  );

  test('replace without an ACL leaves it out', () async {
    final s = Server();
    await s.posts.replace('p1', const Post());
    expect((s.body! as Map<String, Object?>).keys, isNot(contains('ACL')));
  });

  group('create', () {
    final created = {'objectId': 'p1', 'createdAt': updatedAt};

    test('sends non-null fields and the ACL', () async {
      final s = Server(created);
      final doc = await s.posts.create(
        Post(title: 'hi', count: 0, author: const Pointer('a1')),
        acl: const Acl().withPublic().withUser('u1', write: true),
      );
      expect(s.only.method, 'POST');
      expect(s.only.url.toString(), 'http://parse.test/parse/classes/Post');
      expect(s.body, {
        'title': 'hi',
        'count': 0,
        'author': {
          '__type': 'Pointer',
          'className': 'Author',
          'objectId': 'a1',
        },
        'ACL': {
          '*': {'read': true},
          'u1': {'read': true, 'write': true},
        },
      });
      expect(doc.id, 'p1');
      expect(doc.createdAt, DateTime.utc(2024, 1, 2, 3, 4, 5, 678));
      expect(doc.updatedAt, doc.createdAt);
      expect(doc.acl, const Acl().withPublic().withUser('u1', write: true));
      expect(
        doc.data.view,
        Post(title: 'hi', count: 0, author: const Pointer('a1')).view,
      );
    });

    test('takes the fields a trigger changed from the response', () async {
      final s = Server({...created, 'title': 'HI', 'slug': delete});
      final doc = await s.posts.create(const Post(title: 'hi', slug: 's'));
      expect(doc.data.title, 'HI');
      expect(doc.data.slug, isNull);
      expect(doc.acl, isNull);
    });
  });

  test('get', () async {
    final s = Server({
      'objectId': 'p1',
      'createdAt': updatedAt,
      'updatedAt': updatedAt,
      'title': 'hi',
    });
    final doc = await s.posts.get('p1');
    expect(s.only.method, 'GET');
    expect(s.only.url.toString(), 'http://parse.test/parse/classes/Post/p1');
    expect(doc.id, 'p1');
    expect(doc.data.title, 'hi');
  });

  test('delete', () async {
    final s = Server(const {});
    await s.posts.delete('p1');
    expect(s.only.method, 'DELETE');
    expect(s.only.url.toString(), 'http://parse.test/parse/classes/Post/p1');
  });
}
