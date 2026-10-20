import 'dart:convert';
import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

import 'fixtures.g.dart';
import 'models.dart';

const covered = {
  'create_all_fields.json',
  'create_null_fields.json',
  'file_upload.json',
  'get_after_ops.mongo.json',
  'get_after_ops.postgres.json',
  'get_all_fields.json',
  'get_null_fields.mongo.json',
  'get_null_fields.postgres.json',
  'op_add.json',
  'op_add_relation.json',
  'op_add_unique.mongo.json',
  'op_add_unique.postgres.json',
  'op_delete.json',
  'op_increment.json',
  'op_remove.mongo.json',
  'op_remove.postgres.json',
  'op_remove_relation.json',
  'query_all_fields.json',
  'query_include.json',
  'query_related_to.json',
};

const deferred = {
  'error_101_acl_denied.json': 'error mapping is Phase 2',
  'error_101_missing.json': 'error mapping is Phase 2',
  'error_137_duplicate.json': 'error mapping is Phase 2',
  'error_141_script_failed.json': 'error mapping is Phase 2',
  'error_209_invalid_session.json': 'error mapping is Phase 2',
  'error_unauthorized.json': 'error mapping is Phase 2',
};

Map<String, Object?> fixture(String name) {
  if (!covered.contains(name)) throw ArgumentError.value(name, 'name');
  return jsonDecode(fixtures[name]!) as Map<String, Object?>;
}

Json body(String name) =>
    Json((fixture(name)['request']! as Map<String, Object?>)['body']!
        as Map<String, Object?>);

Json response(String name) =>
    Json(fixture(name)['response']! as Map<String, Object?>);

Json firstResult(String name) =>
    Json((response(name)['results']! as List<Object?>).single!
        as Map<String, Object?>);

final epoch = DateTime.utc(2000);

final acl =
    Acl.publicRead().withUser('obj0000001', write: true).withRole('admin');

final file = ParseFile(
  name: 'file0001_hello.txt',
  url: 'http://parse.test/parse/files/parse-next-it/file0001_hello.txt',
);

/// The values sent in create_all_fields. [Post.area] is given open, as sent;
/// the server returns it closed, and [Polygon] drops the closing point, so a
/// decoded polygon equals this one and re-encodes to the request body.
Post sent({ParseFile? attachment}) => Post(
      title: 'Hello, wörld 👋',
      slug: 'hello-world',
      status: 'published',
      count: 20,
      ratio: 1.5,
      score: 2.0,
      published: true,
      publishedAt: DateTime.utc(2024, 1, 2, 3, 4, 5, 678),
      tags: ['a', 'b'],
      meta: Json({
        'list': [1, 'two'],
        'n': 1,
        'nested': {'b': true},
        'nil': null,
        's': 'x',
      }),
      location: GeoPoint(27.7, 85.3),
      area: Polygon([
        GeoPoint(0, 0),
        GeoPoint(0, 1),
        GeoPoint(1, 1),
        GeoPoint(1, 0),
      ]),
      attachment: attachment ?? const ParseFile(name: 'file0001_hello.txt'),
      data: Uint8List.fromList([0, 1, 2, 255]),
      author: const Pointer('obj0000003'),
      coauthors: const [Pointer('obj0000003'), Pointer('obj0000004')],
    );

final stored = sent(attachment: file).view;

Json encodeWithAcl(Post post, Acl acl) =>
    Json({...postSchema.encode(post), 'ACL': acl.toJson()});

