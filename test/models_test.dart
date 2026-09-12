import 'package:flutter_test/flutter_test.dart';
import 'package:rtc_hub/core/constants.dart';
import 'package:rtc_hub/models/post.dart';
import 'package:rtc_hub/models/profile.dart';

/// These cover the pure logic that does not need a live Supabase project:
/// the signup rule, and the row-to-model mapping every screen depends on.
void main() {
  group('student email rule', () {
    test('accepts a 9-digit Richfield address', () {
      expect(isValidStudentEmail('202512345@my.richfield.ac.za'), isTrue);
      expect(isValidStudentEmail('202512345@richfield.ac.za'), isTrue);
      expect(isValidStudentEmail('  202512345@MY.RICHFIELD.AC.ZA '), isTrue);
    });

    test('accepts the AAA domains', () {
      // §2.1 requires these alongside Richfield's.
      expect(isValidStudentEmail('202512345@my.aaa.ac.za'), isTrue);
      expect(isValidStudentEmail('202512345@aaa.ac.za'), isTrue);
    });

    test('rejects a non-campus domain', () {
      expect(isValidStudentEmail('202512345@gmail.com'), isFalse);
      expect(isValidStudentEmail('202512345@aaa.co.za'), isFalse);
      expect(isValidStudentEmail('202512345@notaaa.ac.za'), isFalse);
    });

    test('rejects a prefix that is not exactly 9 digits', () {
      expect(isValidStudentEmail('2025123@my.richfield.ac.za'), isFalse);
      expect(isValidStudentEmail('2025123456@my.richfield.ac.za'), isFalse);
      expect(isValidStudentEmail('jsmith@my.richfield.ac.za'), isFalse);
    });
  });

  group('Profile', () {
    Profile build(Map<String, dynamic> overrides) => Profile.fromMap({
          'id': 'u1',
          'email': 'a@b.c',
          'full_name': 'Thandi Mokoena',
          'role': 'STUDENT',
          'status': 'ACTIVE',
          ...overrides,
        });

    test('initials take the first two words', () {
      expect(build({}).initials, 'TM');
      expect(build({'full_name': 'Sipho'}).initials, 'S');
      expect(build({'full_name': ''}).initials, '?');
    });

    test('businesses display by company name', () {
      final business = build({
        'role': 'BUSINESS',
        'full_name': 'Jane Doe',
        'company_name': 'Acme Ltd',
      });
      expect(business.displayName, 'Acme Ltd');
      expect(build({}).displayName, 'Thandi Mokoena');
    });

    test('toUpdate never sends role or status', () {
      // The database rejects those for non-admins, so they must not be sent.
      final update = build({}).toUpdate();
      expect(update.containsKey('role'), isFalse);
      expect(update.containsKey('status'), isFalse);
      expect(update.containsKey('profile_completeness'), isFalse);
    });
  });

  group('Post', () {
    test('reads embedded aggregate counts', () {
      final post = Post.fromMap({
        'id': 'p1',
        'author_id': 'u1',
        'type': 'CODE',
        'content': 'help',
        'created_at': '2026-01-01T10:00:00Z',
        'post_reactions': [
          {'count': 4},
        ],
        'comments': [
          {'count': 2},
        ],
      });
      expect(post.reactionCount, 4);
      expect(post.commentCount, 2);
      expect(post.hasCode, isFalse);
    });

    test('an unsolved bounty is open', () {
      final open = Post.fromMap({
        'id': 'p2',
        'author_id': 'u1',
        'content': 'x',
        'created_at': '2026-01-01T10:00:00Z',
        'is_bounty': true,
        'bounty_points': 10,
        'bounty_solved': false,
      });
      expect(open.isOpenBounty, isTrue);
      expect(open.copyWith(bountySolved: true).isOpenBounty, isFalse);
    });
  });
}
