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

  /// The role, plus a job title only when the title says something the
  /// role does not.
  ///
  /// Positions are very often just the role typed again -- "Staff /
  /// Staff", "Guidance / Guidance", "Admin / Admin" -- which fills a
  /// phone-width subtitle with nothing. A real title ("Canteen
  /// Supervisor", "College Instructor") still earns its place.
  String labelWith(String? position) {
    final title = position?.trim() ?? '';
    if (title.isEmpty) return displayName;
    if (title.toLowerCase() == displayName.toLowerCase()) return displayName;
    return '$displayName · $title';
  }

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

  /// The school's two oversight roles: they read everything and change
  /// almost nothing.
  ///
  /// A Director runs the school and a Principal runs a division, and
  /// both of them supervise rather than operate. Enrolling a student,
  /// charging a fee, moving stock, editing the timetable, changing what
  /// somebody is paid -- all of that is the Admin's, and neither
  /// `firestore.rules` nor the callables will accept it from these two.
  ///
  /// What they keep is what oversight actually is: deciding an approval
  /// request, posting an announcement, calling a meeting, and picking up
  /// an emergency alert. Those are decisions, not data entry, and taking
  /// them away would leave nobody to make them -- an Admin deciding a
  /// request they filed themselves is not an approval.
  ///
  /// This getter is the single place a screen asks. The rules are the
  /// enforcement; this is what stops the app offering a button that the
  /// rules would then refuse, which is worse than no button at all.
  bool get isOversightOnly =>
      this == UserRole.director || this == UserRole.principal;

  /// Whether this role may change the school's operational records at
  /// all. The plain inverse of [isOversightOnly] for the roles that do
  /// any operating; false for families, who never did.
  bool get canOperate => switch (this) {
        UserRole.admin ||
        UserRole.registrar ||
        UserRole.faculty ||
        UserRole.staff ||
        UserRole.guidance =>
          true,
        UserRole.owner ||
        UserRole.director ||
        UserRole.principal ||
        UserRole.student ||
        UserRole.parent =>
          false,
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
