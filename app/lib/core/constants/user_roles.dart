/// All roles in the system. Values are the exact strings stored in
/// Firestore `users.role` and in the Firebase Auth custom claim `role` --
/// keep this enum and functions/src/shared/auth/claims.ts in sync manually,
/// since Dart and TS can't share an enum directly.
enum UserRole {
  owner('owner'),
  director('director'),
  principal('principal'),
  admin('admin'),
  registrar('registrar'),
  faculty('faculty'),
  staff('staff'),
  guidance('guidance'),
  student('student'),
  parent('parent');

  final String value;
  const UserRole(this.value);

  static UserRole fromString(String value) => UserRole.values.firstWhere(
        (r) => r.value == value,
        orElse: () => throw ArgumentError('Unknown role: $value'),
      );

  String get displayName => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.director => 'Director',
        UserRole.principal => 'Principal',
        UserRole.admin => 'Admin',
        UserRole.registrar => 'Registrar / Cashier',
        UserRole.faculty => 'Faculty',
        UserRole.staff => 'Staff',
        UserRole.guidance => 'Guidance',
        UserRole.student => 'Student',
        UserRole.parent => 'Parent',
      };

  /// Owner operates outside any school tenant (platform-level).
  bool get isPlatformLevel => this == UserRole.owner;

  /// Roles that manage staff/records vs. roles that only consume them.
  bool get isStaffRole => switch (this) {
        UserRole.director ||
        UserRole.principal ||
        UserRole.admin ||
        UserRole.registrar ||
        UserRole.faculty ||
        UserRole.staff ||
        UserRole.guidance =>
          true,
        UserRole.owner || UserRole.student || UserRole.parent => false,
      };
}

enum UserAccountStatus {
  pendingApproval('pending_approval'),
  active('active'),
  suspended('suspended');

  final String value;
  const UserAccountStatus(this.value);

  static UserAccountStatus fromString(String value) =>
      UserAccountStatus.values.firstWhere((s) => s.value == value);
}
