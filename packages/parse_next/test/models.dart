import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';

final class Author {
  const Author({required this.name});
  final String name;
}

final class AuthorFields extends Fields<Author> {
  const AuthorFields();

  StringField<Author> get name => const StringField('name');
  PointerField<Author, Author, AuthorFields> get mentor =>
      const PointerField('mentor', authorSchema);
}

final class AuthorOps {
  const AuthorOps();

  SetOps<String> get name => const SetOps('name');
}

final class AuthorSchema
    implements ParseSchema<Author, AuthorFields, AuthorOps> {
  const AuthorSchema();

  @override
  String get className => 'Author';

  @override
  Author decode(Json json) => Author(name: json.require<String>('name'));

  @override
  Json encode(Author value) => Json({'name': value.name});

  @override
  AuthorFields get fields => const AuthorFields();

  @override
  AuthorOps get ops => const AuthorOps();
}

const authorSchema = AuthorSchema();

final class Post {
  const Post({
    this.title,
    this.slug,
    this.status,
    this.count,
    this.ratio,
    this.score,
    this.published,
    this.publishedAt,
    this.tags,
    this.meta,
    this.location,
    this.area,
    this.attachment,
    this.data,
    this.author,
    this.coauthors,
    this.followers = const Relation(),
  });

  final String? title;
  final String? slug;
  final String? status;
  final int? count;
  final double? ratio;
  final double? score;
  final bool? published;
  final DateTime? publishedAt;
  final List<String>? tags;
  final Json? meta;
  final GeoPoint? location;
  final Polygon? area;
  final ParseFile? attachment;
  final Uint8List? data;
  final Pointer<Author>? author;
  final List<Pointer<Author>>? coauthors;
  final Relation<Author> followers;

  /// Every field in a form `equals` can compare; pointers become their ids.
  Map<String, Object?> get view => {
    'title': title,
    'slug': slug,
    'status': status,
    'count': count,
    'ratio': ratio,
    'score': score,
    'published': published,
    'publishedAt': publishedAt,
    'tags': tags,
    'meta': meta,
    'location': location,
    'area': area,
    'attachment': attachment,
    'data': data,
    'author': author?.id,
    'coauthors': coauthors?.map((p) => p.id).toList(),
  };
}

final class PostFields extends Fields<Post> {
  const PostFields();

  StringField<Post> get title => const StringField('title');
  StringField<Post> get slug => const StringField('slug');
  StringField<Post> get status => const StringField('status');
  ComparableField<Post, int> get count => const ComparableField('count');
  ComparableField<Post, double> get ratio => const ComparableField('ratio');
  ComparableField<Post, double> get score => const ComparableField('score');
  Field<Post, bool> get published => const Field('published');
  DateField<Post> get publishedAt => const DateField('publishedAt');
  ListField<Post, String> get tags => const ListField('tags');
  MapField<Post> get meta => const MapField('meta');
  GeoField<Post> get location => const GeoField('location');
  PolygonField<Post> get area => const PolygonField('area');
  FileField<Post> get attachment => const FileField('attachment');
  ExistsField<Post> get data => const ExistsField('data');
  PointerField<Post, Author, AuthorFields> get author =>
      const PointerField('author', authorSchema);
  PointerListField<Post, Author, AuthorFields> get coauthors =>
      PointerListField('coauthors', authorSchema);
  RelationField<Post, Author> get followers =>
      const RelationField('followers', postSchema, authorSchema);
}

final class PostOps {
  const PostOps();

