# parse_next

A type-safe [Parse Server](https://parseplatform.org) SDK for Dart and Flutter, built on code generation. Models are plain immutable classes; queries and updates are checked by the compiler, with no string keys in app code. It runs on the VM, Flutter and the web, and depends only on `http` and `web_socket_channel`.

Tested against parse-server 9.10.5, on MongoDB and on Postgres.

## Install

```sh
dart pub add parse_next
dart pub add dev:build_runner dev:parse_next_generator
```

## A model

```dart
import 'package:parse_next/parse_next.dart';

part 'post.parse.dart';

@ParseClass('Post')
final class Post {
  const Post({required this.title, required this.likes, required this.tags});

  final String title;
  final int likes;
  final List<String> tags;
}
```

`dart run build_runner build` writes `post.parse.dart` with `PostFields` (query fields), `PostOps` (update ops) and `$PostSchema`. See [parse_next_generator](https://pub.dev/packages/parse_next_generator) for the supported field types.

A saved object is a `Doc<Post>`: `id`, `createdAt`, `updatedAt` and `acl` around the model in `data`. A `Pointer<T>` holds an `id`, and its `loaded` document only when the query included it.

## Create, query, update

```dart
final client = ParseClient(
  server: Uri.parse('https://example.com/parse'),
  appId: 'myAppId',
);
final posts = client.collection(const $PostSchema());

final doc = await posts.create(const Post(title: 'Hello', likes: 0, tags: []));

final popular = await posts
    .where((f) => f.likes.gte(10) & f.tags.contains('dart'))
    .orderBy((f) => f.likes.desc)
    .limit(20)
    .find();

await posts.update(doc.id, (o) => [o.likes.increment(1), o.tags.addUnique(['news'])]);
```

Writes are explicit. `update` sends Parse ops, which the server applies atomically; `replace` overwrites every field, and the last write wins. There is no dirty tracking and no `save()`. A field only offers the constraints and ops Parse supports for its type, so `o.title.increment(1)` does not compile.

`f.tags.containsAny(['dart', 'flutter'])` matches a list holding at least one of the values.

Every failure is a `ParseException`, a sealed class, so a `switch` over it is exhaustive. `DecodeError` is raised where a server row does not match the model; `tryFind()` returns one `Ok` or `Err` per row instead, so one bad row does not fail the page, and the `DecodeError` names the row in `id`. The SDK never retries: after a `NetworkError` a write may or may not have been applied.

## Auth

```dart
final auth = client.auth(const $UserSchema());

await auth.signUp(password: 'secret', user: const User(username: 'ada'));
await auth.logIn('ada', 'secret');
await auth.logInWith('google', {'id': googleUserId, 'id_token': idToken});
final user = await auth.current();
await auth.logOut();
```

`User` is your `@ParseClass('_User')` model. Once logged in, every request carries the session token. `logInWith` logs in the user linked to that provider's `authData`, or signs one up; a token the provider rejects is `InvalidCredentials`. `auth.changes` emits the user on sign-up, either login and `become`, and null on logout or when the server rejects the session (`InvalidSession`, which is still thrown to the caller).

### Session store

By default the session lasts as long as the `ParseClient`. To keep it between runs, pass a `SessionStore`, such as one backed by secure storage on a device:

```dart
abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}
```

- The value is opaque: store it and return it unchanged. It contains the session token, so keep it somewhere private.
- The client reads the store once, on its first request or `Auth` call. A value written to the store by anything else after that is not seen.
- When `write` or `clear` throws, the error reaches the caller, but the client keeps the new session in memory.
- A client built later with the same store starts logged in.

## Live queries

```dart
final sub = posts.where((f) => f.likes.gte(10)).live().listen((event) {
  switch (event) {
    case Subscribed():
      reload();
    case Created(:final doc) || Entered(:final doc) || Updated(:final doc):
      show(doc);
    case Left(:final doc) || Deleted(:final doc):
      hide(doc.id);
  }
});
```

One WebSocket per client carries every subscription. A lost connection is retried with backoff and never ends the stream. **Events missed while disconnected are not replayed**: `Subscribed` is emitted after every (re)connect, so reload the state there. Only classes listed in the server's `liveQuery.classNames` publish events. Conditions the LiveQuery server cannot match correctly, such as `fullText` or any condition on `createdAt`, throw `ArgumentError`.

## Cloud functions, config, batch and files

- `@ParseFunctions` generates a typed client for cloud functions; see parse_next_generator.
- `client.config()` returns the app's config params as `Json`; params marked `masterKeyOnly` are not sent to clients.
- `client.batch()` sends several writes in one request; each returns a handle whose `result` is a `Result`, `Ok` or `Err`, after `send()`. Items are not transactional unless you call `send(transaction: true)`.
- `client.uploadFile(bytes, name: ..., contentType: ...)` returns a `ParseFile` to store in a field.

## Server caveats

MongoDB and Postgres behave differently in places, and some Parse features fail on one of them. The SDK only offers what works on both where it can, and documents the rest on the method concerned. The ones to know before you start:

- Clients cannot create classes (`allowClientClassCreation` is off by default). Create the class and **every field** in the schema first: on Postgres, `replace` and `unset` fail on a field the schema lacks.
- An ACL denial is `ObjectNotFound` (101), the same as a missing object.
- On Postgres, an `update` or `replace` that writes a `Uint8List` field fails with 119; creating one works.
- On Postgres, `addUnique` may reorder the array.
- Strings compare and sort by the database collation (binary on Mongo, the locale on Postgres), and ascending sorts put absent values first on Mongo and last on Postgres. `noneOf` matches an absent field on Mongo only.
- On Mongo, `fullText` uses the class's one text index whatever the field, and fails inside `|` or next to `near`.
- `send(transaction: true)` needs Mongo to run as a replica set.

The full list, with the parse-server source behind each item, is the [server behavior table](https://github.com/2shrestha22/parse_next/blob/main/PLAN.md#server-behavior-found-so-far-parse-server-9105).
