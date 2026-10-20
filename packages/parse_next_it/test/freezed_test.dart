import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/memo.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  forEachBackend((backend) {
    late ParseClient client;

    setUpAll(() async {
      await backend.resetClass('Memo', {
        'text': {'type': 'String'},
        'due_at': {'type': 'Date'},
        'tags': {'type': 'Array'},
        'mood': {'type': 'String'},
      });
      client = backend.client();
    });

    tearDownAll(() => client.close());

    for (final memo in [
      Memo(
        text: 'ship it',
        dueAt: DateTime.utc(2024, 5, 6, 7, 8, 9, 10),
        tags: const ['a', 'b'],
        mood: Mood.busy,
      ),
      const Memo(text: 'bare', tags: []),
    ]) {
      test('a freezed model round-trips: ${memo.text}', () async {
        final memos = client.collection(const $MemoSchema());
        final created = await memos.create(memo);
        expect((await memos.get(created.id)).data, memo);
        final stored = await backend.rest('GET', '/classes/Memo/${created.id}');
        expect(stored.containsKey('due_at'), memo.dueAt != null);
      });
    }
  });
}
