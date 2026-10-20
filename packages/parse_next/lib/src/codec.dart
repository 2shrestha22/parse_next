import 'dart:convert';
import 'dart:typed_data';

import 'exception.dart';

/// A JSON object from the server, with typed reads that raise [DecodeError].
///
/// A key set to `null` and a missing key read the same: Mongo returns a
/// field set to null as `"x": null`, Postgres leaves it out.
///
/// `T` may be a JSON primitive, `num`, `Json`, `Object`, or one of the wire
/// types [DateTime] (`__type: Date`, or the plain ISO string of `createdAt`
/// and `updatedAt`), [GeoPoint], [Polygon], [ParseFile] and
/// [Uint8List] (`__type: Bytes`).
extension type const Json(Map<String, Object?> _map)
    implements Map<String, Object?> {
  T require<T extends Object>(String key) {
    final v = this[key];
    if (v == null) throw DecodeError(key, 'missing');
    return _as<T>(key, v);
  }

  T? opt<T extends Object>(String key) {
    final v = this[key];
    return v == null ? null : _as<T>(key, v);
  }

  List<T> requireList<T extends Object>(String key) =>
      optList<T>(key) ?? (throw DecodeError(key, 'missing'));

  List<T>? optList<T extends Object>(String key) =>
      _list(key, (k, v) => _as<T>(k, v));

  /// Enums are stored by [Enum.name].
  E requireEnum<E extends Enum>(String key, List<E> values) =>
      _enum(key, require<String>(key), values);

  E? optEnum<E extends Enum>(String key, List<E> values) {
    final s = opt<String>(key);
    return s == null ? null : _enum(key, s, values);
  }

  Pointer<T> requirePointer<T>(
          String key, ParseSchema<T, Object?, Object?> schema) =>
      optPointer(key, schema) ?? (throw DecodeError(key, 'missing'));

  Pointer<T>? optPointer<T>(
      String key, ParseSchema<T, Object?, Object?> schema) {
    final v = this[key];
    return v == null ? null : _pointer(key, v, schema);
  }

  List<Pointer<T>> requirePointerList<T>(
          String key, ParseSchema<T, Object?, Object?> schema) =>
      optPointerList(key, schema) ?? (throw DecodeError(key, 'missing'));

  List<Pointer<T>>? optPointerList<T>(
          String key, ParseSchema<T, Object?, Object?> schema) =>
      _list(key, (k, v) => _pointer(k, v, schema));

  Relation<T> relation<T>(String key, ParseSchema<T, Object?, Object?> schema) {
    final v = this[key];
    if (v != null) {
      final j = Json(_typed(key, v, 'Relation'));
      final className = _within(key, () => j.require<String>('className'));
      _checkClass(key, className, schema);
    }
    return Relation<T>();
  }

  List<T>? _list<T>(String key, T Function(String key, Object? v) decode) {
    final v = this[key];
    if (v == null) return null;
    if (v is! List<Object?>) {
      throw DecodeError(key, 'expected a list, got ${_kind(v)}');
    }
    return List.unmodifiable(
      [for (var i = 0; i < v.length; i++) decode('$key[$i]', v[i])],
    );
  }
}

/// A generated `$XSchema`. `F` is the typed fields object that queries pass
/// to their builders, and `O` the typed ops object that `Collection.update`
/// passes to its builder.
abstract interface class ParseSchema<T, F, O> {
  String get className;
  F get fields;
  T decode(Json json);

  /// Must include a null nullable field as `null`, not leave it out:
  /// `Collection.replace` turns it into a `Delete`, and an omitted key keeps
  /// its old value on the server.
  Json encode(T value);
  O get ops;
}

/// A saved object: the model plus the fields the server owns.
final class Doc<T> {
  const Doc({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.acl,
    required this.data,
  });

  factory Doc.decode(Json json, ParseSchema<T, Object?, Object?> schema) => Doc(
        id: json.require<String>('objectId'),
        createdAt: json.require<DateTime>('createdAt'),
        updatedAt: json.require<DateTime>('updatedAt'),
        acl: switch (json['ACL']) { null => null, final v => _acl('ACL', v) },
        data: schema.decode(json),
      );

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Null when the server returned no `ACL`.
  final Acl? acl;
  final T data;
}

final class Pointer<T> {
  const Pointer(this.id) : loaded = null;
  const Pointer._(this.id, this.loaded);

  final String id;

  /// Non-null exactly when the query included this field and the target is
  /// readable.
  final Doc<T>? loaded;

  Map<String, Object?> encode(ParseSchema<T, Object?, Object?> schema) =>
      {'__type': 'Pointer', 'className': schema.className, 'objectId': id};
}

/// Stands for a relation field; its members are read and changed by query
/// and ops, never sent as a value.
final class Relation<T> {
  const Relation();
}

