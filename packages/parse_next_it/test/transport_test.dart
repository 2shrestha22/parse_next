import 'package:http/http.dart' as http;
import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/ping.dart';
import 'package:test/test.dart';

import 'support.dart';

const pings = $PingSchema();

/// Passes requests to the server, but drops the connection before sending
/// (`before`) or after the server answered (`after`), in [plan] order.
final class Flaky extends http.BaseClient {
  Flaky(this.plan);

  final List<String> plan;
  final _inner = http.Client();
  final requestIds = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestIds.add(request.headers['X-Parse-Request-Id']);
    final step = plan.isEmpty ? 'pass' : plan.removeAt(0);
    if (step == 'before') throw http.ClientException('dropped', request.url);
    final response = await _inner.send(request);
    if (step == 'after') {
      await response.stream.drain<void>();
      throw http.ClientException('lost', request.url);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  forEachBackend((backend) {
    late ParseClient reader;

    setUpAll(() async {
      await backend.resetClass('Ping', {
        'name': {'type': 'String'},
      });
      reader = backend.client();
    });

    tearDownAll(() => reader.close());

    String unique(String name) =>
        '$name-${DateTime.now().microsecondsSinceEpoch}';

    Future<int> countNamed(String name) => backend
        .client()
        .collection(pings)
        .where((f) => f.name.eq(name))
        .count();

    ParseClient over(Flaky flaky, {bool idempotency = false}) {
      final c = backend.client(
        httpClient: flaky,
        attempts: 3,
        idempotency: idempotency,
      );
      addTearDown(() {
        c.close();
        flaky.close();
      });
      return c;
    }

    test('a query is retried after a dropped connection', () async {
      final name = unique('read');
      await reader.collection(pings).create(Ping(name: name));
      final flaky = Flaky(['before', 'before']);
      final got = await over(
        flaky,
      ).collection(pings).where((f) => f.name.eq(name)).find();
      expect(got, hasLength(1));
      expect(flaky.requestIds, hasLength(3));
    });

    test('a write is not retried, and may have applied', () async {
      final name = unique('once');
      final flaky = Flaky(['after']);
      await expectLater(
        over(flaky).collection(pings).create(Ping(name: name)),
        throwsA(isA<NetworkError>()),
      );
      expect(flaky.requestIds, [null]);
      expect(await countNamed(name), 1);
    });

    test('with idempotency a dropped write is retried and applies', () async {
      final name = unique('retried');
      final flaky = Flaky(['before']);
      final doc = await over(
        flaky,
        idempotency: true,
      ).collection(pings).create(Ping(name: name));
      expect(doc.data.name, name);
      expect(flaky.requestIds, hasLength(2));
      expect(flaky.requestIds.toSet(), hasLength(1));
      expect(await countNamed(name), 1);
    });

    test(
      'with idempotency a lost answer is retried and applies once',
      () async {
        final name = unique('deduped');
        final flaky = Flaky(['after']);
        await expectLater(
          over(
            flaky,
            idempotency: true,
          ).collection(pings).create(Ping(name: name)),
          throwsA(isA<OtherParseError>().having((e) => e.code, 'code', 159)),
        );
        expect(flaky.requestIds.toSet(), hasLength(1));
        expect(await countNamed(name), 1);
      },
    );
  });
}
