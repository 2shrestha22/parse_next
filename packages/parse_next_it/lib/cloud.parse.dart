// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'cloud.dart';

final class _$Cloud implements Cloud {
  _$Cloud(this._client);

  final ParseClient _client;

  @override
  Future<String> echoString({required String value}) async =>
      (await _client.callFunction(
        'echoString',
        Json({'value': value}),
      )).require<String>('result');

  @override
  Future<int> echoInt({required int value}) async =>
      (await _client.callFunction(
        'echoInt',
        Json({'value': value}),
      )).require<int>('result');

  @override
  Future<double> echoDouble({required double value}) async =>
      (await _client.callFunction(
        'echoDouble',
        Json({'value': value}),
      )).require<double>('result');

  @override
  Future<num> echoNum({required num value}) async =>
      (await _client.callFunction(
        'echoNum',
        Json({'value': value}),
      )).require<num>('result');

  @override
  Future<bool> echoBool({required bool value}) async =>
      (await _client.callFunction(
        'echoBool',
        Json({'value': value}),
      )).require<bool>('result');

  @override
  Future<DateTime> echoDate({required DateTime value}) async =>
      (await _client.callFunction(
        'echoDate',
        Json({'value': encodeDate(value)}),
      )).require<DateTime>('result');

  @override
  Future<Kind> echoEnum({required Kind value}) async =>
      (await _client.callFunction(
        'echoEnum',
        Json({'value': value.name}),
      )).requireEnum('result', Kind.values);

  @override
  Future<List<String>> echoStrings({required List<String> value}) async =>
      (await _client.callFunction(
        'echoStrings',
        Json({'value': value}),
      )).requireList<String>('result');

  @override
  Future<List<int>> echoInts({required List<int> value}) async =>
      (await _client.callFunction(
        'echoInts',
        Json({'value': value}),
      )).requireList<int>('result');

  @override
  Future<Map<String, Object?>> echoMap({
    required Map<String, Object?> value,
  }) async => (await _client.callFunction(
    'echoMap',
    Json({'value': encodeValue(value)}),
  )).requireMap('result');

  @override
  Future<Pointer<User>> echoPointer({required Pointer<User> value}) async =>
      (await _client.callFunction(
        'echoPointer',
        Json({'value': value.encode(const $UserSchema())}),
      )).requirePointer('result', const $UserSchema());

  @override
  Future<List<Pointer<User>>> echoPointers({
    required List<Pointer<User>> value,
  }) async => (await _client.callFunction(
    'echoPointers',
    Json({'value': value.map((p) => p.encode(const $UserSchema())).toList()}),
  )).requirePointerList('result', const $UserSchema());

  @override
  Future<ParseFile> echoFile({required ParseFile value}) async =>
      (await _client.callFunction(
        'echoFile',
        Json({'value': value.toJson()}),
      )).require<ParseFile>('result');

  @override
  Future<GeoPoint> echoGeoPoint({required GeoPoint value}) async =>
      (await _client.callFunction(
        'echoGeoPoint',
        Json({'value': value.toJson()}),
      )).require<GeoPoint>('result');

  @override
  Future<Polygon> echoPolygon({required Polygon value}) async =>
      (await _client.callFunction(
        'echoPolygon',
        Json({'value': value.toJson()}),
      )).require<Polygon>('result');

  @override
  Future<Uint8List> echoBytes({required Uint8List value}) async =>
      (await _client.callFunction(
        'echoBytes',
        Json({'value': encodeBytes(value)}),
      )).require<Uint8List>('result');

  @override
  Future<String?> echoNullableString({String? value}) async =>
      (await _client.callFunction(
        'echoNullableString',
        Json({'value': ?value}),
      )).opt<String>('result');

  @override
  Future<int?> echoNullableInt({int? value}) async =>
      (await _client.callFunction(
        'echoNullableInt',
        Json({'value': ?value}),
      )).opt<int>('result');

  @override
  Future<double?> echoNullableDouble({double? value}) async =>
      (await _client.callFunction(
        'echoNullableDouble',
        Json({'value': ?value}),
      )).opt<double>('result');

  @override
  Future<num?> echoNullableNum({num? value}) async =>
      (await _client.callFunction(
        'echoNullableNum',
        Json({'value': ?value}),
      )).opt<num>('result');

  @override
  Future<bool?> echoNullableBool({bool? value}) async =>
      (await _client.callFunction(
        'echoNullableBool',
        Json({'value': ?value}),
      )).opt<bool>('result');

