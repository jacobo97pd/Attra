import 'package:attra/src/features/social/domain/friend_group.dart';
import 'package:attra/src/features/social/domain/intent_mode.dart';
import 'package:attra/src/features/social/domain/social_affinity.dart';
import 'package:attra/src/features/social/domain/social_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntentMode.fromValue', () {
    test('desconocido/ausente cae a dating (compat)', () {
      expect(IntentMode.fromValue(null), IntentMode.dating);
      expect(IntentMode.fromValue(''), IntentMode.dating);
      expect(IntentMode.fromValue('xxx'), IntentMode.dating);
    });
    test('parsea wire y nombre', () {
      expect(IntentMode.fromValue('friends'), IntentMode.friends);
      expect(IntentMode.fromValue('BOTH'), IntentMode.both);
      expect(IntentMode.fromValue('groups'), IntentMode.groups);
    });
  });

  group('IntentCompatibility.showsInFeed', () {
    test('dating ve dating y both, no friends-only', () {
      expect(
          IntentCompatibility.showsInFeed(IntentMode.dating, IntentMode.dating),
          isTrue);
      expect(
          IntentCompatibility.showsInFeed(IntentMode.dating, IntentMode.both),
          isTrue);
      expect(
          IntentCompatibility.showsInFeed(
              IntentMode.dating, IntentMode.friends),
          isFalse);
    });
    test('friends ve friends y both, no dating-only', () {
      expect(
          IntentCompatibility.showsInFeed(
              IntentMode.friends, IntentMode.friends),
          isTrue);
      expect(
          IntentCompatibility.showsInFeed(IntentMode.friends, IntentMode.both),
          isTrue);
      expect(
          IntentCompatibility.showsInFeed(
              IntentMode.friends, IntentMode.dating),
          isFalse);
    });
    test('both ve dating, friends y both; no a solo-groups', () {
      expect(
          IntentCompatibility.showsInFeed(IntentMode.both, IntentMode.dating),
          isTrue);
      expect(
          IntentCompatibility.showsInFeed(IntentMode.both, IntentMode.friends),
          isTrue);
      expect(
          IntentCompatibility.showsInFeed(IntentMode.both, IntentMode.groups),
          isFalse);
    });
    test('un perfil solo-groups no aparece en el feed de personas', () {
      for (final IntentMode viewer in IntentMode.values) {
        expect(
            IntentCompatibility.showsInFeed(viewer, IntentMode.groups), isFalse,
            reason: 'groups no debe verse en el feed 1:1 (viewer=$viewer)');
      }
    });
  });

  group('SocialCopy', () {
    test('amistad/grupos usan copy social', () {
      expect(SocialCopy.of(IntentMode.friends).matchNoun, 'Conexión');
      expect(SocialCopy.of(IntentMode.groups).dateNoun, 'Plan');
      expect(SocialCopy.of(IntentMode.friends).likeVerb, 'Conectar');
    });
    test('dating/ambas usan copy romántico', () {
      expect(SocialCopy.of(IntentMode.dating).matchNoun, 'Match');
      expect(SocialCopy.of(IntentMode.both).dateNoun, 'Cita');
    });
  });

  group('SocialAffinity', () {
    test('sin intereses en algún lado → 0', () {
      expect(SocialAffinity.score(<String>[], <String>['a']), 0.0);
      expect(SocialAffinity.score(<String>['a'], <String>[]), 0.0);
    });
    test('normaliza (mayúsculas/espacios) al intersecar', () {
      final Set<String> common = SocialAffinity.commonInterests(
          <String>['Café', ' Arte '], <String>['cafe ', 'arte']);
      // 'Café' vs 'cafe' NO coinciden (no quita tildes), pero 'arte' sí.
      expect(common, contains('arte'));
    });
    test('más solapamiento sobre la unión = más score', () {
      final double a = SocialAffinity.score(
          <String>['music', 'coffee', 'hiking'],
          <String>['music', 'coffee', 'films']);
      final double b = SocialAffinity.score(
          <String>['music', 'coffee', 'hiking'],
          <String>['music', 'x', 'y', 'z', 'w', 'v']);
      expect(a, greaterThan(b));
      expect(a, inInclusiveRange(0.0, 1.0));
    });
  });

  group('FriendGroup', () {
    test('parsea y deriva estado de membresía', () {
      final FriendGroup g = FriendGroup.fromMap('g1', <String, dynamic>{
        'name': 'Senderismo Madrid',
        'city': 'Madrid',
        'interests': <String>['senderismo', 'naturaleza'],
        'memberIds': <String>['a', 'b'],
        'pendingIds': <String>['c'],
        'maxMembers': 6,
        'createdBy': 'a',
        'status': 'open',
      });
      expect(g.memberCount, 2);
      expect(g.isFull, isFalse);
      expect(g.isJoinable, isTrue);
      expect(g.isAdmin('a'), isTrue);
      expect(g.membershipFor('b'), FriendGroupMembership.member);
      expect(g.membershipFor('c'), FriendGroupMembership.pending);
      expect(g.membershipFor('z'), FriendGroupMembership.none);
    });
    test('lleno no es joinable', () {
      final FriendGroup g = FriendGroup.fromMap('g2', <String, dynamic>{
        'memberIds': <String>['a', 'b'],
        'maxMembers': 2,
        'status': 'open',
        'createdBy': 'a',
      });
      expect(g.isFull, isTrue);
      expect(g.isJoinable, isFalse);
    });
  });
}
