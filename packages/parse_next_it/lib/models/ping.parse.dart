// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'ping.dart';

final class PingFields extends Fields<Ping> {
  const PingFields();

  StringField<Ping> get name => const StringField('name');
}

final class PingOps {
  const PingOps();

  SetOps<String> get name => const SetOps('name');
}

final class $PingSchema implements ParseSchema<Ping, PingFields, PingOps> {
  const $PingSchema();

  @override
  String get className => 'Ping';

  @override
  Ping decode(Json json) => Ping(name: json.require<String>('name'));

  @override
  Json encode(Ping value) => Json({'name': value.name});

  @override
  PingFields get fields => const PingFields();

  @override
  PingOps get ops => const PingOps();
}
