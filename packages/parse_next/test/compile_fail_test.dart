@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

final _header = RegExp(r'^// expect: ([A-Z_]+)$');

void main() {
  test('each compile_fail file produces exactly its expected code', () async {
    final files = Directory('test/compile_fail')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.absolute.path)
        .toList();
    if (files.isEmpty) return;

    // Each file is named explicitly: the directory is excluded in
    // analysis_options.yaml, so analyzing the directory reports nothing.
    final result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '--format=machine',
      ...files,
    ]);
    final actual = {for (final f in files) f: <String>{}};
    for (final line in '${result.stdout}${result.stderr}'.split('\n')) {
      final parts = line.split('|');
      if (parts.length >= 8) actual[parts[3]]?.add(parts[2]);
    }

    final mismatches = <String, String>{};
    for (final path in files) {
      final firstLine = File(path).readAsLinesSync().firstOrNull ?? '';
      final expected = _header.firstMatch(firstLine)?.group(1);
      if (expected == null) {
        mismatches[path] = 'first line must be "// expect: ERROR_CODE"';
      } else if (actual[path]!.length != 1 ||
          actual[path]!.single != expected) {
        mismatches[path] = 'expected {$expected}, got ${actual[path]}';
      }
    }
    expect(mismatches, isEmpty);
  });
}
