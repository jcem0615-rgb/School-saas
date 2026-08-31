import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../admin_portal/data/models/school_branding_model.dart';
import '../../domain/entities/system_check.dart';
import '../../domain/repositories/system_check_repository.dart';

/// Proves a real deployment actually works, before a school is let in.
///
/// Every one of these has been a real first-day failure somewhere: rules
/// left in test mode, a function that never deployed, an index nobody
/// created, a storage bucket that refuses writes. Each is invisible
/// until somebody tries the one screen that needs it, which on an
/// onboarding call is the worst possible moment to find out.
class SystemCheckRepositoryImpl implements SystemCheckRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final String _schoolId;

  const SystemCheckRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
    required FirebaseAuth auth,
    required String schoolId,
  })  : _firestore = firestore,
        _functions = functions,
        _storage = storage,
        _auth = auth,
        _schoolId = schoolId;

  @override
  Future<SystemCheckReport> run() async {
    final checks = <SystemCheck>[
      await _checkFirestoreReachable(),
      await _checkRulesDeployed(),
      await _checkCallablesDeployed(),
      await _checkIndexes(),
      await _checkStorage(),
      await _checkClaims(),
      await _checkBranding(),
    ];
    return SystemCheckReport(checks: checks, ranAt: DateTime.now());
  }

  Future<SystemCheck> _checkFirestoreReachable() async {
    try {
      await _firestore
          .collection(FirestorePaths.students(_schoolId))
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 20));
      return SystemCheck.pass(
        id: 'firestore',
        title: 'Database reachable',
        detail: 'Read from this school\'s records without error.',
      );
    } catch (e) {
      return SystemCheck.fail(
        id: 'firestore',
        title: 'Database reachable',
        detail: 'The read failed: $e',
        remedy: 'Check that the Firebase project id and API key in the build '
            'match the project, and that Cloud Firestore is enabled on it.',
      );
    }
  }

  /// The check that matters most, and the one nobody thinks to run.
  ///
  /// A project left in test mode allows every write from any signed-in
  /// client. Everything in the app still works -- better, in fact, since
  /// nothing is ever refused -- so there is no symptom at all until the
  /// day somebody notices one school reading another's records.
  ///
  /// `scheduleBlocks` refuses every client write outright, so a write
  /// that *succeeds* is proof the deployed rules are not these rules.
  Future<SystemCheck> _checkRulesDeployed() async {
    final probe = _firestore
        .collection(FirestorePaths.scheduleBlocks(_schoolId))
        .doc('__preflight_probe');
    try {
      await probe.set({
        'preflight': true,
        'writtenAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 20));

      // It should not have got here. Clean up so the probe does not
      // become the junk record it was checking for.
      await probe.delete().catchError((_) {});

      return const SystemCheck.fail(
        id: 'rules',
        title: 'Security rules deployed',
        detail: 'A write that the rules must refuse was accepted. The project '
            'is almost certainly still on test-mode rules, which allow any '
            'signed-in user to read and write anything -- including another '
            'school\'s records.',
        remedy: 'Run: firebase deploy --only firestore:rules,storage:rules',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return SystemCheck.pass(
          id: 'rules',
          title: 'Security rules deployed',
          detail: 'A write the rules must refuse was refused.',
        );
      }
      return SystemCheck.fail(
        id: 'rules',
        title: 'Security rules deployed',
        detail: 'The probe failed for an unexpected reason: ${e.code}. '
            '${e.message ?? ''}',
        remedy: 'Run: firebase deploy --only firestore:rules,storage:rules',
      );
    } catch (e) {
      return SystemCheck.fail(
        id: 'rules',
        title: 'Security rules deployed',
        detail: 'The probe failed: $e',
        remedy: 'Run: firebase deploy --only firestore:rules,storage:rules',
      );
    }
  }

  /// Every callable the app depends on, called with arguments it must
  /// reject.
  ///
  /// `invalid-argument` is the pass: it means the function is deployed,
  /// in the right region, and got far enough to validate. `not-found` or
  /// `internal` means it is not there. Nothing is written either way,
  /// because every one of these validates before it touches the
  /// database -- which is a property of how they were written, and this
  /// check quietly depends on it.
  Future<SystemCheck> _checkCallablesDeployed() async {
    const names = [
      'recordPayment',
      'recordRefund',
      'assessStudentFees',
      'voidAssessment',
      'saveScheduleBlock',
      'deleteScheduleBlock',
      'markAttendance',
      'registerStudent',
      'setStudentBalance',
      'provisionUser',
      'decidePaymentSubmission',
      'resetPasswordAdmin',
    ];

    final missing = <String>[];
    final unexpected = <String>[];

    for (final name in names) {
      try {
        // Deliberately empty: every one of these refuses a payload with
        // no schoolId before doing anything.
        await _functions
            .httpsCallable(name)
            .call<dynamic>(<String, dynamic>{}).timeout(const Duration(seconds: 25));
        // Reaching here means it accepted nothing at all as valid input,
        // which is its own problem and worth naming.
        unexpected.add('$name accepted an empty payload');
      } on FirebaseFunctionsException catch (e) {
        switch (e.code) {
          case 'invalid-argument':
          case 'failed-precondition':
          case 'unauthenticated':
          case 'permission-denied':
            // The function itself answered and refused. Whether this
            // account may call it is a different question from whether
            // it is deployed, so all four count as reachable.
            break;
          // Everything below is the backend not answering. The first run
          // of this check against a real deployment reported a Functions
          // backend that was not running at all as a warning, because
          // only 'not-found' was treated as missing -- but a refused
          // connection, a wrong region and a dead deployment all arrive
          // as 'internal' or 'unavailable'. A school with no functions
          // deployed would have been told "worth a look".
          case 'not-found':
          case 'internal':
          case 'unavailable':
          case 'deadline-exceeded':
          case 'cancelled':
            missing.add('$name (${e.code})');
          default:
            unexpected.add('$name returned ${e.code}');
        }
      } catch (e) {
        missing.add('$name ($e)');
      }
    }

    if (missing.isNotEmpty) {
      return SystemCheck.fail(
        id: 'functions',
        title: 'Cloud Functions deployed',
        detail: '${missing.length} of ${names.length} are not reachable: '
            '${missing.join(', ')}. Balances, receipts and timetables are all '
            'written by these, so the app will look like it is saving and '
            'silently not be.',
        remedy: 'Run: cd functions && npm install && npm run build && '
            'firebase deploy --only functions. They deploy to '
            'asia-southeast1; a client pointed at another region sees them '
            'as missing.',
      );
    }
    if (unexpected.isNotEmpty) {
      return SystemCheck.warn(
        id: 'functions',
        title: 'Cloud Functions deployed',
        detail: 'All ${names.length} answered, but: ${unexpected.join('; ')}.',
        remedy: 'Worth a look before letting a school in.',
      );
    }
    return SystemCheck.pass(
      id: 'functions',
      title: 'Cloud Functions deployed',
      detail: 'All ${names.length} answered and refused an empty payload.',
    );
  }

  /// The composite indexes the app's ordinary screens need.
  ///
  /// A missing index does not fail at deploy time and does not fail in
  /// testing on a small dataset -- Firestore serves small collections
  /// without one and then starts refusing as the school grows, which
  /// makes it a fault that appears weeks after go-live.
  Future<SystemCheck> _checkIndexes() async {
    final probes = <String, Query<Map<String, dynamic>>>{
      'students by name': _firestore
          .collection(FirestorePaths.students(_schoolId))
          .where('isDeleted', isEqualTo: false)
          .orderBy('lastName')
          .limit(1),
      'payments in a period': _firestore
          .collection(FirestorePaths.payments(_schoolId))
          .where('isDeleted', isEqualTo: false)
          .orderBy('createdAt')
          .limit(1),
      'assessments for a student': _firestore
          .collection(FirestorePaths.assessments(_schoolId))
          .where('studentId', isEqualTo: '__preflight')
          .where('isDeleted', isEqualTo: false)
          .orderBy('assessedAt', descending: true)
          .limit(1),
      'the timetable': _firestore
          .collection(FirestorePaths.scheduleBlocks(_schoolId))
          .where('schoolYear', isEqualTo: '__preflight')
          .where('isDeleted', isEqualTo: false)
          .orderBy('dayOfWeek')
          .orderBy('startMinute')
          .limit(1),
      'grades for a student': _firestore
          .collection(FirestorePaths.grades(_schoolId))
          .where('studentId', isEqualTo: '__preflight')
          .where('isDeleted', isEqualTo: false)
          .orderBy('submittedAt', descending: true)
          .limit(1),
      // The year-end rollover reads a whole section's marks at once. It
      // is run on one day of the year, which is exactly the kind of
      // query a missing index is discovered by on the day it matters.
      'a section\'s marks for the rollover': _firestore
          .collection(FirestorePaths.grades(_schoolId))
          .where('section', isEqualTo: '__preflight')
          .where('isDeleted', isEqualTo: false)
          .orderBy('submittedAt', descending: true)
          .limit(1),
    };

    final missing = <String>[];
    for (final entry in probes.entries) {
      try {
        await entry.value.get().timeout(const Duration(seconds: 20));
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition') {
          missing.add(entry.key);
        }
        // Anything else -- a permission denial, say -- is not this
        // check's business and is caught by the checks that are.
      } catch (_) {
        // Same.
      }
    }

    if (missing.isEmpty) {
      return SystemCheck.pass(
        id: 'indexes',
        title: 'Database indexes created',
        detail: 'All ${probes.length} probe queries ran.',
      );
    }
    return SystemCheck.fail(
      id: 'indexes',
      title: 'Database indexes created',
      detail: '${missing.length} queries were refused for want of an index: '
          '${missing.join(', ')}. These screens work on a small school and '
          'start failing as it grows.',
      remedy: 'Run: firebase deploy --only firestore:indexes, then wait for '
          'them to finish building in the Firebase console.',
    );
  }

  /// Writes a few bytes and removes them.
  ///
  /// The one probe that really writes. Photographs, signatures and
  /// payment proofs all go to Storage, and a bucket whose rules were
  /// never deployed refuses them one upload at a time -- with the
  /// failure surfacing as a photo that just does not appear.
  ///
  /// A PNG rather than a text file, and that is not cosmetic.
  /// storage.rules accepts only `image/*` and `application/pdf`, so a
  /// text probe is refused by rules that are working perfectly -- which
  /// is how the first real run of this check reported a correct
  /// deployment as broken and told somebody to redeploy the very rules
  /// that had just done their job.
  Future<SystemCheck> _checkStorage() async {
    final ref = _storage.ref('schools/$_schoolId/preflight/probe.png');
    try {
      await ref
          .putData(
            _probePng,
            SettableMetadata(contentType: 'image/png'),
          )
          .timeout(const Duration(seconds: 30));
      await ref.delete().catchError((_) {});
      return SystemCheck.pass(
        id: 'storage',
        title: 'File storage writable',
        detail: 'Wrote and removed a probe file.',
      );
    } on FirebaseException catch (e) {
      return SystemCheck.fail(
        id: 'storage',
        title: 'File storage writable',
        detail: 'The upload failed: ${e.code}. ${e.message ?? ''}',
        remedy: e.code == 'unauthorized'
            ? 'Run: firebase deploy --only storage:rules'
            : 'Check that Cloud Storage is enabled on the project and that '
                'the bucket name in the build is right.',
      );
    } catch (e) {
      return SystemCheck.fail(
        id: 'storage',
        title: 'File storage writable',
        detail: 'The upload failed: $e',
        remedy: 'Check that Cloud Storage is enabled on the project.',
      );
    }
  }

  /// Role and school on the signed-in token.
  ///
  /// Every rule in the system reads these off the token rather than off
  /// a document. An account whose claims were never set can sign in
  /// perfectly well and then be refused by everything, which reads as
  /// the whole app being broken for that one person.
  Future<SystemCheck> _checkClaims() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const SystemCheck.fail(
        id: 'claims',
        title: 'Account claims set',
        detail: 'Nobody is signed in.',
        remedy: 'Sign in and run this again.',
      );
    }
    try {
      final token = await user.getIdTokenResult(true);
      final role = token.claims?['role'] as String?;
      final schoolId = token.claims?['schoolId'] as String?;

      if (role == null || role.isEmpty) {
        return const SystemCheck.fail(
          id: 'claims',
          title: 'Account claims set',
          detail: 'This account has no role on its token. Every rule in the '
              'system reads the role from there, so this account will be '
              'refused by everything while appearing to be signed in.',
          remedy: 'Accounts are created by the provisionUser callable, which '
              'sets the claims. An account made by hand in the Firebase '
              'console has none.',
        );
      }
      if (schoolId != _schoolId) {
        return SystemCheck.fail(
          id: 'claims',
          title: 'Account claims set',
          detail: 'The token says schoolId "$schoolId" and the app is looking '
              'at "$_schoolId".',
          remedy: 'Sign out and back in -- the claim is stamped into the '
              'token at sign-in and an old token survives the change.',
        );
      }
      return SystemCheck.pass(
        id: 'claims',
        title: 'Account claims set',
        detail: 'Signed in as $role for this school.',
      );
    } catch (e) {
      return SystemCheck.fail(
        id: 'claims',
        title: 'Account claims set',
        detail: 'The token could not be read: $e',
        remedy: 'Sign out and back in.',
      );
    }
  }

  /// The smallest valid PNG: a single transparent pixel.
  ///
  /// Small enough that the upload proves reachability rather than
  /// bandwidth, and a real image so the content-type rule sees what it
  /// expects.
  static final Uint8List _probePng = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89,
    0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT
    0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
    0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
    0xAE, 0x42, 0x60, 0x82,
  ]);

  /// Not a deployment fault -- a readiness one.
  ///
  /// A school let in without these has ID cards with no crest, printed
  /// documents with no school name on them, and a privacy notice that
  /// tells families nobody has been named to hear their complaint.
  Future<SystemCheck> _checkBranding() async {
    try {
      final snapshot = await _firestore
          .doc(FirestorePaths.brandingDoc(_schoolId))
          .get()
          .timeout(const Duration(seconds: 20));
      // Through the model rather than off the raw map, so that renaming
      // a branding field breaks this check at compile time instead of
      // silently reporting it as unset forever.
      final branding = SchoolBrandingModel.fromFirestore(snapshot.data());
      final missing = <String>[];
      bool blank(String? value) => value == null || value.trim().isEmpty;

      if (blank(branding.schoolName)) missing.add('school name');
      if (!branding.hasLogo) missing.add('logo');
      if (blank(branding.schoolYear)) missing.add('school year');
      if (blank(branding.principalName)) missing.add('principal');
      if (!branding.hasDataProtectionOfficer) {
        missing.add('Data Protection Officer');
      }

      if (missing.isEmpty) {
        return SystemCheck.pass(
          id: 'branding',
          title: 'School details filled in',
          detail: 'Name, logo, school year, principal and Data Protection '
              'Officer are all set.',
        );
      }
      return SystemCheck.warn(
        id: 'branding',
        title: 'School details filled in',
        detail: 'Not set yet: ${missing.join(', ')}. ID cards, printed '
            'documents and the privacy notice all read from these.',
        remedy: 'Fill them in under School Branding.',
      );
    } catch (e) {
      return SystemCheck.warn(
        id: 'branding',
        title: 'School details filled in',
        detail: 'Could not be read: $e',
      );
    }
  }
}
