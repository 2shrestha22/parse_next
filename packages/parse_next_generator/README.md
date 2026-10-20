# parse_next_generator

The [build_runner](https://pub.dev/packages/build_runner) code generator for [parse_next](https://pub.dev/packages/parse_next), a type-safe Parse Server SDK. Add it as a dev dependency only.

## Install

```sh
dart pub add parse_next
dart pub add dev:build_runner dev:parse_next_generator
dart run build_runner build
```

## Models

```dart
import 'package:parse_next/parse_next.dart';

part 'post.parse.dart';

@ParseClass('Post')
final class Post {
  const Post({
    required this.title,
    @ParseKey('published_at') this.publishedAt,
    required this.author,
    this.followers = const Relation(),
  });

  final String title;
  final DateTime? publishedAt;
  final Pointer<User> author;
  final Relation<User> followers;
}
```

For each `@ParseClass` the generator writes `PostFields` (typed query fields), `PostOps` (typed update ops) and `$PostSchema`, which `ParseClient.collection` takes.

- It reads the named parameters of the unnamed constructor, generative or factory, and the getters of the same names. Positional parameters are a build error. freezed models work.
- The wire key is the parameter name, or the `@ParseKey` value, which must be unique within the class.
- A field is `String`, `int`, `double`, `num`, `bool`, `DateTime`, an enum (stored by name), a `List` of `String`, `int`, `double`, `num` or `bool`, `Map<String, Object?>`, `Pointer<T>`, `List<Pointer<T>>`, `Relation<T>`, `ParseFile`, `GeoPoint`, `Polygon` or `Uint8List`, or a nullable one of these. `T` must be a `@ParseClass`.
- A `Relation` is non-nullable with the default `const Relation()`: it is never sent or read as a value, only queried and changed through ops.
- A class has at most one `GeoPoint` field, as the server allows.
- Ops follow the type: `unset` exists only on nullable fields, `increment` only on numbers, `add`, `addUnique` and `remove` only on lists.

Anything else fails the build with a message that points at the offending element.

## Cloud functions

```dart
@ParseFunctions()
abstract class Cloud {
  factory Cloud(ParseClient client) = _$Cloud;

  Future<int> score({required Pointer<Post> post, DateTime? since});
  Future<List<Doc<Post>>> trending({required int limit});
}
```

Each abstract method calls the cloud function of the same name, with its named parameters as the params; a null parameter is left out. Parameters take the field types above except `Relation`. A method returns a `Future` of `void`, one of those types, `Doc<T>` or `List<Doc<T>>`, or a nullable one of these. A cloud function that throws raises `ScriptFailed` with its message.
