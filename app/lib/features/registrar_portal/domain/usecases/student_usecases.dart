import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../entities/document_release.dart';
import '../entities/student_summary.dart';
import '../repositories/registrar_repository.dart';

class WatchStudentsUseCase {
  final RegistrarRepository _repository;
  const WatchStudentsUseCase(this._repository);

  Stream<List<StudentSummary>> call({int? limit, EducationLevel? educationLevel}) =>
      _repository.watchStudents(limit: limit, educationLevel: educationLevel);
}

/// The whole roster in one read, for export. Kept apart from
/// [WatchStudentsUseCase] so the expensive call has a name of its own.
class FetchAllStudentsUseCase {
  final RegistrarRepository _repository;
  const FetchAllStudentsUseCase(this._repository);

  Future<List<StudentSummary>> call() => _repository.fetchAllStudents();
}

/// Every mark a student has, for the transcript.
class WatchStudentGradesUseCase {
  final RegistrarRepository _repository;
  const WatchStudentGradesUseCase(this._repository);

  Stream<List<Grade>> call(String studentId) => _repository.watchStudentGrades(studentId);
}

/// What has already been handed out for a student.
class WatchDocumentReleasesUseCase {
  final RegistrarRepository _repository;
  const WatchDocumentReleasesUseCase(this._repository);

  Stream<List<DocumentRelease>> call(String studentId) =>
      _repository.watchDocumentReleases(studentId);
}

/// Logs that a TOR or Form 137 was handed over.
///
/// The checks are about the log being worth keeping. A release with no
/// purpose and no named recipient is a row that says a document left the
/// building and nothing else -- which is exactly the question the log
/// exists to answer, so it is refused rather than stored empty.
class RecordDocumentReleaseUseCase {
  final RegistrarRepository _repository;
  const RecordDocumentReleaseUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String studentName,
    required SchoolDocument document,
    required int copies,
    required String purpose,
    required String releasedToName,
    String? releasedToRelation,
    String? remarks,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing student.')));
    }

    final purposeError = Validators.required(purpose, fieldName: 'Purpose');
    if (purposeError != null) return Future.value(Error(ValidationFailure(purposeError)));

    final recipientError = Validators.required(releasedToName, fieldName: 'Released to');
    if (recipientError != null) return Future.value(Error(ValidationFailure(recipientError)));

    // An upper bound as well as a lower one. Nothing stops a registrar
    // handing over ten copies, but a three-digit number in this field is
    // a mis-key, and it would go into the school's "how many have we
    // given this family" answer as if it were real.
    if (copies < 1 || copies > 20) {
      return Future.value(
        const Error(ValidationFailure('Copies must be between 1 and 20.')),
      );
    }

    return _repository.recordDocumentRelease(
      studentId: studentId,
      studentName: studentName,
      document: document,
      copies: copies,
      purpose: purpose.trim(),
      releasedToName: releasedToName.trim(),
      releasedToRelation: releasedToRelation?.trim().isEmpty ?? true
          ? null
          : releasedToRelation!.trim(),
      remarks: remarks?.trim().isEmpty ?? true ? null : remarks!.trim(),
    );
  }
}

/// Records an already-uploaded photo against a student.
class SetStudentPhotoUseCase {
  final RegistrarRepository _repository;
  const SetStudentPhotoUseCase(this._repository);

  Future<Result<void>> call({required String studentId, required String photoUrl}) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing student.')));
    }
    if (photoUrl.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('The upload returned no address.')));
    }
    return _repository.setStudentPhoto(studentId: studentId, photoUrl: photoUrl);
  }
}

class RegisterStudentUseCase {
  final RegistrarRepository _repository;
  const RegisterStudentUseCase(this._repository);

