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
    'int, double, num or bool, Map<String, Object?>, Pointer<T>, '
    'List<Pointer<T>>, Relation<T>, ParseFile, GeoPoint, Polygon or '
    'Uint8List, or a nullable one of these except Relation';

final class _ParseGenerator extends Generator {
  @override
  String generate(LibraryReader library, BuildStep buildStep) => [
    for (final a in library.annotatedWith(_parseClass))
      _schema(a.element, a.annotation.read('name').stringValue),
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
      fields:
          'ComparableField<$model, DateTime> get $name => '
          'const ComparableField($k, encodeDate);',
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
  if (type.isDartCoreMap &&
      _element(args[0]) == 'String' &&
      args[1].isDartCoreObject &&
      args[1].nullabilitySuffix == NullabilitySuffix.question) {
    return plain('ExistsField', '<$model>', 'Map<String, Object?>', 'Set');
  }
  if (_parseFile.isExactlyType(type)) return wire('ExistsField', 'ParseFile');
  if (_geoPoint.isExactlyType(type)) return wire('GeoField', 'GeoPoint');
  if (_polygon.isExactlyType(type)) return wire('ExistsField', 'Polygon');
  if (_pointer.isExactlyType(type)) {
    final x = target(args[0]);
    return (
      fields:
          'PointerField<$model, $x> get $name => '
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
          'const RelationField($k, \$${model}Schema());',
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
    if (e is InterfaceType &&
        _pointer.isExactlyType(e) &&
        e.nullabilitySuffix == NullabilitySuffix.none) {
      final x = target(e.typeArguments[0]);
      final each = 'p.encode(const \$${x}Schema())';
      return (
        fields:
            'PointerListField<$model, $x> get $name => '
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
