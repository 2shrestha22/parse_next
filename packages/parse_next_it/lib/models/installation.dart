import 'package:parse_next/parse_next.dart';

part 'installation.parse.dart';

@ParseClass('_Installation')
final class Installation {
  const Installation({
    required this.deviceType,
    required this.deviceToken,
    required this.channels,
  });

  final String deviceType;
  final String deviceToken;
  final List<String> channels;
}
