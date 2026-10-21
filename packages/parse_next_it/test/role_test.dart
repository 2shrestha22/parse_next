import 'package:parse_next/parse_next.dart';
import 'package:parse_next_it/models/role.dart';
import 'package:parse_next_it/models/secret.dart';
import 'package:parse_next_it/models/user.dart';
import 'package:test/test.dart';

import 'support.dart';

const roles = $RoleSchema();
const secrets = $SecretSchema();

void main() {
  forEachBackend((backend) {
    late ParseClient asAlice;
    late ParseClient asBob;
    late Pointer<User> alice;
    late Pointer<User> bob;

    setUpAll(() async {
      await backend.resetClass('Secret', {
        'text': {'type': 'String'},
      });
      final a = await backend.signUp('ralice');
      final b = await backend.signUp('rbob');
      alice = Pointer(a.id);
      bob = Pointer(b.id);
      asAlice = backend.client();
      asBob = backend.client();
      await asAlice.auth(const $UserSchema()).become(a.token);
      await asBob.auth(const $UserSchema()).become(b.token);
    });

    tearDownAll(() {
      asAlice.close();
      asBob.close();
    });

    String unique(String name) =>
        '$name${DateTime.now().microsecondsSinceEpoch}';

    Future<Doc<Role>> role(String name, Pointer<User> member) async {
      final rolesOf = asAlice.collection(roles);
      final doc = await rolesOf.create(
        Role(name: name),
        acl: const Acl().withPublic().withUser(alice.id, write: true),
      );
      await rolesOf.update(
        doc.id,
        (o) => [
          o.users.add([member]),
        ],
      );
      return doc;
    }

    test('a role ACL lets its users read, and only them', () async {
      final editors = unique('editors');
      await role(editors, alice);
      final secret = await asAlice
          .collection(secrets)
          .create(
            const Secret(text: 'hidden'),
            acl: const Acl().withRole(editors),
          );
      expect(
        (await asAlice.collection(secrets).get(secret.id)).data.text,
        'hidden',
      );
      await expectLater(
        asBob.collection(secrets).get(secret.id),
        throwsA(isA<ObjectNotFound>()),
      );
    });

    test('the roles a user is in, through RelationField.has', () async {
      final name = unique('members');
      final doc = await role(name, bob);
      final found = await asAlice
          .collection(roles)
          .where((f) => f.users.has(bob) & f.name.eq(name))
          .find();
      expect([for (final r in found) r.id], [doc.id]);
      expect(
        await asAlice
            .collection(roles)
            .where((f) => f.users.has(alice) & f.name.eq(name))
            .count(),
        0,
      );
    });
  });
}