  NullableSetOps<String> get title => const NullableSetOps('title');
  NullableSetOps<String> get slug => const NullableSetOps('slug');
  NullableSetOps<String> get status => const NullableSetOps('status');
  NullableNumOps<int> get count => const NullableNumOps('count');
  NullableNumOps<double> get ratio => const NullableNumOps('ratio');
  NullableNumOps<double> get score => const NullableNumOps('score');
  NullableSetOps<bool> get published => const NullableSetOps('published');
  NullableSetOps<DateTime> get publishedAt =>
      const NullableSetOps('publishedAt', encodeDate);
  NullableListOps<String> get tags => const NullableListOps('tags');
  NullableMapOps get meta => const NullableMapOps('meta');
  NullableSetOps<GeoPoint> get location =>
      NullableSetOps('location', (v) => v.toJson());
  NullableSetOps<Polygon> get area => NullableSetOps('area', (v) => v.toJson());
  NullableSetOps<ParseFile> get attachment =>
      NullableSetOps('attachment', (v) => v.toJson());
  NullableSetOps<Uint8List> get data =>
      const NullableSetOps('data', encodeBytes);
  NullableSetOps<Pointer<Author>> get author =>
      NullableSetOps('author', (v) => v.encode(authorSchema));
  NullableListOps<Pointer<Author>> get coauthors =>
      NullableListOps('coauthors', (v) => v.encode(authorSchema));
  RelationOps<Author> get followers =>
      const RelationOps('followers', authorSchema);
}

final class PostSchema implements ParseSchema<Post, PostFields, PostOps> {
  const PostSchema();

  @override
  String get className => 'Post';

  @override
  Post decode(Json json) => Post(
    title: json.opt<String>('title'),
    slug: json.opt<String>('slug'),
    status: json.opt<String>('status'),
    count: json.opt<int>('count'),
    ratio: json.opt<double>('ratio'),
    score: json.opt<double>('score'),
    published: json.opt<bool>('published'),
    publishedAt: json.opt<DateTime>('publishedAt'),
    tags: json.optList<String>('tags'),
    meta: json.opt<Json>('meta'),
    location: json.opt<GeoPoint>('location'),
    area: json.opt<Polygon>('area'),
    attachment: json.opt<ParseFile>('attachment'),
    data: json.opt<Uint8List>('data'),
    author: json.optPointer('author', authorSchema),
    coauthors: json.optPointerList('coauthors', authorSchema),
    followers: json.relation('followers', authorSchema),
  );

  @override
  Json encode(Post value) => Json({
    'title': value.title,
    'slug': value.slug,
    'status': value.status,
    'count': value.count,
    'ratio': value.ratio,
    'score': value.score,
    'published': value.published,
    'publishedAt': _map(value.publishedAt, encodeDate),
    'tags': value.tags,
    'meta': value.meta,
    'location': value.location?.toJson(),
    'area': value.area?.toJson(),
    'attachment': value.attachment?.toJson(),
    'data': _map(value.data, encodeBytes),
    'author': value.author?.encode(authorSchema),
    'coauthors': value.coauthors?.map((p) => p.encode(authorSchema)).toList(),
  });

  @override
  PostFields get fields => const PostFields();

  @override
  PostOps get ops => const PostOps();
}

const postSchema = PostSchema();

Object? _map<V extends Object>(V? v, Object? Function(V) encode) =>
    v == null ? null : encode(v);

final class Member {
  const Member({required this.username, this.email, this.decodedKeys});

  final String username;
  final String? email;

  /// The keys decode was given; null on a value built by hand.
  final Set<String>? decodedKeys;
}

final class MemberFields extends Fields<Member> {
  const MemberFields();
}

final class MemberOps {
  const MemberOps();
}

final class MemberSchema
    implements ParseSchema<Member, MemberFields, MemberOps> {
  const MemberSchema();

  @override
  String get className => '_User';

  @override
  Member decode(Json json) => Member(
    username: json.require<String>('username'),
    email: json.opt<String>('email'),
    decodedKeys: json.keys.toSet(),
  );

  @override
  Json encode(Member value) =>
      Json({'username': value.username, 'email': value.email});

  @override
  MemberFields get fields => const MemberFields();

  @override
  MemberOps get ops => const MemberOps();
}

const memberSchema = MemberSchema();
