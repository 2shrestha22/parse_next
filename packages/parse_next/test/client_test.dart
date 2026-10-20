import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parse_next/parse_next.dart';
import 'package:parse_next/src/client.dart';
import 'package:test/test.dart';

final server = Uri.parse('http://parse.test/parse');

/// Records every request it receives and answers each with [respond].
final class Recorder {
  Recorder([http.Response Function()? respond])
    : respond = respond ?? (() => http.Response('{}', 200));

  final http.Response Function() respond;
  final requests = <http.Request>[];

  late final client = MockClient((r) async {
    requests.add(r);
    return respond();
  });

  ParseClient parse({String? clientKey, Uri? server}) => ParseClient(
    server: server ?? Uri.parse('http://parse.test/parse'),
    appId: 'app',
    clientKey: clientKey,
    httpClient: client,
  );
}

Future<ParseException> failure(Future<Json> call) async {
  try {
    await call;
  } on ParseException catch (e) {
    return e;
  }
  fail('expected a ParseException');
}

void main() {
  group('headers', () {
    for (final clientKey in [null, 'ck']) {
      for (final sessionToken in [null, 'r:token']) {
        for (final body in [
          null,
          Json({'a': 1}),
        ]) {
          test('clientKey: $clientKey, sessionToken: $sessionToken, '
              'body: ${body != null}', () async {
            final rec = Recorder();
            await request(
              rec.parse(clientKey: clientKey),
              'POST',
              '/x',
              body: body,
              sessionToken: sessionToken,
            );
            expect(rec.requests.single.headers, {
              'X-Parse-Application-Id': 'app',
              'X-Parse-Client-Key': ?clientKey,
              'X-Parse-Session-Token': ?sessionToken,
              if (body != null) 'Content-Type': 'application/json',
            });
            expect(rec.requests.single.body, body == null ? '' : '{"a":1}');
          });
        }
      }
    }
  });

  group('url', () {
    for (final s in ['http://parse.test/parse', 'http://parse.test/parse/']) {
      test('server $s', () async {
        final rec = Recorder();
        await request(
          rec.parse(server: Uri.parse(s)),
          'GET',
          '/classes/Post',
          query: {'where': '{"a":1}'},
        );
        expect(rec.requests.single.method, 'GET');
        expect(
          rec.requests.single.url.toString(),
          'http://parse.test/parse/classes/Post?where=%7B%22a%22%3A1%7D',
        );
      });
    }
  });

  test('2xx returns the decoded object', () async {
    final rec = Recorder(() => http.Response('{"objectId":"x"}', 201));
    expect(await request(rec.parse(), 'POST', '/classes/Post'), {
      'objectId': 'x',
    });
  });

  test('UTF-8 body without a charset decodes as UTF-8', () async {
    final rec = Recorder(
      () => http.Response.bytes(utf8.encode('{"s":"wörld 👋"}'), 200),
    );
    expect(await request(rec.parse(), 'GET', '/x'), {'s': 'wörld 👋'});
  });

  test('UTF-8 error message without a charset decodes as UTF-8', () async {
    final rec = Recorder(
      () => http.Response.bytes(
        utf8.encode('{"code":141,"error":"ünïcode"}'),
        400,
      ),
    );
    final e = await failure(request(rec.parse(), 'POST', '/functions/f'));
    expect(
      e,
      isA<ScriptFailed>().having((e) => e.message, 'message', 'ünïcode'),
    );
  });

  group('OtherParseError', () {
    test('non-JSON 500 carries the status and the text', () async {
      final rec = Recorder(
        () => http.Response('<html>Bad Gateway</html>', 500),
      );
      expect(
        await failure(request(rec.parse(), 'GET', '/x')),
        isA<OtherParseError>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e.code, 'code', null)
            .having((e) => e.message, 'message', '<html>Bad Gateway</html>'),
      );
    });

    for (final status in [200, 500]) {
      test('empty body with $status', () async {
        final rec = Recorder(() => http.Response('', status));
        expect(
          await failure(request(rec.parse(), 'GET', '/x')),
          isA<OtherParseError>()
              .having((e) => e.status, 'status', status)
              .having((e) => e.code, 'code', null),
        );
      });
    }

    test('unmapped code keeps code and message', () async {
      final rec = Recorder(
        () => http.Response('{"code":119,"error":"nope"}', 400),
      );
      expect(
        await failure(request(rec.parse(), 'GET', '/x')),
        isA<OtherParseError>()
            .having((e) => e.code, 'code', 119)
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'nope'),
      );
    });

    test('uncaught server error reads `message`', () async {
      final rec = Recorder(
        () =>
            http.Response('{"code":1,"message":"Internal server error."}', 500),
      );
      expect(
        await failure(request(rec.parse(), 'GET', '/x')),
        isA<OtherParseError>()
            .having((e) => e.code, 'code', 1)
            .having((e) => e.message, 'message', 'Internal server error.'),
      );
    });

    test('a non-403 without a code is not Unauthorized', () async {
      final rec = Recorder(
        () => http.Response('{"error":"unauthorized"}', 401),
      );
      expect(
        await failure(request(rec.parse(), 'GET', '/x')),
        isA<OtherParseError>().having((e) => e.code, 'code', null),
      );
    });
  });

  group('NetworkError', () {
    test('a ClientException', () async {
      var calls = 0;
      final client = ParseClient(
        server: server,
        appId: 'app',
        httpClient: MockClient((r) async {
          calls++;
          throw http.ClientException('Connection refused', r.url);
        }),
      );
      expect(
        await failure(request(client, 'POST', '/x', body: Json({}))),
        isA<NetworkError>(),
      );
      expect(calls, 1);
    });

    test('a timeout', () async {
      var calls = 0;
      final client = ParseClient(
        server: server,
        appId: 'app',
        timeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) {
          calls++;
          return Completer<http.Response>().future;
        }),
      );
      expect(await failure(request(client, 'GET', '/x')), isA<NetworkError>());
      expect(calls, 1);
    });

    test('a timeout aborts the request', () async {
      final fake = _Capturing(answer: null);
      final client = ParseClient(
        server: server,
        appId: 'app',
        timeout: const Duration(milliseconds: 10),
        httpClient: fake,
      );
      expect(await failure(request(client, 'GET', '/x')), isA<NetworkError>());
      await fake.abortTrigger!.timeout(const Duration(seconds: 1));
    });

    test('a request that answers in time is never aborted', () async {
      final fake = _Capturing(answer: '{}');
      final client = ParseClient(
        server: server,
        appId: 'app',
        timeout: const Duration(milliseconds: 10),
        httpClient: fake,
      );
      await request(client, 'GET', '/x');
      var aborted = false;
      unawaited(fake.abortTrigger!.then((_) => aborted = true));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(aborted, isFalse);
    });
  });

  for (final (status, body) in [
    (200, '{}'),
    (404, '{"code":101,"error":"Object not found."}'),
    (403, '{"error":"unauthorized"}'),
    (500, 'oops'),
  ]) {
    test('exactly one request for a $status', () async {
      final rec = Recorder(() => http.Response(body, status));
      try {
        await request(rec.parse(), 'PUT', '/x', body: Json({}));
      } on ParseException {
        // The count is what is under test.
      }
      expect(rec.requests, hasLength(1));
    });
  }

  test('every subclass is handled without a default', () {
    String name(ParseException e) => switch (e) {
      DecodeError() => 'decode',
      ObjectNotFound() => '101',
      DuplicateValue() => '137',
      ScriptFailed() => '141',
      InvalidSession() => '209',
      Unauthorized() => 'unauthorized',
      NetworkError() => 'network',
      OtherParseError() => 'other',
    };
    expect(name(const NetworkError('x')), 'network');
  });
}

/// Unlike [MockClient], keeps the original request, so its abortTrigger is
/// visible. A null [answer] never responds.
final class _Capturing extends http.BaseClient {
  _Capturing({required this.answer});

  final String? answer;
  Future<void>? abortTrigger;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    abortTrigger = (request as http.Abortable).abortTrigger;
    final body = answer;
    if (body == null) return Completer<http.StreamedResponse>().future;
    return Future.value(
      http.StreamedResponse(Stream.value(utf8.encode(body)), 200),
    );
  }
}
