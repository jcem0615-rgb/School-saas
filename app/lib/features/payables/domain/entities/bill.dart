/// What the school owes, and what it has paid against it.
///
/// The difference between this and the `expenses` collection is the word
/// "yet". An expense is money gone. A bill is money owed, which is a
/// liability the school is carrying and the single thing a bursar's
/// system could not tell anybody: how much is outstanding, to whom, and
/// how late.
library;

import '../../../ledger/domain/entities/journal_entry.dart' show centavo, sameMoney;

enum BillStatus {
  open('open', 'Open'),
  partiallyPaid('partially_paid', 'Part paid'),
  paid('paid', 'Paid'),
  void_('void', 'Void');

  final String value;
  final String displayLabel;
  const BillStatus(this.value, this.displayLabel);

  static BillStatus fromString(String value) => BillStatus.values
      .firstWhere((s) => s.value == value, orElse: () => BillStatus.open);

  bool get isSettled => this == BillStatus.paid || this == BillStatus.void_;
}

/// One line of a bill: what was bought, and which account it belongs to.
class BillLine {
  final String accountCode;

  /// The account name as it stood when the bill was entered, for the
  /// same reason a journal line carries one.
  final String accountName;
  final String description;
  final double amount;

  const BillLine({
    required this.accountCode,
    required this.accountName,
    required this.description,
    required this.amount,
  });

  bool get isWellFormed =>
      accountCode.trim().isNotEmpty &&
      description.trim().isNotEmpty &&
      amount > 0;
}

/// One payment made against one bill.
class BillPayment {
  final String id;
  final DateTime date;
  final double amount;

  /// Which cash account it came out of -- 1000, 1010, 1020.
  final String paidFromAccountCode;

  /// Cheque number, transfer reference. What the bank statement will say.
  final String? reference;
  final String paidByName;
  final String? journalEntryId;

  const BillPayment({
    required this.id,
    required this.date,
    required this.amount,
    required this.paidFromAccountCode,
    required this.paidByName,
    this.reference,
    this.journalEntryId,
  });
}

class Bill {
  final String id;
  final String vendorId;

  /// Denormalised at the moment the bill was entered, like every other
  /// name in this system: a vendor renamed next year must not rewrite
  /// what last year's voucher said.
  final String vendorName;

  /// The number printed on the supplier's invoice, not one we generate.
  /// It is what the supplier will quote back on the phone.
  final String billNumber;

  final DateTime billDate;
  final DateTime dueDate;
  final List<BillLine> lines;
  final double total;
  final double amountPaid;
  final BillStatus status;
  final String? notes;

  final String recordedByName;
  final DateTime recordedAt;

  /// The entry that raised the liability. One bill, one entry.
  final String? journalEntryId;

  final List<BillPayment> payments;

  final DateTime? voidedAt;
  final String? voidedByName;
  final String? voidReason;

  const Bill({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.billNumber,
    required this.billDate,
    required this.dueDate,
    required this.lines,
    required this.total,
    required this.recordedByName,
    required this.recordedAt,
    this.amountPaid = 0,
    this.status = BillStatus.open,
    this.notes,
    this.journalEntryId,
    this.payments = const [],
    this.voidedAt,
    this.voidedByName,
    this.voidReason,
  });

  /// What is still owed on it.
  double get outstanding {
    final left = total - amountPaid;
    // Never negative, and never a stray fraction of a centavo: an
    // overpayment is a data problem to see, not a negative to propagate
    // into an ageing total.
    return left < centavo ? 0 : left;
  }

  bool get isVoid => voidedAt != null;
  bool get isPaid => !isVoid && sameMoney(outstanding, 0);

  /// Worked out rather than trusted.
  ///
  /// The stored `status` is what the server wrote; this is what the
  /// numbers say. They agree, and when they do not it is the numbers
  /// that are right -- a status field that drifted is how a paid bill
  /// stays on an ageing report for a year.
  BillStatus get effectiveStatus {
    if (isVoid) return BillStatus.void_;
    if (isPaid) return BillStatus.paid;
    if (amountPaid > 0) return BillStatus.partiallyPaid;
    return BillStatus.open;
  }

  /// Still owed, and therefore still on the ageing report.
  bool get isOutstanding => !isVoid && !isPaid;

  /// How many days past due on [asOf]. Negative means not due yet.
  int daysOverdueOn(DateTime asOf) {
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final day = DateTime(asOf.year, asOf.month, asOf.day);
    return day.difference(due).inDays;
  }

