import '../../../../core/constants/user_roles.dart';

/// The authenticated user, as understood by the rest of the app.
///
/// This is a pure domain entity: no Firebase types, no JSON. The data
/// layer is responsible for producing this from Firebase Auth + Firestore
/// and the presentation layer only ever depends on this shape, so backend
/// changes never ripple into UI code.
class AppUser {
  final String uid;
  final String? schoolId; // null only for platform-level Owner
  final UserRole role;
  final String firstName;
  final String lastName;
  final String email;
  final String? photoUrl;
  final UserAccountStatus status;
  final bool mustChangePassword;
  final String qrCode;
  final List<String>? linkedStudentIds; // populated for parent role only

  /// The privacy notice version this person has read, or null if they
  /// have not seen one.
  ///
  /// A version rather than a flag, so that changing what the notice says
  /// asks everybody again. A flag would mean the eight hundred people
  /// who agreed to the old wording are recorded as having agreed to the
  /// new one, which is exactly the record a regulator would object to.
  final int? privacyNoticeVersion;

  const AppUser({
    required this.uid,
    required this.schoolId,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.status,
    required this.mustChangePassword,
    required this.qrCode,
    this.photoUrl,
    this.linkedStudentIds,
    this.privacyNoticeVersion,
  });

  String get fullName => '$firstName $lastName';

  bool get isActive => status == UserAccountStatus.active;

  AppUser copyWith({
    String? schoolId,
    UserRole? role,
    String? firstName,
    String? lastName,
    String? email,
    String? photoUrl,
    UserAccountStatus? status,
    bool? mustChangePassword,
    String? qrCode,
    List<String>? linkedStudentIds,
    int? privacyNoticeVersion,
  }) {
    return AppUser(
      uid: uid,
      schoolId: schoolId ?? this.schoolId,
      role: role ?? this.role,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      status: status ?? this.status,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      qrCode: qrCode ?? this.qrCode,
      linkedStudentIds: linkedStudentIds ?? this.linkedStudentIds,
      privacyNoticeVersion: privacyNoticeVersion ?? this.privacyNoticeVersion,
    );
  }

  @override
  bool operator ==(Object other) => other is AppUser && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}
