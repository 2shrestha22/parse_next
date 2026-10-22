library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder parseBuilder(BuilderOptions options) =>
    PartBuilder([_ParseGenerator()], '.parse.dart', writeDescriptions: false);

const _parseClass = TypeChecker.fromUrl(
  'package:parse_next/src/annotations.dart#ParseClass',
);
const _parseFunctions = TypeChecker.fromUrl(
  'package:parse_next/src/annotations.dart#ParseFunctions',
);
const _parseClient = TypeChecker.fromUrl(
  'package:parse_next/src/client.dart#ParseClient',
);
const _doc = TypeChecker.fromUrl('package:parse_next/src/codec.dart#Doc');
const _parseKey = TypeChecker.fromUrl(
  'package:parse_next/src/annotations.dart#ParseKey',
);
const _pointer = TypeChecker.fromUrl(
  'package:parse_next/src/codec.dart#Pointer',
);
const _relation = TypeChecker.fromUrl(
  'package:parse_next/src/codec.dart#Relation',
);
const _parseFile = TypeChecker.fromUrl(
  'package:parse_next/src/codec.dart#ParseFile',
);
const _geoPoint = TypeChecker.fromUrl(
  'package:parse_next/src/codec.dart#GeoPoint',
);
const _polygon = TypeChecker.fromUrl(
  'package:parse_next/src/codec.dart#Polygon',
);
const _dateTime = TypeChecker.fromUrl('dart:core#DateTime');
const _uint8List = TypeChecker.fromUrl('dart:typed_data#Uint8List');

const _supported =
    'String, int, double, num, bool, DateTime, an enum, a List of String, '
    'int, double, num, bool, DateTime, GeoPoint, ParseFile or '
    'Map<String, Object?>, Map<String, Object?>, Pointer<T>, '
    'List<Pointer<T>>, Relation<T>, ParseFile, GeoPoint, Polygon or '
    'Uint8List, or a nullable one of these except Relation';

final class _ParseGenerator extends Generator {
  @override
  String generate(LibraryReader library, BuildStep buildStep) => [
    for (final a in library.annotatedWith(_parseClass))
      _schema(a.element, a.annotation.read('name').stringValue),
    for (final a in library.annotatedWith(_parseFunctions))
      _functions(a.element),
  ].join('\n\n');
}

typedef _Field = ({String fields, String ops, String decode, String? encode});

String _schema(Element element, String className) {
  if (element is! ClassElement) {
    throw InvalidGenerationSourceError(
      '@ParseClass applies only to classes.',
      element: element,
    );
  }
  final model = element.displayName;
  final constructor = element.unnamedConstructor;
  if (constructor == null) {
    throw InvalidGenerationSourceError(
      '$model has no unnamed constructor, whose named parameters '
      '@ParseClass reads.',
      element: element,
    );
  }

  final owners = <String, String>{};
  String? geoPoint;
  final fields = <String, _Field>{};
  for (final p in constructor.formalParameters) {
    final name = p.displayName;
    if (p.isPositional) {
      throw InvalidGenerationSourceError(
        '$name is positional; a @ParseClass constructor takes only named '
        'parameters.',
        element: p,
      );
    }
    final key =
        _parseKey
            .firstAnnotationOfExact(p)
            ?.getField('name')
            ?.toStringValue() ??
        name;
    if (owners[key] case final other?) {
      throw InvalidGenerationSourceError(
        '$name maps to the wire key "$key", which $other already uses.',
        element: p,
      );
    }
    owners[key] = name;
    if (_geoPoint.isExactlyType(p.type)) {
      if (geoPoint != null) {
        throw InvalidGenerationSourceError(
          '$name is a second GeoPoint field after $geoPoint; the server '
          'allows one per class.',
          element: p,
        );
      }
      geoPoint = name;
    }
    fields[name] = _field(model, p, key);
  }

  return '''
final class ${model}Fields extends Fields<$model> {
  const ${model}Fields();

  ${[for (final f in fields.values) f.fields].join('\n')}
}

final class ${model}Ops {
  const ${model}Ops();

  ${[for (final f in fields.values) f.ops].join('\n')}
}

final class \$${model}Schema implements ParseSchema<$model, ${model}Fields, ${model}Ops> {
  const \$${model}Schema();

  @override
  String get className => '$className';

  @override
  $model decode(Json json) => $model(
    ${[for (final MapEntry(:key, :value) in fields.entries) '$key: ${value.decode},'].join('\n')}
  );

  @override
  Json encode($model value) => Json({
    ${[for (final f in fields.values) ?f.encode].join('\n')}
  });

  @override
  ${model}Fields get fields => const ${model}Fields();

  @override
  ${model}Ops get ops => const ${model}Ops();
}''';
}

