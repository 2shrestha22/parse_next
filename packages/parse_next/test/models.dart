import 'dart:typed_data';

import 'package:parse_next/parse_next.dart';

final class Author {
  const Author({required this.name});
  final String name;
}

final class AuthorOps {
  const AuthorOps();

  SetOps<String> get name => const SetOps('name');
}

final class AuthorSchema implements ParseSchema<Author, AuthorOps> {
  const AuthorSchema();

  @override
  String get className => 'Author';

  @override
  Author decode(Json json) => Author(name: json.require<String>('name'));

  @override
  Json encode(Author value) => Json({'name': value.name});

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
  NullableSetOps<Json> get meta => const NullableSetOps('meta');
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

final class PostSchema implements ParseSchema<Post, PostOps> {
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
        'coauthors':
            value.coauthors?.map((p) => p.encode(authorSchema)).toList(),
      });

  @override
  PostOps get ops => const PostOps();
}

const postSchema = PostSchema();

Object? _map<V extends Object>(V? v, Object? Function(V) encode) =>
    v == null ? null : encode(v);
