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
  }) {
    final categoryError = Validators.required(category, fieldName: 'Category');
    if (categoryError != null) return Future.value(Error(ValidationFailure(categoryError)));

    if (amount <= 0) {
      return Future.value(const Error(ValidationFailure('Amount must be greater than zero.')));
    }

    return _repository.createExpense(
      category: category.trim(),
      description: description.trim(),
      amount: amount,
      date: date,
      receiptUrl: receiptUrl,
    );
  }
}
