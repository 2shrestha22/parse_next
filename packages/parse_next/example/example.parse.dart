// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'example.dart';

final class UserFields extends Fields<User> {
  const UserFields();

  StringField<User> get username => const StringField('username');
  StringField<User> get email => const StringField('email');
}

final class UserOps {
  const UserOps();

  SetOps<String> get username => const SetOps('username');
  NullableSetOps<String> get email => const NullableSetOps('email');
}

final class $UserSchema implements ParseSchema<User, UserFields, UserOps> {
  const $UserSchema();

  @override
  String get className => '_User';

  @override
  User decode(Json json) => User(
    username: json.require<String>('username'),
    email: json.opt<String>('email'),
  );

  @override
  Json encode(User value) =>
      Json({'username': value.username, 'email': value.email});

  @override
  UserFields get fields => const UserFields();

  @override
  UserOps get ops => const UserOps();
}

final class PostFields extends Fields<Post> {
  const PostFields();

  StringField<Post> get title => const StringField('title');
  ComparableField<Post, int> get likes => const ComparableField('likes');
  ListField<Post, String> get tags => const ListField('tags');
  PointerField<Post, User, UserFields> get author =>
      const PointerField('author', $UserSchema());
}

final class PostOps {
  const PostOps();

  SetOps<String> get title => const SetOps('title');
  NumOps<int> get likes => const NumOps('likes');
  ListOps<String> get tags => const ListOps('tags');
  SetOps<Pointer<User>> get author =>
      SetOps('author', (v) => v.encode(const $UserSchema()));
}

final class $PostSchema implements ParseSchema<Post, PostFields, PostOps> {
  const $PostSchema();

  @override
  String get className => 'Post';

  @override
  Post decode(Json json) => Post(
    title: json.require<String>('title'),
    likes: json.require<int>('likes'),
    tags: json.requireList<String>('tags'),
    author: json.requirePointer('author', const $UserSchema()),
  );

  @override
  Json encode(Post value) => Json({
    'title': value.title,
    'likes': value.likes,
    'tags': value.tags,
    'author': value.author.encode(const $UserSchema()),
  });

  @override
  PostFields get fields => const PostFields();

  @override
  PostOps get ops => const PostOps();
}
