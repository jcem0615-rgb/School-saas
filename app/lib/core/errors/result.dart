import 'failures.dart';

/// A lightweight Either-style result type, used instead of pulling in a
/// third-party functional package. Keeps the dependency surface small and
/// keeps failure handling explicit at every call site.
///
/// Usage:
/// ```dart
/// final result = await loginUseCase(email: email, password: password);
/// switch (result) {
///   case Success(:final value) => // value is AppUser
///   case Error(:final failure) => // failure is a typed Failure
/// }
/// ```
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isError => this is Error<T>;

  /// Convenience for UI code that just needs the value or null.
  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Error<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Success<T>() => null,
        Error<T>(:final failure) => failure,
      };

  /// Functional map over the success value, passing failures through.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Success<T>(:final value) => Success(transform(value)),
        Error<T>(:final failure) => Error<R>(failure),
      };
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class Error<T> extends Result<T> {
  final Failure failure;
  const Error(this.failure);
}
