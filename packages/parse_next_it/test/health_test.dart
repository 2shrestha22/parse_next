import 'package:http/http.dart' as http;
import 'package:parse_next_it/backends.dart';
import 'package:test/test.dart';

void main() {
  for (final MapEntry(key: name, value: url) in backends.entries) {
    test('$name health', () async {
      final response = await http.get(Uri.parse('$url/health'));
      expect(response.statusCode, 200);
      expect(response.body, '{"status":"ok"}');
    });
  }
}