_Field _field(String model, FormalParameterElement p, String key) {
  final name = p.displayName;
  final type = p.type;
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  final n = nullable ? 'Nullable' : '';
  final read = nullable ? 'opt' : 'require';
  final value = 'value.$name';
  final k = "'$key'";

  Never unsupported() => throw InvalidGenerationSourceError(
    '${type.getDisplayString()} is not a supported field type. A field is '
    '$_supported.',
    element: p,
  );

  String target(DartType t) {
    final element = t.element;
    if (element == null || !_parseClass.hasAnnotationOfExact(element)) {
      throw InvalidGenerationSourceError(
        '${type.getDisplayString()} points to ${t.getDisplayString()}, which '
        'is not a @ParseClass.',
        element: p,
      );
    }
    return element.displayName;
  }

  _Field plain(String fields, String args, String typeName, String ops) => (
    fields: '$fields$args get $name => const $fields($k);',
    ops: '$n${ops}Ops<$typeName> get $name => const $n${ops}Ops($k);',
    decode: 'json.$read<$typeName>($k)',
    encode: '$k: $value,',
  );

  _Field wire(String fields, String typeName) => (
    fields: '$fields<$model> get $name => const $fields($k);',
    ops:
        '${n}SetOps<$typeName> get $name => '
        '${n}SetOps($k, (v) => v.toJson());',
    decode: 'json.$read<$typeName>($k)',
    encode: '$k: $value${nullable ? '?' : ''}.toJson(),',
  );

  if (type is! InterfaceType) unsupported();
  final args = type.typeArguments;

  if (type.element is EnumElement) {
    final e = type.element.displayName;
    return (
      fields: "Field<$model, $e> get $name => Field($k, (v) => v.name);",
      ops: '${n}SetOps<$e> get $name => ${n}SetOps($k, (v) => v.name);',
      decode: 'json.${read}Enum($k, $e.values)',
      encode: '$k: $value${nullable ? '?' : ''}.name,',
    );
  }
  if (_primitive(type) case final t?) {
    return switch (t) {
      'String' => plain('StringField', '<$model>', t, 'Set'),
      'bool' => plain('Field', '<$model, bool>', t, 'Set'),
      _ => plain('ComparableField', '<$model, $t>', t, 'Num'),
    };
  }
  if (_dateTime.isExactlyType(type)) {
    return (
      fields: 'DateField<$model> get $name => const DateField($k);',
      ops:
          '${n}SetOps<DateTime> get $name => '
          'const ${n}SetOps($k, encodeDate);',
      decode: 'json.$read<DateTime>($k)',
      encode: nullable
          ? '$k: $value == null ? null : encodeDate($value!),'
          : '$k: encodeDate($value),',
    );
  }
  if (_uint8List.isExactlyType(type)) {
    return (
      fields: 'ExistsField<$model> get $name => const ExistsField($k);',
      ops:
          '${n}SetOps<Uint8List> get $name => '
          'const ${n}SetOps($k, encodeBytes);',
      decode: 'json.$read<Uint8List>($k)',
      encode: nullable
          ? '$k: $value == null ? null : encodeBytes($value!),'
          : '$k: encodeBytes($value),',
    );
  }
  if (_isJsonMap(type)) {
    return (
      fields: 'MapField<$model> get $name => const MapField($k);',
      ops: '${n}MapOps get $name => const ${n}MapOps($k);',
      decode: 'json.${read}Map($k)',
      encode: '$k: encodeValue($value),',
    );
  }
  if (_parseFile.isExactlyType(type)) return wire('FileField', 'ParseFile');
  if (_geoPoint.isExactlyType(type)) return wire('GeoField', 'GeoPoint');
  if (_polygon.isExactlyType(type)) return wire('PolygonField', 'Polygon');
  if (_pointer.isExactlyType(type)) {
    final x = target(args[0]);
    return (
      fields:
          'PointerField<$model, $x, ${x}Fields> get $name => '
          'const PointerField($k, \$${x}Schema());',
      ops:
          '${n}SetOps<Pointer<$x>> get $name => '
          '${n}SetOps($k, (v) => v.encode(const \$${x}Schema()));',
      decode: 'json.${read}Pointer($k, const \$${x}Schema())',
      encode: '$k: $value${nullable ? '?' : ''}.encode(const \$${x}Schema()),',
    );
  }
  if (_relation.isExactlyType(type)) {
    final x = target(args[0]);
    if (nullable || !p.hasDefaultValue) {
      throw InvalidGenerationSourceError(
        '$name must be a non-nullable Relation with a default, such as '
        '`this.$name = const Relation()`: a relation is never sent or read '
        'as a value.',
        element: p,
      );
    }
    return (
      fields:
          'RelationField<$model, $x> get $name => '
          'const RelationField($k, \$${model}Schema(), \$${x}Schema());',
      ops:
          'RelationOps<$x> get $name => '
          'const RelationOps($k, \$${x}Schema());',
      decode: 'json.relation($k, const \$${x}Schema())',
      encode: null,
    );
  }
  if (type.isDartCoreList) {
    final e = args[0];
    if (_element(e) case final t?) {
      return (
        fields: 'ListField<$model, $t> get $name => const ListField($k);',
        ops: '${n}ListOps<$t> get $name => const ${n}ListOps($k);',
        decode: 'json.${read}List<$t>($k)',
        encode: '$k: $value,',
      );
    }
    if (_listOf(e) case final l?) {
      final each = '(v) => ${l.encode('v')}';
      return (
        fields:
            'ListField<$model, ${l.type}> get $name => ListField($k, $each);',
        ops: '${n}ListOps<${l.type}> get $name => ${n}ListOps($k, $each);',
        decode: 'json.${l.decode(read, k)}',
        encode: nullable
            ? '$k: $value == null ? null : [for (final e in $value!) ${l.encode('e')}],'
            : '$k: [for (final e in $value) ${l.encode('e')}],',
      );
    }
    if (e is InterfaceType &&
        _pointer.isExactlyType(e) &&
        e.nullabilitySuffix == NullabilitySuffix.none) {
      final x = target(e.typeArguments[0]);
      final each = 'p.encode(const \$${x}Schema())';
      return (
        fields:
            'PointerListField<$model, $x, ${x}Fields> get $name => '
            'PointerListField($k, const \$${x}Schema());',
        ops:
            '${n}ListOps<Pointer<$x>> get $name => '
            '${n}ListOps($k, (v) => v.encode(const \$${x}Schema()));',
        decode: 'json.${read}PointerList($k, const \$${x}Schema())',
        encode: nullable
            ? '$k: $value == null ? null : [for (final p in $value!) $each],'
            : '$k: [for (final p in $value) $each],',
      );
    }
  }
  unsupported();
}

