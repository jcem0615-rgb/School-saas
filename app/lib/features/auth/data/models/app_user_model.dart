import '../../../../core/constants/user_roles.dart';
import '../../domain/entities/app_user.dart';

/// Data-layer counterpart of [AppUser]. This is the only place in the
/// codebase that knows about Firestore's document shape for `users/*`.
///
/// Deliberately hand-written (no freezed/json_serializable code-gen) so the
/// module compiles standalone without a build_runner pass -- swap in
/// freezed later if desired, the public shape below will not need to change.
class AppUserModel extends AppUser {
  const AppUserModel({
    required super.uid,
    required super.schoolId,
    required super.role,
    required super.firstName,
    required super.lastName,
    required super.email,
    required super.status,
    required super.mustChangePassword,
    required super.qrCode,
    super.photoUrl,
    super.linkedStudentIds,
    super.privacyNoticeVersion,
    super.termsVersion,
  });

  /// Builds the model from a Firestore `users/{userId}` document combined
  /// with the values already trusted from the ID token's custom claims.
  /// [schoolId], [role], and [mustChangePassword] are read from claims
  /// (server-set, unforgeable) rather than the Firestore doc body, so a
  /// client can never spoof its own permissions by editing its profile doc.
  factory AppUserModel.fromFirestore({
    required String uid,
    required Map<String, dynamic> data,
    required String? schoolIdFromClaims,
    required String roleFromClaims,
    required bool mustChangePasswordFromClaims,
  }) {
    return AppUserModel(
      uid: uid,
      schoolId: schoolIdFromClaims,
      role: UserRole.fromString(roleFromClaims),
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      status: UserAccountStatus.fromString(data['status'] as String? ?? 'active'),
      mustChangePassword: mustChangePasswordFromClaims,
      qrCode: data['qrCode'] as String? ?? '',
      linkedStudentIds: (data['linkedStudentIds'] as List<dynamic>?)?.cast<String>(),
      privacyNoticeVersion: (data['privacyNoticeVersion'] as num?)?.toInt(),
      termsVersion: (data['termsVersion'] as num?)?.toInt(),
    );
  }
}
