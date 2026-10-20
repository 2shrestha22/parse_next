// Output is normalized as recorded in PLAN.md (Defaults): keys are sorted, so
// key order in a fixture is not the server's.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:parse_next_it/backends.dart';

const _fixedInstant = '2000-01-01T00:00:00.000Z';

final _compose = Platform.script.resolve('../../../docker/compose.yaml');
final _fixtures = Directory.fromUri(
  Platform.script.resolve('../../parse_next/test/fixtures/'),
);

Future<void> main() async {
  final captured = <String, Map<String, Object?>>{};
  for (final MapEntry(key: backend, value: url) in backends.entries) {
    final fixtures = await _Capture(backend, url).run();
    fixtures.forEach((name, fixture) {
      (captured[name] ??= {})[backend] = fixture;
    });
  }

  _fixtures.createSync(recursive: true);
  for (final f in _fixtures.listSync().whereType<File>()) {
    if (f.path.endsWith('.json')) f.deleteSync();
  }
  const encoder = JsonEncoder.withIndent('  ');
  final differing = <String>[];
  captured.forEach((name, byBackend) {
    final encoded = byBackend.map((b, f) => MapEntry(b, encoder.convert(f)));
    if (encoded.values.toSet().length == 1) {
      _write('$name.json', encoded.values.first);
    } else {
      differing.add(name);
      encoded.forEach((backend, json) => _write('$name.$backend.json', json));
    }
  });
  stdout.writeln('wrote ${captured.length} fixtures to ${_fixtures.path}');
  if (differing.isNotEmpty) {
    stdout.writeln('differ between backends: ${differing.join(', ')}');
  }
}

void _write(String name, String json) =>
    File('${_fixtures.path}$name').writeAsStringSync('$json\n');

class _Capture {
  _Capture(this.backend, this.url);

  final String backend;
  final String url;
  final _fixtures = <String, Object?>{};
  late final _placeholders = <String, String>{url: 'http://parse.test/parse'};
  final _counters = <String, int>{};

