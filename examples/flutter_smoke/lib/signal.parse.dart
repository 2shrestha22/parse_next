// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'signal.dart';

final class SignalFields extends Fields<Signal> {
  const SignalFields();

  StringField<Signal> get name => const StringField('name');
  ComparableField<Signal, int> get points => const ComparableField('points');
}

final class SignalOps {
  const SignalOps();

  SetOps<String> get name => const SetOps('name');
  NumOps<int> get points => const NumOps('points');
}

final class $SignalSchema
    implements ParseSchema<Signal, SignalFields, SignalOps> {
  const $SignalSchema();

  @override
  String get className => 'Signal';

  @override
  Signal decode(Json json) => Signal(
    name: json.require<String>('name'),
    points: json.require<int>('points'),
  );

  @override
  Json encode(Signal value) =>
      Json({'name': value.name, 'points': value.points});

  @override
  SignalFields get fields => const SignalFields();

  @override
  SignalOps get ops => const SignalOps();
}