void main() {
  test('every fixture is covered or deferred with a reason', () {
    expect(covered.intersection(deferred.keys.toSet()), isEmpty);
    expect(fixtures.keys.toSet(), {...covered, ...deferred.keys});
  });

  group('create', () {
    test('create_all_fields: encoding the values gives the request body', () {
      expect(encodeWithAcl(sent(), acl), body('create_all_fields.json'));
    });

    test('create_null_fields: null fields encode as null', () {
      final sentBody = body('create_null_fields.json');
      final encoded = postSchema.encode(const Post());
      // The capture leaves out slug (unique index) and area (a null Polygon
      // breaks later reads on Mongo); see parse_next_it/tool/capture.dart.
      expect(encoded.keys.toSet().difference(sentBody.keys.toSet()),
          {'slug', 'area'});
      expect({for (final k in sentBody.keys) k: encoded[k]}, sentBody);
    });

    for (final (name, id) in [
      ('create_all_fields.json', 'obj0000005'),
      ('create_null_fields.json', 'obj0000006'),
    ]) {
      test('$name: response', () {
        final r = response(name);
        expect(r.require<String>('objectId'), id);
        expect(r.require<DateTime>('createdAt'), epoch);
      });
    }
  });

  group('get', () {
    for (final name in [
      'get_all_fields.json',
      'query_all_fields.json',
    ]) {
      test('$name decodes every field type', () {
        final json =
            name.startsWith('query') ? firstResult(name) : response(name);
        final doc = Doc.decode(json, postSchema);
        expect(doc.id, 'obj0000005');
        expect(doc.createdAt, epoch);
        expect(doc.updatedAt, epoch);
        expect(doc.createdAt.isUtc, isTrue);
        expect(doc.acl, acl);
        expect(doc.data.view, stored);
        expect(doc.data.followers, isA<Relation<Author>>());
        expect(doc.data.author!.loaded, isNull);
        expect(doc.data.count, isA<int>());
        expect(doc.data.score, isA<double>());
      });
    }

    test('get_all_fields re-encodes to the create body', () {
      final doc = Doc.decode(response('get_all_fields.json'), postSchema);
      expect(encodeWithAcl(doc.data, doc.acl!), body('create_all_fields.json'));
    });

    for (final backend in ['mongo', 'postgres']) {
      test('get_null_fields.$backend.json: null and absent both decode absent',
          () {
        final doc =
            Doc.decode(response('get_null_fields.$backend.json'), postSchema);
        expect(doc.id, 'obj0000006');
        expect(doc.acl, isNull);
        expect(doc.data.view, const Post().view);
        expect(doc.data.followers, isA<Relation<Author>>());
      });

      test('get_after_ops.$backend.json', () {
        final doc =
            Doc.decode(response('get_after_ops.$backend.json'), postSchema);
        final expected = {...stored, 'count': 21, 'title': null};
        // Postgres reorders arrays after AddUnique (see PLAN.md).
        expect(doc.data.tags, unorderedEquals(['b', 'c', 'd']));
        expect({...doc.data.view, 'tags': null}, {...expected, 'tags': null});
      });
    }
  });

  group('query', () {
    test('query_include: included pointers carry the loaded Doc', () {
      final doc = Doc.decode(firstResult('query_include.json'), postSchema);
      expect(doc.data.view, stored);
      final author = doc.data.author!;
      expect(author.id, 'obj0000003');
      expect(author.loaded!.id, 'obj0000003');
      expect(author.loaded!.data.name, 'Ann');
      expect(author.loaded!.createdAt, epoch);
      expect(author.loaded!.updatedAt, epoch);
      expect(
        [for (final p in doc.data.coauthors!) (p.id, p.loaded!.data.name)],
        [('obj0000003', 'Ann'), ('obj0000004', 'Ben')],
      );
    });

    test('query_related_to: plain results decode as Doc', () {
      final doc =
          Doc.decode(firstResult('query_related_to.json'), authorSchema);
      expect(doc.id, 'obj0000003');
      expect(doc.data.name, 'Ann');
      expect(doc.acl, isNull);
    });
  });

  test('file_upload: response is the File value without __type', () {
    final r = response('file_upload.json');
    expect(
      ParseFile(name: r.require<String>('name'), url: r.require<String>('url')),
      file,
    );
  });

  // Request bodies here are __op ops, which are Phase 3; only the responses
  // are decoded.
  group('op responses', () {
    for (final (name, tags) in [
      ('op_add.json', ['a', 'b', 'c']),
      ('op_add_unique.mongo.json', ['a', 'b', 'c', 'd']),
      ('op_add_unique.postgres.json', ['a', 'd', 'c', 'b']),
      ('op_remove.mongo.json', ['b', 'c', 'd']),
      ('op_remove.postgres.json', ['d', 'c', 'b']),
    ]) {
      test(name, () {
        final r = response(name);
        expect(r.optList<String>('tags'), tags);
        expect(r.require<DateTime>('updatedAt'), epoch);
      });
    }

    test('op_increment.json', () {
      final r = response('op_increment.json');
      expect(r.require<int>('count'), 21);
      expect(r.require<DateTime>('updatedAt'), epoch);
    });

    for (final name in [
      'op_delete.json',
      'op_add_relation.json',
      'op_remove_relation.json',
    ]) {
      test(name, () {
        final r = response(name);
        expect(r.keys, ['updatedAt']);
        expect(r.require<DateTime>('updatedAt'), epoch);
      });
    }
  });
}