  Future<Map<String, Object?>> run() async {
    await _reset();

    final alice = await _signUp('alice');
    final bob = await _signUp('bob');
    final aliceId = alice['objectId']! as String;
    final aliceToken = alice['sessionToken']! as String;
    final bobToken = bob['sessionToken']! as String;

    final authors = [
      for (final name in ['Ann', 'Ben'])
        _pointer(
          'Author',
          (await _call('POST', '/classes/Author', body: {'name': name})),
        ),
    ];

    final upload = await _call(
      'POST',
      '/files/hello.txt',
      token: aliceToken,
      rawBody: 'hello',
      contentType: 'text/plain',
      save: 'file_upload',
    );

    final allFields = <String, Object?>{
      'title': 'Hello, wörld 👋',
      'slug': 'hello-world',
      'count': 20,
      'ratio': 1.5,
      'score': 2.0,
      'published': true,
      'publishedAt': {'__type': 'Date', 'iso': '2024-01-02T03:04:05.678Z'},
      'status': 'published',
      'tags': ['a', 'b'],
      'meta': {
        'n': 1,
        's': 'x',
        'nested': {'b': true},
        'list': [1, 'two'],
        'nil': null,
      },
      'author': authors[0],
      'coauthors': authors,
      'attachment': {'__type': 'File', 'name': upload['name']},
      'location': {'__type': 'GeoPoint', 'latitude': 27.7, 'longitude': 85.3},
      'area': {
        '__type': 'Polygon',
        'coordinates': [
          [0, 0],
          [0, 1],
          [1, 1],
          [1, 0],
        ],
      },
      'data': {'__type': 'Bytes', 'base64': 'AAEC/w=='},
      'ACL': {
        '*': {'read': true},
        aliceId: {'read': true, 'write': true},
        'role:admin': {'read': true},
      },
    };
    final created = await _call(
      'POST',
      '/classes/Post',
      token: aliceToken,
      body: allFields,
      save: 'create_all_fields',
    );
    final id = created['objectId']! as String;
    await _call(
      'GET',
      '/classes/Post/$id',
      token: aliceToken,
      save: 'get_all_fields',
    );
    await _call(
      'GET',
      '/classes/Post',
      token: aliceToken,
      query: {
        'where': jsonEncode({'objectId': id}),
      },
      save: 'query_all_fields',
    );
    await _call(
      'GET',
      '/classes/Post',
      token: aliceToken,
      query: {
        'where': jsonEncode({'objectId': id}),
        'include': 'author,coauthors',
      },
      save: 'query_include',
    );

    // Not 'area': on Mongo a null Polygon makes every later read or delete of
    // the object fail with 500 "Cannot read properties of null".
    final nullFields = {
      for (final key in allFields.keys)
        if (!const {'ACL', 'slug', 'area'}.contains(key)) key: null,
    };
    final createdNull = await _call(
      'POST',
      '/classes/Post',
      token: aliceToken,
      body: nullFields,
      save: 'create_null_fields',
    );
    await _call(
      'GET',
      '/classes/Post/${createdNull['objectId']}',
      token: aliceToken,
      save: 'get_null_fields',
    );

    final ops = <String, Map<String, Object?>>{
      'op_increment': {
        'count': {'__op': 'Increment', 'amount': 1},
      },
      'op_add': {
        'tags': {
          '__op': 'Add',
          'objects': ['c'],
        },
      },
      'op_add_unique': {
        'tags': {
          '__op': 'AddUnique',
          'objects': ['a', 'd'],
        },
      },
      'op_remove': {
        'tags': {
          '__op': 'Remove',
          'objects': ['a'],
        },
      },
      'op_delete': {
        'title': {'__op': 'Delete'},
      },
      'op_add_relation': {
        'followers': {'__op': 'AddRelation', 'objects': authors},
      },
      'op_remove_relation': {
        'followers': {
          '__op': 'RemoveRelation',
          'objects': [authors[1]],
        },
      },
    };
    for (final MapEntry(key: name, value: body) in ops.entries) {
      await _call(
        'PUT',
        '/classes/Post/$id',
        token: aliceToken,
        body: body,
        save: name,
      );
    }
    await _call(
      'GET',
      '/classes/Post/$id',
      token: aliceToken,
      save: 'get_after_ops',
    );
    await _call(
      'GET',
      '/classes/Author',
      token: aliceToken,
      query: {
        'where': jsonEncode({
          r'$relatedTo': {
            'object': {
              '__type': 'Pointer',
              'className': 'Post',
              'objectId': id,
            },
            'key': 'followers',
          },
        }),
      },
      save: 'query_related_to',
    );

    await _call(
      'GET',
      '/classes/Post/doesNotExist',
      token: aliceToken,
      expectError: true,
      save: 'error_101_missing',
    );
    await _call(
      'PUT',
      '/classes/Post/$id',
      token: bobToken,
      body: {'count': 0},
      expectError: true,
      save: 'error_101_acl_denied',
    );
    await _call(
      'POST',
      '/classes/Post',
      token: aliceToken,
      body: {'slug': 'hello-world'},
      expectError: true,
      save: 'error_137_duplicate',
    );
    await _call(
      'POST',
      '/functions/fail',
      body: <String, Object?>{},
      expectError: true,
      save: 'error_141_script_failed',
    );
    await _call(
      'POST',
      '/functions/whoAmI',
      token: aliceToken,
      body: <String, Object?>{},
      save: 'function_call',
    );
    await _call(
      'POST',
      '/functions/failWithCode',
      body: {'code': 137},
      expectError: true,
      save: 'error_137_function',
    );
    await _call(
      'GET',
      '/classes/Post',
      token: 'r:invalid',
      expectError: true,
      save: 'error_209_invalid_session',
    );
    await _call(
      'GET',
      '/classes/Post',
      appId: 'wrong-app-id',
      expectError: true,
      save: 'error_unauthorized',
    );

    const carol = {
      'username': 'carol',
      'password': 'pw',
      'email': 'carol@example.test',
    };
    await _call('POST', '/users', body: carol, save: 'user_sign_up');
    final login = await _call(
      'POST',
      '/login',
      body: {'username': 'carol', 'password': 'pw'},
      save: 'user_log_in',
    );
    await _call(
      'GET',
      '/users/me',
      token: login['sessionToken']! as String,
      save: 'user_me',
    );
    await _call(
      'POST',
      '/login',
      body: {'username': 'carol', 'password': 'wrong'},
      expectError: true,
      save: 'error_101_invalid_credentials',
    );
    await _call(
      'POST',
      '/users',
      body: {...carol, 'email': 'other@example.test'},
      expectError: true,
      save: 'error_202_username_taken',
    );
    await _call(
      'POST',
      '/users',
      body: {...carol, 'username': 'dave'},
      expectError: true,
      save: 'error_203_email_taken',
    );

    final mount = Uri.parse(url).path;
    final batchItems = [
      {
        'method': 'POST',
        'path': '$mount/classes/Author',
        'body': {'name': 'Cy'},
      },
      {
        'method': 'PUT',
        'path': '$mount/classes/Post/doesNotExist',
        'body': {'count': 1},
      },
      {
        'method': 'PUT',
        'path': '$mount/classes/Author/${authors[0]['objectId']}',
        'body': {'name': 'Ann'},
      },
      {
        'method': 'DELETE',
        'path': '$mount/classes/Author/${authors[1]['objectId']}',
      },
    ];
    await _call(
      'POST',
      '/batch',
      token: aliceToken,
      body: {'requests': batchItems},
      save: 'batch_partial_failure',
    );
    await _call(
      'POST',
      '/batch',
      token: aliceToken,
      body: {'requests': batchItems.sublist(0, 2), 'transaction': true},
      expectError: true,
      save: 'batch_transaction_failure',
    );

    return _fixtures;
  }

