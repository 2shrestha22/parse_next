// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'installation.dart';

final class InstallationFields extends Fields<Installation> {
  const InstallationFields();

  StringField<Installation> get deviceType => const StringField('deviceType');
  StringField<Installation> get deviceToken => const StringField('deviceToken');
  ListField<Installation, String> get channels => const ListField('channels');
}

final class InstallationOps {
  const InstallationOps();

  SetOps<String> get deviceType => const SetOps('deviceType');
  SetOps<String> get deviceToken => const SetOps('deviceToken');
  ListOps<String> get channels => const ListOps('channels');
}

final class $InstallationSchema
    implements ParseSchema<Installation, InstallationFields, InstallationOps> {
  const $InstallationSchema();

  @override
  String get className => '_Installation';

  @override
  Installation decode(Json json) => Installation(
    deviceType: json.require<String>('deviceType'),
    deviceToken: json.require<String>('deviceToken'),
    channels: json.requireList<String>('channels'),
  );

  @override
  Json encode(Installation value) => Json({
    'deviceType': value.deviceType,
    'deviceToken': value.deviceToken,
    'channels': value.channels,
  });

  @override
  InstallationFields get fields => const InstallationFields();

  @override
  InstallationOps get ops => const InstallationOps();
}