typedef _ListOf = ({
  String type,
  String Function(String e) encode,
  String Function(String read, String key) decode,
});

/// A List element that is encoded one by one: DateTime, GeoPoint, ParseFile
/// or `Map<String, Object?>`.
_ListOf? _listOf(DartType e) {
  if (e is! InterfaceType || e.nullabilitySuffix != NullabilitySuffix.none) {
    return null;
  }
  _ListOf typed(String t, String Function(String e) encode) =>
      (type: t, encode: encode, decode: (read, k) => '${read}List<$t>($k)');
  if (_dateTime.isExactlyType(e)) {
    return typed('DateTime', (e) => 'encodeDate($e)');
  }
  for (final (checker, t) in [
    (_geoPoint, 'GeoPoint'),
    (_parseFile, 'ParseFile'),
  ]) {
    if (checker.isExactlyType(e)) return typed(t, (e) => '$e.toJson()');
  }
  if (_isJsonMap(e)) {
    return (
      type: 'Map<String, Object?>',
      encode: (e) => 'encodeValue($e)',
      decode: (read, k) => '${read}MapList($k)',
    );
  }
  return null;
}

bool _isJsonMap(DartType t) {
  if (t is! InterfaceType || !t.isDartCoreMap) return false;
  final [key, value] = t.typeArguments;
  return _element(key) == 'String' &&
      value.isDartCoreObject &&
      value.nullabilitySuffix == NullabilitySuffix.question;
}

