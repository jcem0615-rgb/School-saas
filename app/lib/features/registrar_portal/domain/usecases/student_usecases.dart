import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/student_summary.dart';
import '../repositories/registrar_repository.dart';

class WatchStudentsUseCase {
  final RegistrarRepository _repository;
  const WatchStudentsUseCase(this._repository);

  Stream<List<StudentSummary>> call() => _repository.watchStudents();
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

    // The explicit ask: every student declares Elementary/High School/
    // College, and a College student must also declare which program --
    // this is enforced here (client-side, fast feedback) AND again
    // server-side in registerStudent.ts (the actual security boundary).
    if (educationLevel == EducationLevel.college && (programId == null || programId.trim().isEmpty)) {
      return Future.value(
        const Error(ValidationFailure('A college student must be enrolled in a program/course.')),
      );
    }
    if (educationLevel != EducationLevel.college && programId != null && programId.trim().isNotEmpty) {
      return Future.value(
        const Error(ValidationFailure('A program can only be set for college students.')),
      );
    }

    return _repository.registerStudent(
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      middleName: middleName?.trim(),
      educationLevel: educationLevel,
      gradeLevel: gradeLevel.trim(),
      section: section.trim(),
      programId: educationLevel == EducationLevel.college ? programId!.trim() : null,
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
