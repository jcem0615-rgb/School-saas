enum InvoiceStatus {
  pending('pending'),
  paid('paid'),
  overdue('overdue'),
  void_('void');

  final String value;
  const InvoiceStatus(this.value);

  static InvoiceStatus fromString(String value) =>
      InvoiceStatus.values.firstWhere((s) => s.value == value);
}

enum PaymentMethod {
  cash('cash'),
  gcash('gcash'),
  bankTransfer('bank_transfer'),
  online('online');

  final String value;
  const PaymentMethod(this.value);

  static PaymentMethod fromString(String value) =>
      PaymentMethod.values.firstWhere((m) => m.value == value);
}

class DailyBillingLine {
  final DateTime date;
  final int activeStudents;
  final double charge;
  const DailyBillingLine({
    required this.date,
    required this.activeStudents,
    required this.charge,
  });
}

/// A single monthly invoice for one school. Generated automatically by the
/// billing engine (Cloud Function) -- never created or edited by hand,
/// only its payment status changes, and only through recordManualPayment.
class Invoice {
  final String id;
  final String schoolId;
  final DateTime billingPeriodStart;
  final DateTime billingPeriodEnd;
  final List<DailyBillingLine> dailyBreakdown;
  final double totalAmount;
  final InvoiceStatus status;
  final DateTime dueDate;
  final DateTime? paidAt;
  final double? paidAmount;
  final PaymentMethod? paymentMethod;
  final String? paymentReference;

  const Invoice({
    required this.id,
    required this.schoolId,
    required this.billingPeriodStart,
    required this.billingPeriodEnd,
    required this.dailyBreakdown,
    required this.totalAmount,
    required this.status,
    required this.dueDate,
    this.paidAt,
    this.paidAmount,
    this.paymentMethod,
    this.paymentReference,
  });

  bool get isOverdue => status == InvoiceStatus.overdue;
}
