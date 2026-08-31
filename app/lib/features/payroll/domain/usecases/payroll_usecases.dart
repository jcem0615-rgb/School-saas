import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/contribution_scheme.dart';
import '../entities/payslip.dart';
import '../repositories/payroll_repository.dart';

class SaveCompensationUseCase {
  final PayrollRepository _repository;
  const SaveCompensationUseCase(this._repository);

  Future<Result<void>> call(Compensation compensation) {
    if (compensation.rate <= 0) {
      return Future.value(const Error(ValidationFailure(
        'A pay rate has to be more than zero. Somebody on nothing is not '
        'somebody this system should be issuing a payslip to.',
      )));
    }
    if (compensation.allowance < 0) {
      return Future.value(
        const Error(ValidationFailure('An allowance cannot be negative.')),
      );
    }
    return _repository.saveCompensation(compensation);
  }
}

class SaveContributionSchemeUseCase {
  final PayrollRepository _repository;
  const SaveContributionSchemeUseCase(this._repository);

  /// Refuses a table whose brackets overlap or run backwards.
  ///
  /// Overlapping brackets are the quiet failure: the first match wins,
  /// so the deduction depends on the order somebody happened to type the
  /// rows in, and two employees on the same salary can come out
  /// different. A gap is fine and deliberate -- a salary below the
  /// lowest bracket owes nothing.
  Future<Result<void>> call(ContributionScheme scheme) {
    for (final table in scheme.tables) {
      final sorted = [...table.brackets]..sort((a, b) => a.from.compareTo(b.from));
      for (var i = 0; i < sorted.length; i++) {
        final bracket = sorted[i];
        if (bracket.to != null && bracket.to! < bracket.from) {
          return Future.value(Error(ValidationFailure(
            'A ${table.kind.displayLabel} bracket ends before it starts.',
          )));
        }
        if (i + 1 < sorted.length) {
          final next = sorted[i + 1];
          if (bracket.to == null) {
            return Future.value(Error(ValidationFailure(
              'A ${table.kind.displayLabel} bracket with no ceiling has to be '
              'the last one, or it swallows everything above it.',
            )));
          }
          if (next.from <= bracket.to!) {
            return Future.value(Error(ValidationFailure(
              '${table.kind.displayLabel} brackets overlap around '
              '${next.from.toStringAsFixed(2)}. Which one applies would then '
              'depend on the order they were typed in.',
            )));
          }
        }
      }
    }
    return _repository.saveContributionScheme(scheme);
  }
}

class ConfirmContributionSchemeUseCase {
  final PayrollRepository _repository;
  const ConfirmContributionSchemeUseCase(this._repository);

  Future<Result<void>> call(ContributionScheme scheme) {
    if (!scheme.isComplete) {
      final missing =
          scheme.unconfiguredKinds.map((k) => k.displayLabel).join(', ');
      return Future.value(Error(ValidationFailure(
        'These have no table yet: $missing. A payslip that silently deducts '
        'nothing for an agency is one the school under-remits on all year.',
      )));
    }
    return _repository.confirmContributionScheme();
  }
}

class IssuePayslipsUseCase {
  final PayrollRepository _repository;
  const IssuePayslipsUseCase(this._repository);

  Future<Result<int>> call({
    required List<Payslip> payslips,
    required ContributionScheme scheme,
  }) {
    if (payslips.isEmpty) {
      return Future.value(const Error(ValidationFailure('Nobody to pay.')));
    }
    if (!scheme.canIssuePayslips) {
      // The refusal that makes the confirmation mean something. These
      // are somebody's deductions, and this software asserts nothing
      // about what they should be until the school has said.
      return Future.value(const Error(ValidationFailure(
        'The contribution tables have not been confirmed. Somebody has to '
        'check them against the current circulars on the Payroll Setup '
        'screen before payslips can be issued.',
      )));
    }
    return _repository.issuePayslips(payslips);
  }
}