  bool isOverdueOn(DateTime asOf) => isOutstanding && daysOverdueOn(asOf) > 0;
}

/// How late a debt is, in the buckets every ageing report in the world
/// uses. A school's own report will be compared against one of those.
enum AgeingBucket {
  current('Not yet due'),
  upTo30('1-30 days'),
  upTo60('31-60 days'),
  upTo90('61-90 days'),
  over90('Over 90 days');

  final String displayLabel;
  const AgeingBucket(this.displayLabel);

  static AgeingBucket forDaysOverdue(int days) {
    if (days <= 0) return AgeingBucket.current;
    if (days <= 30) return AgeingBucket.upTo30;
    if (days <= 60) return AgeingBucket.upTo60;
    if (days <= 90) return AgeingBucket.upTo90;
    return AgeingBucket.over90;
  }
}

/// What the school owes, by how late it is.
class PayablesAgeing {
  final DateTime asOf;
  final Map<AgeingBucket, double> totals;

  /// Per vendor, so the report answers "who are we behind with" as well
  /// as "how far behind are we".
  final Map<String, Map<AgeingBucket, double>> byVendor;

  const PayablesAgeing({
    required this.asOf,
    required this.totals,
    required this.byVendor,
  });

  factory PayablesAgeing.from(Iterable<Bill> bills, {DateTime? asOf}) {
    final on = asOf ?? DateTime.now();
    final totals = {for (final b in AgeingBucket.values) b: 0.0};
    final byVendor = <String, Map<AgeingBucket, double>>{};

    for (final bill in bills) {
      // A void bill is not a debt and a paid one is not either. Both
      // staying on an ageing report is the classic way a school thinks
      // it owes more than it does.
      if (!bill.isOutstanding) continue;
      final bucket = AgeingBucket.forDaysOverdue(bill.daysOverdueOn(on));
      totals[bucket] = totals[bucket]! + bill.outstanding;
      final vendor = byVendor.putIfAbsent(
        bill.vendorName,
        () => {for (final b in AgeingBucket.values) b: 0.0},
      );
      vendor[bucket] = vendor[bucket]! + bill.outstanding;
    }

    return PayablesAgeing(asOf: on, totals: totals, byVendor: byVendor);
  }

  double get total => totals.values.fold(0, (sum, v) => sum + v);

  /// Everything past its due date, which is the number somebody is
  /// actually worried about.
  double get overdue =>
      total - (totals[AgeingBucket.current] ?? 0);

  bool get isEmpty => sameMoney(total, 0);
}

/// Why a bill cannot be recorded, or null.
///
/// A string rather than a bool: all of these end up in front of whoever
/// typed the bill, and "invalid" tells them nothing about which line.
String? reasonBillCannotBeRecorded({
  required String vendorId,
  required String billNumber,
  required DateTime billDate,
  required DateTime dueDate,
  required List<BillLine> lines,
}) {
  if (vendorId.trim().isEmpty) return 'Choose who the bill is from.';
  if (billNumber.trim().isEmpty) {
    // Without it there is no way to tell the supplier which bill is
    // being queried, and no way to notice the same one entered twice.
    return "Enter the number printed on the supplier's invoice.";
  }
  if (lines.isEmpty) return 'A bill needs at least one line.';
  if (lines.any((l) => !l.isWellFormed)) {
    return 'Every line needs an account, a description and an amount above zero.';
  }
  if (dueDate.isBefore(DateTime(billDate.year, billDate.month, billDate.day))) {
    return 'A bill cannot fall due before it was issued.';
  }
  final total = lines.fold<double>(0, (sum, l) => sum + l.amount);
  if (total <= 0) return 'A bill of nothing is not a bill.';
  return null;
}

/// Why a payment cannot be made against [bill], or null.
String? reasonPaymentCannotBeMade({
  required Bill bill,
  required double amount,
  required String paidFromAccountCode,
}) {
  if (bill.isVoid) return 'That bill was voided.';
  if (bill.isPaid) return 'That bill is already settled.';
  if (amount <= 0) return 'Enter how much is being paid.';
  if (paidFromAccountCode.trim().isEmpty) {
    return 'Choose which account the money came out of.';
  }
  // Overpaying a bill is almost always a typo, and the alternative --
  // letting it through and carrying a negative -- turns one mistake
  // into a wrong total on every report that sums outstanding.
  if (amount - bill.outstanding > centavo) {
    return 'That is more than the ${bill.outstanding.toStringAsFixed(2)} '
        'still owed on this bill.';
  }
  return null;
}