final class GeoPoint {
  GeoPoint(this.latitude, this.longitude) {
    if (!(latitude >= -90 && latitude <= 90)) {
      throw ArgumentError.value(latitude, 'latitude', 'must be within ±90');
    }
    if (!(longitude >= -180 && longitude <= 180)) {
      throw ArgumentError.value(longitude, 'longitude', 'must be within ±180');
    }
  }

  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() =>
      {'__type': 'GeoPoint', 'latitude': latitude, 'longitude': longitude};

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

final class Polygon {
  /// [points] are kept open: a last point equal to the first is dropped,
  /// because the server closes the ring by appending the first point
  /// (`PolygonCoder.JSONToDatabase` in parse-server's `MongoTransform.js`).
  Polygon(List<GeoPoint> points)
      : points = List.unmodifiable(
          points.length > 1 && points.first == points.last
              ? points.sublist(0, points.length - 1)
              : points,
        ) {
    if (this.points.toSet().length < 3) {
      throw ArgumentError.value(
          points, 'points', 'needs at least 3 distinct vertices');
    }
  }

  final List<GeoPoint> points;

  Map<String, Object?> toJson() => {
        '__type': 'Polygon',
        'coordinates': [
          for (final p in points) [p.latitude, p.longitude],
        ],
      };

  @override
  bool operator ==(Object other) {
    if (other is! Polygon || other.points.length != points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (other.points[i] != points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(points);

  @override
  String toString() => 'Polygon($points)';
}

final class ParseFile {
  const ParseFile({required this.name, this.url});

  final String name;

  /// Not sent on encode and ignored by `==`: the server stores only the name
  /// and builds the URL from the request host.
  final String? url;

  Map<String, Object?> toJson() => {'__type': 'File', 'name': name};

  @override
  bool operator ==(Object other) => other is ParseFile && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ParseFile($name, $url)';
}

typedef AclAccess = ({bool read, bool write});

final class Acl {
  /// No access for anyone.
  const Acl() : _entries = const {};

  const Acl._(this._entries);

  factory Acl.publicRead() => const Acl().withPublic();

  final Map<String, AclAccess> _entries;

  AclAccess get public => _get('*');
  AclAccess user(String id) => _get(id);
  AclAccess role(String name) => _get('role:$name');

  Acl withPublic({bool read = true, bool write = false}) =>
      _with('*', read, write);
  Acl withUser(String id, {bool read = true, bool write = false}) =>
      _with(id, read, write);
  Acl withRole(String name, {bool read = true, bool write = false}) =>
      _with('role:$name', read, write);

  AclAccess _get(String key) => _entries[key] ?? (read: false, write: false);

  Acl _with(String key, bool read, bool write) {
    final next = {..._entries}..remove(key);
    if (read || write) next[key] = (read: read, write: write);
    return Acl._(Map.unmodifiable(next));
  }

  Map<String, Object?> toJson() => {
        for (final MapEntry(:key, value: a) in _entries.entries)
          key: {if (a.read) 'read': true, if (a.write) 'write': true},
      };

  @override
  bool operator ==(Object other) =>
      other is Acl &&
      other._entries.length == _entries.length &&
      _entries.entries.every((e) => other._entries[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
      _entries.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'Acl($_entries)';
}

/// Always UTC, truncated to the millisecond the server stores.
Map<String, Object?> encodeDate(DateTime date) =>
    {'__type': 'Date', 'iso': _truncate(date).toIso8601String()};

/// The server rejects empty bytes with 111, since it checks `base64` for
/// truthiness (`getObjectType` in SchemaController.js).
Map<String, Object?> encodeBytes(Uint8List bytes) =>
    {'__type': 'Bytes', 'base64': base64Encode(bytes)};

T _as<T extends Object>(String key, Object? v) {
  if (v is num) {
    if (T == int) {
      final i = v.toInt();
      if (i == v) return i as T;
    } else if (T == double) {
      return v.toDouble() as T;
    }
  }
  if (T == DateTime) return _date(key, v) as T;
  if (T == GeoPoint) return _geoPoint(key, v) as T;
  if (T == Polygon) return _polygon(key, v) as T;
  if (T == ParseFile) return _file(key, v) as T;
  if (T == Uint8List) return _bytes(key, v) as T;
  if (v is Map<String, Object?> && v.containsKey('__type')) {
    throw DecodeError(key, 'unexpected __type ${v['__type']}');
  }
  if (v is T) return v;
  throw DecodeError(key, 'expected $T, got ${_kind(v)}');
}

String _kind(Object? v) => switch (v) {
      null => 'null',
      String() => 'string',
      num() => 'number',
      bool() => 'bool',
      List<Object?>() => 'list',
      Map<String, Object?>() when v.containsKey('__type') =>
        '__type ${v['__type']}',
      Map<String, Object?>() => 'object',
      _ => 'unknown',
    };

R _within<R>(String key, R Function() decode) {
  try {
    return decode();
  } on DecodeError catch (e) {
    throw DecodeError('$key.${e.key}', e.message);
  }
}

Map<String, Object?> _typed(String key, Object? v, String type) {
  if (v is Map<String, Object?> && v['__type'] == type) return v;
  throw DecodeError(key, 'expected __type $type, got ${_kind(v)}');
}

void _checkClass(String key, String className,
    ParseSchema<Object?, Object?, Object?> schema) {
  if (className != schema.className) {
    throw DecodeError(
        '$key.className', 'expected ${schema.className}, got $className');
  }
}

DateTime _truncate(DateTime d) =>
    DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true);

DateTime _parseIso(String key, String s) {
  final d = DateTime.tryParse(s);
  // Without a zone designator DateTime.parse reads local time.
  if (d == null || !d.isUtc) {
    throw DecodeError(key, 'expected an ISO 8601 UTC date, got "$s"');
  }
  return _truncate(d);
}

DateTime _date(String key, Object? v) {
  if (v is String) return _parseIso(key, v);
  final j = Json(_typed(key, v, 'Date'));
  return _within(key, () => _parseIso('iso', j.require<String>('iso')));
}

GeoPoint _geoPoint(String key, Object? v) {
  final j = Json(_typed(key, v, 'GeoPoint'));
  return _within(key, () {
    final lat = j.require<double>('latitude');
    final lng = j.require<double>('longitude');
    try {
      return GeoPoint(lat, lng);
    } on ArgumentError catch (e) {
      throw DecodeError(e.name ?? '', '${e.message}, got ${e.invalidValue}');
    }
  });
}

Polygon _polygon(String key, Object? v) {
  final j = Json(_typed(key, v, 'Polygon'));
  return _within(key, () {
    final coords = j._list('coordinates', (k, c) {
      if (c is! List<Object?> || c.length != 2) {
        throw DecodeError(k, 'expected [latitude, longitude]');
      }
      final lat = _as<double>('$k[0]', c[0]);
      final lng = _as<double>('$k[1]', c[1]);
      try {
        return GeoPoint(lat, lng);
      } on ArgumentError catch (e) {
        throw DecodeError(k, '${e.message}, got ${e.invalidValue}');
      }
    });
    if (coords == null) throw const DecodeError('coordinates', 'missing');
    try {
      return Polygon(coords);
    } on ArgumentError catch (e) {
      throw DecodeError('coordinates', '${e.message}');
    }
  });
}

ParseFile _file(String key, Object? v) {
  final j = Json(_typed(key, v, 'File'));
  return _within(
    key,
    () => ParseFile(name: j.require<String>('name'), url: j.opt<String>('url')),
  );
}

Uint8List _bytes(String key, Object? v) {
  final j = Json(_typed(key, v, 'Bytes'));
  return _within(key, () {
    final s = j.require<String>('base64');
    try {
      return base64Decode(s);
    } on FormatException {
      throw const DecodeError('base64', 'not valid base64');
    }
  });
}

Pointer<T> _pointer<T>(
    String key, Object? v, ParseSchema<T, Object?, Object?> schema) {
  if (v is! Map<String, Object?>) {
    throw DecodeError(key, 'expected a Pointer, got ${_kind(v)}');
  }
  final j = Json(v);
  final type = j['__type'];
  if (type != 'Pointer' && type != 'Object') {
    throw DecodeError(key, 'expected __type Pointer or Object, got $type');
  }
  _checkClass(key, _within(key, () => j.require<String>('className')), schema);
  return _within(key, () {
    if (type == 'Pointer') return Pointer<T>(j.require<String>('objectId'));
    final doc = Doc.decode(j, schema);
    return Pointer<T>._(doc.id, doc);
  });
}

E _enum<E extends Enum>(String key, String name, List<E> values) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw DecodeError(key, 'unknown value "$name"');
}

Acl _acl(String key, Object? v) {
  if (v is! Map<String, Object?>) {
    throw DecodeError(key, 'expected an object, got ${_kind(v)}');
  }
  var acl = const Acl();
  for (final MapEntry(key: who, value: access) in v.entries) {
    if (access is! Map<String, Object?>) {
      throw DecodeError(
          '$key.$who', 'expected an object, got ${_kind(access)}');
    }
    final j = Json(access);
    acl = _within('$key.$who', () {
      final read = j.opt<bool>('read') ?? false;
      final write = j.opt<bool>('write') ?? false;
      return acl._with(who, read, write);
    });
  }
  return acl;
}
