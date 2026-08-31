import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:logicclass/core/errors/app_exceptions.dart';
import 'package:logicclass/features/auth/data/datasources/auth_remote_datasource.dart';

class MockFirebaseAuth extends Mock implements fb_auth.FirebaseAuth {}

class MockUserCredential extends Mock implements fb_auth.UserCredential {}

class MockUser extends Mock implements fb_auth.User {}

class MockFirestore extends Mock implements FirebaseFirestore {}

class MockFunctions extends Mock implements FirebaseFunctions {}

/// Signing in is two network calls, not one.
///
/// `signInWithEmailAndPassword` checks the password; `_hydrateUser` then
/// forces an ID-token refresh to read the custom claims. The second call
/// can fail on its own -- and on a phone on mobile data, the second is at
/// least as likely to fail as the first.
///
/// The datasource's job is to turn a FirebaseAuthException into an
/// AuthException carrying a message a person can act on. This file exists
/// because it used to do that for the first call and not the second: the
/// hydrate future was returned rather than awaited, so its exception was
/// thrown after the try block had already been left behind, and the
/// repository above fell through to its generic handler. Somebody on a
/// weak connection was told "Authentication failed" -- which reads as a
/// wrong password, so they retype it, and it fails again.
void main() {
  late MockFirebaseAuth auth;
  late AuthRemoteDataSource dataSource;

  setUp(() {
    auth = MockFirebaseAuth();
    dataSource = AuthRemoteDataSource(
      auth: auth,
      firestore: MockFirestore(),
      functions: MockFunctions(),
    );
  });

  /// Password accepted, then the token refresh fails with [code].
  void givenTokenRefreshFails(String code) {
    final user = MockUser();
    final credential = MockUserCredential();
    when(() => credential.user).thenReturn(user);
    when(() => user.getIdTokenResult(any()))
        .thenThrow(fb_auth.FirebaseAuthException(code: code));
    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);
  }

  Future<Object?> loginError() async {
    try {
      await dataSource.login(email: 'teacher@school.edu.ph', password: 'correct1');
      return null;
    } catch (e) {
      return e;
    }
  }

  test('a network failure during the token refresh still reaches the user as one',
      () async {
    givenTokenRefreshFails('network-request-failed');

    final error = await loginError();

    expect(error, isA<AuthException>());
    expect((error as AuthException).code, 'network-request-failed');
    expect(error.message, 'Network error. Check your connection and try again.');
  });

  test('a disabled account found at the token refresh says so', () async {
    // The account is disabled between the password check and the claim
    // read -- or, more often, Firebase reports it at the second call
    // rather than the first. Either way the person needs to be told to
    // contact the school, not to try again.
    givenTokenRefreshFails('user-disabled');

    final error = await loginError();

    expect(error, isA<AuthException>());
    expect(
      (error as AuthException).message,
      'This account has been disabled. Contact your school administrator.',
    );
  });

  test('an unrecognised code still becomes an AuthException, not a raw Firebase one',
      () async {
    // The point is the type as much as the wording: everything above this
    // layer catches AuthException, and a FirebaseAuthException escaping
    // here is one the repository can only turn into UnknownFailure.
    givenTokenRefreshFails('some-code-firebase-added-later');

    final error = await loginError();

    expect(error, isA<AuthException>());
    expect(error, isNot(isA<fb_auth.FirebaseAuthException>()));
    expect((error as AuthException).message, 'Authentication failed. Please try again.');
  });

  test('a sign-in that returns no user is reported rather than dereferenced', () async {
    final credential = MockUserCredential();
    when(() => credential.user).thenReturn(null);
    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);

    final error = await loginError();

    expect(error, isA<AuthException>());
    expect((error as AuthException).code, 'unknown');
  });

  test('the password check failing is mapped as it always was', () async {
    // The half that was already correct, pinned so a future edit cannot
    // fix one path by breaking the other.
    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(fb_auth.FirebaseAuthException(code: 'invalid-credential'));

    final error = await loginError();

    expect(error, isA<AuthException>());
    expect((error as AuthException).message, 'Incorrect email or password.');
  });
}
