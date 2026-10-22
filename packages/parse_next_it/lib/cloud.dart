import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';

import 'models/item.dart';
import 'models/user.dart';

part 'cloud.parse.dart';

/// Each `echo` function in cloud/main.js returns its `value` param.
@ParseFunctions()
abstract class Cloud {
  factory Cloud(ParseClient client) = _$Cloud;

  Future<String> echoString({required String value});
  Future<int> echoInt({required int value});
  Future<double> echoDouble({required double value});
  Future<num> echoNum({required num value});
  Future<bool> echoBool({required bool value});
  Future<DateTime> echoDate({required DateTime value});
  Future<Kind> echoEnum({required Kind value});
  Future<List<String>> echoStrings({required List<String> value});
  Future<List<int>> echoInts({required List<int> value});
  Future<Map<String, Object?>> echoMap({required Map<String, Object?> value});
  Future<Pointer<User>> echoPointer({required Pointer<User> value});
  Future<List<Pointer<User>>> echoPointers({
    required List<Pointer<User>> value,
  });
  Future<ParseFile> echoFile({required ParseFile value});
  Future<GeoPoint> echoGeoPoint({required GeoPoint value});
  Future<Polygon> echoPolygon({required Polygon value});
  Future<Uint8List> echoBytes({required Uint8List value});
  Future<List<DateTime>> echoDates({required List<DateTime> value});
  Future<List<GeoPoint>> echoGeoPoints({required List<GeoPoint> value});
  Future<List<ParseFile>> echoFiles({required List<ParseFile> value});
  Future<List<Map<String, Object?>>> echoMaps({
    required List<Map<String, Object?>> value,
  });

  Future<String?> echoNullableString({String? value});
  Future<int?> echoNullableInt({int? value});
  Future<double?> echoNullableDouble({double? value});
  Future<num?> echoNullableNum({num? value});
  Future<bool?> echoNullableBool({bool? value});
  Future<DateTime?> echoNullableDate({DateTime? value});
  Future<Kind?> echoNullableEnum({Kind? value});
  Future<List<String>?> echoNullableStrings({List<String>? value});
  Future<List<int>?> echoNullableInts({List<int>? value});
  Future<Map<String, Object?>?> echoNullableMap({Map<String, Object?>? value});
  Future<Pointer<User>?> echoNullablePointer({Pointer<User>? value});
  Future<List<Pointer<User>>?> echoNullablePointers({
    List<Pointer<User>>? value,
  });
  Future<ParseFile?> echoNullableFile({ParseFile? value});
  Future<GeoPoint?> echoNullableGeoPoint({GeoPoint? value});
  Future<Polygon?> echoNullablePolygon({Polygon? value});
  Future<Uint8List?> echoNullableBytes({Uint8List? value});
  Future<List<Map<String, Object?>>?> echoNullableMaps({
    List<Map<String, Object?>>? value,
  });

  /// The keys of the params object cloud code received.
  Future<List<String>> paramKeys({String? a, required int b, DateTime? c});

  Future<void> ping();
  Future<String> returnsNull();
  Future<String> returnsUndefined();
  Future<void> fail();
  Future<void> failWithCode({required int code});

  /// `request.user`, fetched by the server from the session token.
  Future<Doc<User>?> whoAmI();
  Future<Doc<User>> requireUser();
  Future<List<Doc<User>>> findUsers({required List<String> usernames});

  /// Null when [usernames] is.
  Future<List<Doc<User>>?> findUsersOrNull({List<String>? usernames});
}
