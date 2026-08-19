import '../../../../core/errors/result.dart';

/// Every role needs a Profile screen (General Requirement). Deliberately
/// tiny: only the fields firestore.rules actually lets a user self-edit
/// (`phone`, `photoUrl`, `privacySettings` -- see the users/{userId} rule
/// in Module 4) are here. Everything else about a user (name, role,
/// email, employeeInfo) is either immutable by the user themselves or
/// edited by an admin role through the Employee Detail screen.
abstract class ProfileRepository {
  Future<Result<void>> updateProfile({String? phone, String? photoUrl});
}