  @override
  Future<DateTime?> echoNullableDate({DateTime? value}) async =>
      (await _client.callFunction(
        'echoNullableDate',
        Json({if (value != null) 'value': encodeDate(value)}),
      )).opt<DateTime>('result');

  @override
  Future<Kind?> echoNullableEnum({Kind? value}) async =>
      (await _client.callFunction(
        'echoNullableEnum',
        Json({if (value != null) 'value': value.name}),
      )).optEnum('result', Kind.values);

  @override
  Future<List<String>?> echoNullableStrings({List<String>? value}) async =>
      (await _client.callFunction(
        'echoNullableStrings',
        Json({'value': ?value}),
      )).optList<String>('result');

  @override
  Future<List<int>?> echoNullableInts({List<int>? value}) async =>
      (await _client.callFunction(
        'echoNullableInts',
        Json({'value': ?value}),
      )).optList<int>('result');

  @override
  Future<Map<String, Object?>?> echoNullableMap({
    Map<String, Object?>? value,
  }) async => (await _client.callFunction(
    'echoNullableMap',
    Json({if (value != null) 'value': encodeValue(value)}),
  )).optMap('result');

  @override
  Future<Pointer<User>?> echoNullablePointer({Pointer<User>? value}) async =>
      (await _client.callFunction(
        'echoNullablePointer',
        Json({if (value != null) 'value': value.encode(const $UserSchema())}),
      )).optPointer('result', const $UserSchema());

  @override
  Future<List<Pointer<User>>?> echoNullablePointers({
    List<Pointer<User>>? value,
  }) async => (await _client.callFunction(
    'echoNullablePointers',
    Json({
      if (value != null)
        'value': value.map((p) => p.encode(const $UserSchema())).toList(),
    }),
  )).optPointerList('result', const $UserSchema());

  @override
  Future<ParseFile?> echoNullableFile({ParseFile? value}) async =>
      (await _client.callFunction(
        'echoNullableFile',
        Json({if (value != null) 'value': value.toJson()}),
      )).opt<ParseFile>('result');

  @override
  Future<GeoPoint?> echoNullableGeoPoint({GeoPoint? value}) async =>
      (await _client.callFunction(
        'echoNullableGeoPoint',
        Json({if (value != null) 'value': value.toJson()}),
      )).opt<GeoPoint>('result');

  @override
  Future<Polygon?> echoNullablePolygon({Polygon? value}) async =>
      (await _client.callFunction(
        'echoNullablePolygon',
        Json({if (value != null) 'value': value.toJson()}),
      )).opt<Polygon>('result');

  @override
  Future<Uint8List?> echoNullableBytes({Uint8List? value}) async =>
      (await _client.callFunction(
        'echoNullableBytes',
        Json({if (value != null) 'value': encodeBytes(value)}),
      )).opt<Uint8List>('result');

  @override
  Future<List<String>> paramKeys({
    String? a,
    required int b,
    DateTime? c,
  }) async => (await _client.callFunction(
    'paramKeys',
    Json({'a': ?a, 'b': b, if (c != null) 'c': encodeDate(c)}),
  )).requireList<String>('result');

  @override
  Future<void> ping() async {
    await _client.callFunction('ping', Json({}));
  }

  @override
  Future<String> returnsNull() async => (await _client.callFunction(
    'returnsNull',
    Json({}),
  )).require<String>('result');

  @override
  Future<String> returnsUndefined() async => (await _client.callFunction(
    'returnsUndefined',
    Json({}),
  )).require<String>('result');

  @override
  Future<void> fail() async {
    await _client.callFunction('fail', Json({}));
  }

  @override
  Future<void> failWithCode({required int code}) async {
    await _client.callFunction('failWithCode', Json({'code': code}));
  }

  @override
  Future<Doc<User>?> whoAmI() async => (await _client.callFunction(
    'whoAmI',
    Json({}),
  )).optDoc('result', const $UserSchema());

  @override
  Future<Doc<User>> requireUser() async => (await _client.callFunction(
    'requireUser',
    Json({}),
  )).requireDoc('result', const $UserSchema());

  @override
  Future<List<Doc<User>>> findUsers({required List<String> usernames}) async =>
      (await _client.callFunction(
        'findUsers',
        Json({'usernames': usernames}),
      )).requireDocList('result', const $UserSchema());

  @override
  Future<List<Doc<User>>?> findUsersOrNull({List<String>? usernames}) async =>
      (await _client.callFunction(
        'findUsersOrNull',
        Json({'usernames': ?usernames}),
      )).optDocList('result', const $UserSchema());
}
