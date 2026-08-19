/// Exceptions thrown by data sources (Firebase Auth, Firestore, Functions).
/// These are caught inside repository implementations and translated into
/// [Failure]s before ever reaching the domain/presentation layers -- the
/// domain layer must never know these types exist.

class AuthException implements Exception {
  final String code;
  final String message;
  const AuthException(this.code, this.message);
}

class ServerException implements Exception {
  final String message;
  const ServerException(this.message);
}

class NetworkException implements Exception {
  const NetworkException();
}

class NotFoundException implements Exception {
  final String message;
  const NotFoundException(this.message);
}