String? _element(DartType t) =>
    t.nullabilitySuffix == NullabilitySuffix.none ? _primitive(t) : null;

String? _primitive(DartType t) {
  if (t.isDartCoreString) return 'String';
  if (t.isDartCoreInt) return 'int';
  if (t.isDartCoreDouble) return 'double';
  if (t.isDartCoreNum) return 'num';
  if (t.isDartCoreBool) return 'bool';
  return null;
}

const _values =
    'String, int, double, num, bool, DateTime, an enum, a List of String, '
    'int, double, num, bool, DateTime, GeoPoint, ParseFile or '
    'Map<String, Object?>, Map<String, Object?>, Pointer<T>, '
    'List<Pointer<T>>, ParseFile, GeoPoint, Polygon, Uint8List';

String _functions(Element element) {
  if (element is! ClassElement) {
    throw InvalidGenerationSourceError(
      '@ParseFunctions applies only to classes.',
      element: element,
    );
  }
  final name = element.displayName;
  final factory = '`factory $name(ParseClient client) = _\$$name;`';
  final constructor = element.unnamedConstructor;
  final params = constructor?.formalParameters ?? const [];
  if (constructor == null ||
      !constructor.isFactory ||
      params.length != 1 ||
      !params.single.isRequiredPositional ||
      !_parseClient.isExactlyType(params.single.type) ||
      !_redirectsTo(constructor, '_\$$name')) {
    throw InvalidGenerationSourceError(
      '$name needs the constructor $factory.',
      element: element,
    );
  }
  if ([...element.getters, ...element.setters].firstOrNull case final a?) {
    throw InvalidGenerationSourceError(
      '${a.displayName} is a getter or setter; a @ParseFunctions class has '
      'only abstract methods.',
      element: a,
    );
  }
  final methods = [for (final m in element.methods) _function(m)];
  return '''
final class _\$$name implements $name {
  _\$$name(this._client);

  final ParseClient _client;

  ${methods.join('\n\n')}
}''';
}

/// The redirect target is in the part being generated, so the analyzer
/// cannot resolve it and [ConstructorElement.redirectedConstructor] is null;
/// the source text is all there is.
bool _redirectsTo(ConstructorElement constructor, String target) {
  final fragment = constructor.firstFragment;
  final source = fragment.libraryFragment.source.contents.data;
  final end = source.indexOf(';', fragment.offset);
  return end >= 0 &&
      RegExp(
        '=\\s*${RegExp.escape(target)}\\s*\$',
      ).hasMatch(source.substring(fragment.offset, end));
}

String _function(MethodElement m) {
  final name = m.displayName;
  if (!m.isAbstract || m.isStatic) {
    throw InvalidGenerationSourceError(
      '$name has a body; a @ParseFunctions class has only abstract methods.',
      element: m,
    );
  }
  final returnType = m.returnType;
  if (returnType is! InterfaceType || !returnType.isDartAsyncFuture) {
    throw InvalidGenerationSourceError(
      '$name returns ${returnType.getDisplayString()}; a cloud function '
      'method returns a Future.',
      element: m,
    );
  }
  final result = returnType.typeArguments.single;

  final body = <String>[];
  final signature = <String>[];
  for (final p in m.formalParameters) {
    final param = p.displayName;
    if (p.isPositional) {
      throw InvalidGenerationSourceError(
        '$param is positional; a cloud function method takes only named '
        'parameters.',
        element: p,
      );
    }
    final type = p.type;
    final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
    final encode = _wire(type, p, docs: false).encode(param);
    final initial = p.defaultValueCode;
    signature.add(
      '${p.isRequired ? 'required ' : ''}${type.getDisplayString()} $param'
      '${initial == null ? '' : ' = $initial'}',
    );
    body.add(
      !nullable
          ? "'$param': $encode,"
          : encode == param
          ? "'$param': ?$param,"
          : "if ($param != null) '$param': $encode,",
    );
  }

  final call = "_client.callFunction('$name', Json({${body.join('\n')}}))";
  final read = result.nullabilitySuffix == NullabilitySuffix.question
      ? 'opt'
      : 'require';
  final returns = result is VoidType
      ? 'async { await $call; }'
      : 'async => (await $call)'
            '.${_wire(result, m, docs: true).decode(read, "'result'")};';
  final params = signature.isEmpty ? '' : '{${signature.join(', ')}}';
  return '''
  @override
  ${returnType.getDisplayString()} $name($params) $returns''';
}

