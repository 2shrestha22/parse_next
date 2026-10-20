import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/backends.dart';
import 'package:test/test.dart';

void forEachBackend(void Function(Backend backend) body) {
  for (final MapEntry(key: name, value: url) in backends.entries) {
    group(name, () => body(Backend(name, url)));
  }
}

final class Backend {
  Backend(this.name, this.url);

  final String name;
  final String url;

  bool get isPostgres => name == 'postgres';

  ParseClient client({
    String appId = appId,
    SessionStore? sessions,
    http.Client? httpClient,
  }) => ParseClient(
    server: Uri.parse(url),
    appId: appId,
    sessions: sessions,
    httpClient: httpClient,
  );

  Future<Map<String, Object?>> rest(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    String? token,
    bool master = false,
    bool allowError = false,
  }) async {
    final request =
        http.Request(
            method,
            Uri.parse('$url$path').replace(queryParameters: query),
          )
          ..headers.addAll({
            'X-Parse-Application-Id': appId,
            'Content-Type': 'application/json',
            'X-Parse-Session-Token': ?token,
            if (master) 'X-Parse-Master-Key': masterKey,
          });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await request.send());
    if (!allowError && response.statusCode >= 300) {
      throw StateError(
        '$name $method $path: '
        '${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  /// Clients may not create classes (`allowClientClassCreation` defaults to
  /// false). Every field is declared because on Postgres a Delete of a field
  /// the schema lacks is a 500 (`column ... does not exist`).
  Future<void> resetClass(
    String className,
    Map<String, Map<String, String>> fields,
  ) async {
    await rest('DELETE', '/purge/$className', master: true, allowError: true);
    await rest('DELETE', '/schemas/$className', master: true, allowError: true);
    await rest(
      'POST',
      '/schemas/$className',
      master: true,
      body: {'className': className, 'fields': fields},
    );
  }

  Future<({String id, String token})> signUp(
    String username, [
    Map<String, Object?> fields = const {},
  ]) async {
    final r = await rest(
      'POST',
      '/users',
      body: {
        'username': '$username-${DateTime.now().microsecondsSinceEpoch}',
        'password': 'pw',
        ...fields,
      },
    );
    final id = r['objectId']! as String;
    // Users are created private (`enforcePrivateUsers` defaults to true in
    // Options/Definitions.js), and the SDK has no session to read them with.
    await rest(
      'PUT',
      '/classes/_User/$id',
      master: true,
      body: {
        'ACL': {
          '*': {'read': true},
          id: {'read': true, 'write': true},
        },
      },
    );
    return (id: id, token: r['sessionToken']! as String);
  }

  Future<List<String>> relatedIds(
    String className,
    String id,
    String key,
    String targetClass,
  ) async {
    final r = await rest(
      'GET',
      '/classes/$targetClass',
      master: true,
      query: {
        'where': jsonEncode({
          r'$relatedTo': {
            'object': {
              '__type': 'Pointer',
              'className': className,
              'objectId': id,
            },
            'key': key,
          },
        }),
      },
    );
    return [
      for (final o in r['results']! as List<Object?>)
        (o! as Map<String, Object?>)['objectId']! as String,
    ];
  }
}
