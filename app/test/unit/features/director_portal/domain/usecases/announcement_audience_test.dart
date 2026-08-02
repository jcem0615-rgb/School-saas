import 'package:flutter_test/flutter_test.dart';
import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/features/director_portal/domain/entities/announcement.dart';

/// An announcement carries an audience, and for a long time nothing read
/// it: every role saw every notice, so a student opened the app and read
/// the payroll cut-off date. These pin the targeting itself.
void main() {
  group('AnnouncementAudience.includes', () {
    test('everyone reaches every role', () {
      for (final role in UserRole.values) {
        expect(AnnouncementAudience.everyone.includes(role), isTrue,
            reason: '${role.displayName} must see a school-wide notice');
      }
    });

    test('staffOnly reaches the people who work here, and nobody else', () {
      const outsiders = [UserRole.student, UserRole.parent];
      for (final role in UserRole.values) {
        expect(
          AnnouncementAudience.staffOnly.includes(role),
          !outsiders.contains(role) && !role.isPlatformLevel,
          reason: '${role.displayName} against staff-only',
        );
      }
    });

    test('a named list reaches exactly the roles named', () {
      const audience = AnnouncementAudience(all: false, roles: ['faculty', 'student']);
      expect(audience.includes(UserRole.faculty), isTrue);
      expect(audience.includes(UserRole.student), isTrue);
      expect(audience.includes(UserRole.parent), isFalse);
      expect(audience.includes(UserRole.admin), isFalse);
    });

    // The editor disables Post in this state, but an announcement that
    // predates the picker, or one written straight to Firestore, can
    // still land here -- it must reach nobody rather than everybody.
    test('an empty role list reaches nobody', () {
      const audience = AnnouncementAudience(all: false, roles: []);
      for (final role in UserRole.values) {
        expect(audience.includes(role), isFalse);
      }
    });
  });

  group('label', () {
    test('reads as Everyone when unrestricted', () {
      expect(AnnouncementAudience.everyone.label, 'Everyone');
    });

    test('names the roles, alphabetically, so the same audience reads the same way', () {
      const a = AnnouncementAudience(all: false, roles: ['student', 'faculty']);
      const b = AnnouncementAudience(all: false, roles: ['faculty', 'student']);
      expect(a.label, b.label);
      expect(a.label, 'Faculty, Student');
    });

    test('says so when it reaches nobody', () {
      expect(const AnnouncementAudience(all: false, roles: []).label, 'No one');
    });
  });
}
