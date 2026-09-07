import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/expense.dart';
import '../repositories/director_repository.dart';

class WatchExpensesUseCase {
  final DirectorRepository _repository;
  const WatchExpensesUseCase(this._repository);

  Stream<List<Expense>> call() => _repository.watchExpenses();
}

class CreateExpenseUseCase {
  final DirectorRepository _repository;
  const CreateExpenseUseCase(this._repository);

  Future<Result<void>> call({
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
    String? receiptFileName,
  }) {
    final categoryError = Validators.required(category, fieldName: 'Category');
    if (categoryError != null) return Future.value(Error(ValidationFailure(categoryError)));

    // Checked before the comparison, because the comparison is what lets
    // it through: `NaN <= 0` is false, and `double.tryParse('NaN')`
    // returns NaN for one word typed into the amount box. `1e400` parses
    // to Infinity and is no better. Either one reaches the ledger and
    // every total that includes the row reads NaN from then on.
    if (!amount.isFinite) {
      return Future.value(const Error(ValidationFailure(
        'An amount has to be a number.',
      )));
    }
    if (amount <= 0) {
      return Future.value(const Error(ValidationFailure('Amount must be greater than zero.')));
    }

    return _repository.createExpense(
      category: category.trim(),
      description: description.trim(),
      amount: amount,
      date: date,
      receiptUrl: receiptUrl,
      receiptFileName: receiptFileName,
    );
  }
}

class UpdateExpenseUseCase {
  final DirectorRepository _repository;
  const UpdateExpenseUseCase(this._repository);

  Future<Result<void>> call({
    required String expenseId,
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
    String? receiptFileName,
  }) {
    if (expenseId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing expense.')));
    }

    final categoryError = Validators.required(category, fieldName: 'Category');
    if (categoryError != null) return Future.value(Error(ValidationFailure(categoryError)));

    // Checked before the comparison, because the comparison is what lets
    // it through: `NaN <= 0` is false, and `double.tryParse('NaN')`
    // returns NaN for one word typed into the amount box. `1e400` parses
    // to Infinity and is no better. Either one reaches the ledger and
    // every total that includes the row reads NaN from then on.
    if (!amount.isFinite) {
      return Future.value(const Error(ValidationFailure(
        'An amount has to be a number.',
      )));
    }
    if (amount <= 0) {
      return Future.value(const Error(ValidationFailure('Amount must be greater than zero.')));
    }

    return _repository.updateExpense(
      expenseId: expenseId,
      category: category.trim(),
      description: description.trim(),
      amount: amount,
      date: date,
      receiptUrl: receiptUrl,
      receiptFileName: receiptFileName,
    );
  }
}

class DeleteExpenseUseCase {
  final DirectorRepository _repository;
  const DeleteExpenseUseCase(this._repository);

  Future<Result<void>> call(String expenseId) {
    if (expenseId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing expense.')));
    }
    return _repository.deleteExpense(expenseId);
  }
}
