/// Base failure type returned to the presentation layer.
///
/// The domain/data layers never throw raw exceptions up to the UI.
/// Every repository method returns a `Result<T>` (see result.dart) whose
/// error branch carries one of these typed [Failure]s, so the UI can
/// pattern-match on failure type instead of parsing error strings.
sealed class Failure {
  final String message;
  const Failure(this.message);
}

/// Wraps FirebaseAuth-level problems: bad credentials, disabled user,
/// too many attempts, expired session, etc.
class AuthFailure extends Failure {
  final String code;
  const AuthFailure(this.code, String message) : super(message);
}

/// Firestore/Functions server-side errors (permission-denied, unavailable).
class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

/// Device is offline and the operation cannot be served from cache.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection.']);
}

/// Client-side input validation failed before any network call was made.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

/// Caller's role/claims do not permit the requested action.
class PermissionFailure extends Failure {
  const PermissionFailure(
      [super.message = 'You do not have permission to perform this action.']);
}

/// Catch-all for anything unexpected. Should be rare; if this shows up
/// often in Crashlytics it means a code path is missing explicit handling.
class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong. Please try again.']);
}