typedef _Wire = ({
  String Function(String value) encode,
  String Function(String read, String key) decode,
});

/// [docs] allows `Doc<X>` and `List<Doc<X>>`, which cloud code can return
/// but which cannot be sent.
_Wire _wire(DartType type, Element at, {required bool docs}) {
  Never unsupported() => throw InvalidGenerationSourceError(
    docs
        ? '${type.getDisplayString()} is not a supported return type. A cloud '
              'function method returns a Future of void, $_values, Doc<T> or '
              'List<Doc<T>>, or a nullable one of these.'
        : '${type.getDisplayString()} is not a supported parameter type. A '
              'parameter is $_values, or a nullable one of these.',
    element: at,
  );

  String schema(DartType t) {
    final element = t.element;
    if (element == null || !_parseClass.hasAnnotationOfExact(element)) {
      throw InvalidGenerationSourceError(
        '${type.getDisplayString()} points to ${t.getDisplayString()}, which '
        'is not a @ParseClass.',
        element: at,
      );
    }
    return 'const \$${element.displayName}Schema()';
  }

  _Wire typed(String t, String Function(String v) encode) =>
      (encode: encode, decode: (read, k) => '$read<$t>($k)');

  if (type is! InterfaceType) unsupported();
  final args = type.typeArguments;
  if (type.element is EnumElement) {
    final e = type.element.displayName;
    return (
      encode: (v) => '$v.name',
      decode: (read, k) => '${read}Enum($k, $e.values)',
    );
  }
  if (_primitive(type) case final t?) return typed(t, (v) => v);
  if (_dateTime.isExactlyType(type)) {
    return typed('DateTime', (v) => 'encodeDate($v)');
  }
  if (_uint8List.isExactlyType(type)) {
    return typed('Uint8List', (v) => 'encodeBytes($v)');
  }
  if (_isJsonMap(type)) {
    return (
      encode: (v) => 'encodeValue($v)',
      decode: (read, k) => '${read}Map($k)',
    );
  }
  for (final (checker, t) in [
    (_parseFile, 'ParseFile'),
    (_geoPoint, 'GeoPoint'),
    (_polygon, 'Polygon'),
  ]) {
    if (checker.isExactlyType(type)) return typed(t, (v) => '$v.toJson()');
  }
  if (_pointer.isExactlyType(type)) {
    final s = schema(args[0]);
    return (
      encode: (v) => '$v.encode($s)',
      decode: (read, k) => '${read}Pointer($k, $s)',
    );
  }
  if (docs && _doc.isExactlyType(type)) {
    final s = schema(args[0]);
    return (
      encode: (_) => unsupported(),
      decode: (read, k) => '${read}Doc($k, $s)',
    );
  }
  if (type.isDartCoreList) {
    final e = args[0];
    if (_element(e) case final t?) {
      return (encode: (v) => v, decode: (read, k) => '${read}List<$t>($k)');
    }
    if (_listOf(e) case final l?) {
      return (
        encode: (v) => '$v.map((e) => ${l.encode('e')}).toList()',
        decode: l.decode,
      );
    }
    if (e is InterfaceType && e.nullabilitySuffix == NullabilitySuffix.none) {
      if (_pointer.isExactlyType(e)) {
        final s = schema(e.typeArguments[0]);
        return (
          encode: (v) => '$v.map((p) => p.encode($s)).toList()',
          decode: (read, k) => '${read}PointerList($k, $s)',
        );
      }
      if (docs && _doc.isExactlyType(e)) {
        final s = schema(e.typeArguments[0]);
        return (
          encode: (_) => unsupported(),
          decode: (read, k) => '${read}DocList($k, $s)',
        );
      }
    }
  }
  unsupported();
}