  Future<void> _reset() async {
    for (final cls in ['Post', 'Author', '_Session', '_User']) {
      await _call('DELETE', '/purge/$cls', master: true, expectError: true);
    }
    for (final cls in ['Post', 'Author']) {
      await _call('DELETE', '/schemas/$cls', master: true, expectError: true);
    }
    await _call(
      'POST',
      '/schemas/Author',
      master: true,
      body: {
        'className': 'Author',
        'fields': {
          'name': {'type': 'String'},
        },
      },
    );
    await _call(
      'POST',
      '/schemas/Post',
      master: true,
      body: {
        'className': 'Post',
        'fields': {
          'title': {'type': 'String'},
          'slug': {'type': 'String'},
          'count': {'type': 'Number'},
          'ratio': {'type': 'Number'},
          'score': {'type': 'Number'},
          'published': {'type': 'Boolean'},
          'publishedAt': {'type': 'Date'},
          'status': {'type': 'String'},
          'tags': {'type': 'Array'},
          'meta': {'type': 'Object'},
          'author': {'type': 'Pointer', 'targetClass': 'Author'},
          'coauthors': {'type': 'Array'},
          'followers': {'type': 'Relation', 'targetClass': 'Author'},
          'attachment': {'type': 'File'},
          'location': {'type': 'GeoPoint'},
          'area': {'type': 'Polygon'},
          'data': {'type': 'Bytes'},
        },
      },
    );
    // parse-server's REST schema API cannot create unique indexes.
    await _exec(switch (backend) {
      'mongo' => [
        'mongo',
        'mongosh',
        '--quiet',
        'parse',
        '--eval',
        'db.Post.createIndex({slug: 1}, {unique: true})',
      ],
      'postgres' => [
        'postgres',
        'psql',
        '-U',
        'postgres',
        '-d',
        'parse',
        '-c',
        'CREATE UNIQUE INDEX post_slug_unique ON "Post" ("slug")',
      ],
      _ => throw ArgumentError(backend),
    });
  }

