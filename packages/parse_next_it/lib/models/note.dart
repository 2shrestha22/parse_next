import 'package:parse_next/parse_next.dart';

part 'note.parse.dart';

@ParseClass('Note')
final class Note {
  const Note({required this.text, this.draft, this.place, this.attachment});

  final String text;
  final bool? draft;
  final GeoPoint? place;
  final ParseFile? attachment;
}
