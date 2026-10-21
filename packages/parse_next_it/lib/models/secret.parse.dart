// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'secret.dart';

final class SecretFields extends Fields<Secret> {
  const SecretFields();

  StringField<Secret> get text => const StringField('text');
}

final class SecretOps {
  const SecretOps();

  SetOps<String> get text => const SetOps('text');
}

final class $SecretSchema
    implements ParseSchema<Secret, SecretFields, SecretOps> {
  const $SecretSchema();

  @override
  String get className => 'Secret';

  @override
  Secret decode(Json json) => Secret(text: json.require<String>('text'));

  @override
  Json encode(Secret value) => Json({'text': value.text});

  @override
  SecretFields get fields => const SecretFields();

  @override
  SecretOps get ops => const SecretOps();
}