  Future<void> _exec(List<String> serviceAndCommand) async {
    final result = await Process.run('docker', [
      'compose',
      '-f',
      _compose.toFilePath(),
      'exec',
      '-T',
      ...serviceAndCommand,
    ]);
    if (result.exitCode != 0) {
      throw StateError('${serviceAndCommand.join(' ')}: ${result.stderr}');
    }
  }

  Future<Map<String, Object?>> _signUp(String username) =>
      _call('POST', '/users', body: {'username': username, 'password': 'pw'});

  Map<String, Object?> _pointer(String className, Map<String, Object?> obj) => {
    '__type': 'Pointer',
    'className': className,
    'objectId': obj['objectId'],
  };

  Future<Map<String, Object?>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? rawBody,
    String contentType = 'application/json',
    Map<String, String>? query,
    String? token,
    String appId = appId,
    bool master = false,
    bool expectError = false,
    String? save,
  }) async {
    final request =
        http.Request(
            method,
            Uri.parse('$url$path').replace(queryParameters: query),
          )
          ..headers.addAll({
            'X-Parse-Application-Id': appId,
            'Content-Type': contentType,
            'X-Parse-Session-Token': ?token,
            if (master) 'X-Parse-Master-Key': masterKey,
          });
    if (body != null) request.body = jsonEncode(body);
    if (rawBody != null) request.body = rawBody;
    final response = await http.Response.fromStream(await request.send());

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = response.body;
    }
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok && !expectError) {
      throw StateError(
        '$backend $method $path: '
        '${response.statusCode} ${response.body}',
      );
    }
    if (ok && expectError && save != null) {
      throw StateError(
        '$backend $method $path: expected an error, '
        'got ${response.statusCode} ${response.body}',
      );
    }

    _collectPlaceholders(decoded);
    if (save != null) {
      _fixtures[save] = _normalize({
        'request': {
          'method': method,
          'path': path,
          'query': ?query,
          'body': ?(body ?? rawBody),
        },
        'status': response.statusCode,
        'response': decoded,
      });
    }
    return decoded is Map<String, Object?> ? decoded : const {};
  }

  void _collectPlaceholders(Object? json) {
    switch (json) {
      case Map<String, Object?>():
        for (final MapEntry(:key, :value) in json.entries) {
          if (value is String) {
            switch (key) {
              case 'objectId':
                _placeholder(value, 'obj', 7);
              case 'sessionToken':
                _placeholder(value, 'r:session', 4);
              case 'name' when json.containsKey('url'):
                _placeholder(value, 'file', 4, suffix: '_hello.txt');
            }
          }
          _collectPlaceholders(value);
        }
      case List<Object?>():
        json.forEach(_collectPlaceholders);
    }
  }

  void _placeholder(
    String real,
    String prefix,
    int digits, {
    String suffix = '',
  }) {
    if (_placeholders.containsKey(real)) return;
    final n = _counters[prefix] = (_counters[prefix] ?? 0) + 1;
    _placeholders[real] = '$prefix${'$n'.padLeft(digits, '0')}$suffix';
  }

  Object? _normalize(Object? json) => switch (json) {
    Map<String, Object?>() => {
      for (final MapEntry(:key, :value)
          in json.entries.toList()
            ..sort((a, b) => _replace(a.key).compareTo(_replace(b.key))))
        _replace(
          key,
        ): (key == 'createdAt' || key == 'updatedAt') && value is String
            ? _fixedInstant
            : _normalize(value),
    },
    List<Object?>() => [for (final v in json) _normalize(v)],
    String() => _replace(json),
    _ => json,
  };

  String _replace(String s) {
    for (final MapEntry(:key, :value) in _placeholders.entries) {
      s = s.replaceAll(key, value);
    }
    return s;
  }
}
