import '../entities/payment.dart';
import '../repositories/payment_repository.dart';

class WatchPaymentsForStudentUseCase {
  final PaymentRepository _repository;
  const WatchPaymentsForStudentUseCase(this._repository);

  Stream<List<Payment>> call(String studentId) => _repository.watchPaymentsForStudent(studentId);
}

class WatchStudentBalanceUseCase {
  final PaymentRepository _repository;
  const WatchStudentBalanceUseCase(this._repository);

  Stream<double> call(String studentId) => _repository.watchStudentBalance(studentId);
}
