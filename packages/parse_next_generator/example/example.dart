import 'package:parse_next/parse_next.dart';

part 'example.parse.dart';

enum Status { draft, published }

@ParseClass('_User')
final class User {
  const User({required this.username, @ParseKey('display_name') this.name});

  final String username;
  final String? name;
}

@ParseClass('Post')
final class Post {
  const Post({
    required this.title,
    required this.status,
    required this.publishedAt,
    this.location,
    required this.author,
    this.followers = const Relation(),
  });

  final String title;
  final Status status;
  final DateTime publishedAt;
  final GeoPoint? location;
  final Pointer<User> author;
  final Relation<User> followers;
}

@ParseFunctions()
abstract class Cloud {
  factory Cloud(ParseClient client) = _$Cloud;

  Future<int> score({required Pointer<Post> post, DateTime? since});
  Future<List<Doc<Post>>> trending({required int limit});
}

Future<void> main() async {
  final client = ParseClient(
    server: Uri.parse('http://localhost:1337/parse'),
    appId: 'myAppId',
  );
  final posts = client.collection(const $PostSchema());
  final drafts = await posts
      .where((f) => f.status.eq(Status.draft) & f.location.exists())
      .find();
  for (final d in drafts) {
    await posts.update(d.id, (o) => [o.status.set(Status.published)]);
    print(await Cloud(client).score(post: Pointer(d.id)));
  }
  client.close();
}