  Future<Result<RegisterStudentOutcome>> call({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
    List<GuardianContact> guardianContacts = const [],
  }) {
    final firstNameError = Validators.required(firstName, fieldName: 'First name');
    if (firstNameError != null) return Future.value(Error(ValidationFailure(firstNameError)));

    final lastNameError = Validators.required(lastName, fieldName: 'Last name');
    if (lastNameError != null) return Future.value(Error(ValidationFailure(lastNameError)));

    final gradeError = Validators.required(gradeLevel, fieldName: 'Grade level');
    if (gradeError != null) return Future.value(Error(ValidationFailure(gradeError)));

    final sectionError = Validators.required(section, fieldName: 'Section');
    if (sectionError != null) return Future.value(Error(ValidationFailure(sectionError)));

    // Required at registration, but still nullable on the record: student
    // records created before this rule existed have no birth date, and
    // they must stay editable rather than becoming unsaveable.
    if (birthDate == null) {
      return Future.value(const Error(ValidationFailure('A birthday is required.')));
    }
    if (birthDate.isAfter(DateTime.now())) {
      return Future.value(const Error(ValidationFailure('A birthday cannot be in the future.')));
    }

    // The explicit ask: every student declares Elementary/High School/
    // College, and a College student must also declare which program --
    // this is enforced here (client-side, fast feedback) AND again
    // server-side in registerStudent.ts (the actual security boundary).
    if (educationLevel.usesProgramCatalogue && (programId == null || programId.trim().isEmpty)) {
      return Future.value(Error(ValidationFailure(
        'A ${educationLevel.displayLabel} student must be enrolled in a '
        '${educationLevel.programLabel.toLowerCase()}.',
      )));
    }
    if (!educationLevel.usesProgramCatalogue &&
        programId != null &&
        programId.trim().isNotEmpty) {
      return Future.value(const Error(ValidationFailure(
        'Only Senior High School and College students enrol in a strand or program.',
      )));
    }

    return _repository.registerStudent(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      middleName: middleName?.trim(),
      educationLevel: educationLevel,
      gradeLevel: gradeLevel.trim(),
      section: section.trim(),
      programId: educationLevel.usesProgramCatalogue ? programId!.trim() : null,
      birthDate: birthDate,
      guardianContacts: guardianContacts,
    );
  }
}

class UpdateStudentUseCase {
  final RegistrarRepository _repository;
  const UpdateStudentUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
    DateTime? birthDate,
  }) {
    final firstNameError = Validators.required(firstName, fieldName: 'First name');
    if (firstNameError != null) return Future.value(Error(ValidationFailure(firstNameError)));

    final lastNameError = Validators.required(lastName, fieldName: 'Last name');
    if (lastNameError != null) return Future.value(Error(ValidationFailure(lastNameError)));

    return _repository.updateStudent(
      studentId: studentId,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      gradeLevel: gradeLevel.trim(),
      section: section.trim(),
      status: status,
      birthDate: birthDate,
    );
  }
}

class ProvisionStudentAccountUseCase {
  final RegistrarRepository _repository;
  const ProvisionStudentAccountUseCase(this._repository);

  Future<Result<ProvisionStudentAccountOutcome>> call({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
  }) {
    final emailError = Validators.email(email);
    if (emailError != null) return Future.value(Error(ValidationFailure(emailError)));

    return _repository.provisionStudentAccount(
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      email: email.trim(),
    );
  }
}

class SetStudentBalanceUseCase {
  final RegistrarRepository _repository;
  const SetStudentBalanceUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required double balance,
    required String remarks,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing student.')));
    }
    // A reason is mandatory: this is the one place a balance changes
    // without a payment behind it, so an unexplained edit would leave the
    // audit trail unable to answer "why does this family owe this?".
    final remarksError = Validators.required(remarks, fieldName: 'Reason');
    if (remarksError != null) {
      return Future.value(Error(ValidationFailure(remarksError)));
    }
    if (balance.isNaN || balance.isInfinite) {
      return Future.value(const Error(ValidationFailure('Enter a valid amount.')));
    }
    return _repository.setStudentBalance(
      studentId: studentId,
      balance: balance,
      remarks: remarks.trim(),
    );
  }
}
