@TestOn('vm')
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:test/test.dart';

void main() {
  test('X-Parse-Client-Version carries the pubspec version', () async {
    final version = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    String? sent;
    final client = ParseClient(
      server: Uri.parse('http://parse.test/parse'),
      appId: 'app',
      httpClient: MockClient((r) async {
        sent = r.headers['X-Parse-Client-Version'];
        return http.Response('{}', 200);
      }),
    );
    await client.config().catchError((_) => const Json({}));
    expect(sent, 'parse-next/$version');
  });
}
