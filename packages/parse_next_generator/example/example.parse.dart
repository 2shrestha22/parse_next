// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'example.dart';

final class UserFields extends Fields<User> {
  const UserFields();

  StringField<User> get username => const StringField('username');
  StringField<User> get name => const StringField('display_name');
}

final class UserOps {
  const UserOps();

  SetOps<String> get username => const SetOps('username');
  NullableSetOps<String> get name => const NullableSetOps('display_name');
}

final class $UserSchema implements ParseSchema<User, UserFields, UserOps> {
  const $UserSchema();

  @override
  String get className => '_User';

  @override
  User decode(Json json) => User(
    username: json.require<String>('username'),
    name: json.opt<String>('display_name'),
  );

  @override
  Json encode(User value) =>
      Json({'username': value.username, 'display_name': value.name});

  @override
  UserFields get fields => const UserFields();

  @override
  UserOps get ops => const UserOps();
}

final class PostFields extends Fields<Post> {
  const PostFields();

  StringField<Post> get title => const StringField('title');
  Field<Post, Status> get status => Field('status', (v) => v.name);
  DateField<Post> get publishedAt => const DateField('publishedAt');
  GeoField<Post> get location => const GeoField('location');
  PointerField<Post, User> get author =>
      const PointerField('author', $UserSchema());
  RelationField<Post, User> get followers =>
      const RelationField('followers', $PostSchema());
}

final class PostOps {
  const PostOps();

  SetOps<String> get title => const SetOps('title');
  SetOps<Status> get status => SetOps('status', (v) => v.name);
  SetOps<DateTime> get publishedAt => const SetOps('publishedAt', encodeDate);
  NullableSetOps<GeoPoint> get location =>
      NullableSetOps('location', (v) => v.toJson());
  SetOps<Pointer<User>> get author =>
      SetOps('author', (v) => v.encode(const $UserSchema()));
  RelationOps<User> get followers =>
      const RelationOps('followers', $UserSchema());
}

final class $PostSchema implements ParseSchema<Post, PostFields, PostOps> {
  const $PostSchema();

  @override
  String get className => 'Post';

  @override
  Post decode(Json json) => Post(
    title: json.require<String>('title'),
    status: json.requireEnum('status', Status.values),
    publishedAt: json.require<DateTime>('publishedAt'),
    location: json.opt<GeoPoint>('location'),
    author: json.requirePointer('author', const $UserSchema()),
    followers: json.relation('followers', const $UserSchema()),
  );

  @override
  Json encode(Post value) => Json({
    'title': value.title,
    'status': value.status.name,
    'publishedAt': encodeDate(value.publishedAt),
    'location': value.location?.toJson(),
    'author': value.author.encode(const $UserSchema()),
  });

  @override
  PostFields get fields => const PostFields();

  @override
  PostOps get ops => const PostOps();
}

final class _$Cloud implements Cloud {
  _$Cloud(this._client);

  final ParseClient _client;

  @override
  Future<int> score({required Pointer<Post> post, DateTime? since}) async =>
      (await _client.callFunction(
        'score',
        Json({
          'post': post.encode(const $PostSchema()),
          if (since != null) 'since': encodeDate(since),
        }),
      )).require<int>('result');

  @override
  Future<List<Doc<Post>>> trending({required int limit}) async =>
      (await _client.callFunction(
        'trending',
        Json({'limit': limit}),
      )).requireDocList('result', const $PostSchema());
}
