// expect: NON_EXHAUSTIVE_SWITCH_EXPRESSION
import 'package:parse_next/parse_next.dart';

String name(ParseException e) => switch (e) {
  DecodeError() => 'decode',
  ObjectNotFound() => '101',
  DuplicateValue() => '137',
  ScriptFailed() => '141',
  InvalidSession() => '209',
  InvalidCredentials() => 'credentials',
  UsernameTaken() => '202',
  EmailTaken() => '203',
  Unauthorized() => 'unauthorized',
  NetworkError() => 'network',
};
