enum PaymentMethod {
  cash('cash'),
  gcash('gcash'),
  bankTransfer('bank_transfer'),
  online('online');

  final String value;
  const PaymentMethod(this.value);

  static PaymentMethod fromString(String value) =>
      PaymentMethod.values.firstWhere((m) => m.value == value);

  String get displayLabel => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.bankTransfer => 'Bank Transfer',
        PaymentMethod.online => 'Online',
      };
}

enum PaymentPurpose {
  tuition('tuition'),
  miscFee('misc_fee'),
  other('other');

  final String value;
  const PaymentPurpose(this.value);

  static PaymentPurpose fromString(String value) =>
      PaymentPurpose.values.firstWhere((p) => p.value == value);

  String get displayLabel => switch (this) {
        PaymentPurpose.tuition => 'Tuition',
        PaymentPurpose.miscFee => 'Miscellaneous Fee',
        PaymentPurpose.other => 'Other',
      };
}

enum PaymentStatus {
  completed('completed'),
  refunded('refunded');

  final String value;
  const PaymentStatus(this.value);

  static PaymentStatus fromString(String value) =>
      PaymentStatus.values.firstWhere((s) => s.value == value);
}

/// A single payment or refund transaction. Refunds are stored as their own
/// row (negative [amount], [refundOf] pointing at the original payment's
/// id) rather than mutating history -- this is what makes "Payment
/// History" and "Refund History" both derivable from one query: filter
/// this same list by whether [refundOf] is set.
class Payment {
  final String id;
  final String studentId;
  final double amount;
  final PaymentMethod method;
  final String? referenceNumber;
  final String receiptNumber;
  final String collectedByName;
  final PaymentPurpose purpose;
  final PaymentStatus status;
  final String? refundOf;
  final DateTime createdAt;

  const Payment({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.method,
    required this.receiptNumber,
    required this.collectedByName,
    required this.purpose,
    required this.status,
    required this.createdAt,
    this.referenceNumber,
    this.refundOf,
  });

  bool get isRefund => refundOf != null;
}
