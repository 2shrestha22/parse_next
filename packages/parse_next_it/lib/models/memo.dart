import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:parse_next/parse_next.dart';

part 'memo.freezed.dart';
part 'memo.parse.dart';

enum Mood { calm, busy }

@freezed
@ParseClass('Memo')
abstract class Memo with _$Memo {
  const factory Memo({
    required String text,
    @ParseKey('due_at') DateTime? dueAt,
    required List<String> tags,
    Mood? mood,
  }) = _Memo;
}
