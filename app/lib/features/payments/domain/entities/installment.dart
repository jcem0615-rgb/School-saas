/// One dated instalment on a payment plan: "Second payment, 5 Oct, ₱4,500".
///
/// A record inline on the fee structure and on the assessment, not a
/// document of its own, and that is the whole design of this feature.
///
/// The tempting alternative is a row per instalment with its own `paid`
/// field, and it goes wrong immediately: every payment then has to
/// allocate itself across several documents in one transaction, every
/// refund has to un-allocate, a voided assessment has to unwind the lot,
/// and any of those failing halfway leaves a family's plan disagreeing
/// with their balance. The ledger already exists and is already correct
/// -- assessments add, payments subtract -- so nothing here is allowed to
/// become a second one.
///
/// So a schedule is a *plan*, not a ledger. What is overdue is derived by
/// comparing what the plan says should have arrived by today against what
/// actually did. That derivation is a pure function of two numbers and a
/// date, it cannot drift from the balance because it is computed from it,
/// and it survives refunds, voids and back-dated payments without any
/// code that knows about them.
class Installment {
  /// What the school calls it. "Upon enrolment", "October", "Second
  /// payment" -- whatever appears on the letter sent home, because a
  /// family reading this screen is holding that letter.
  final String label;

  /// The day it falls due. Date-only in meaning: a payment made at any
  /// time on the due date is on time, which is why every comparison here
  /// goes through [_dayOf] rather than comparing timestamps.
  final DateTime dueDate;

  final double amount;

  const Installment({
    required this.label,
    required this.dueDate,
    required this.amount,
  });

  Map<String, dynamic> toMap() => {
        'label': label,
        'dueDate': dueDate.toIso8601String(),
        'amount': amount,
      };

  /// Tolerant of both shapes a due date arrives in: a Firestore
  /// Timestamp converted upstream, or the ISO string this writes.
  factory Installment.fromMap(Map<String, dynamic> map, {DateTime? dueDate}) =>
      Installment(
        label: map['label'] as String? ?? '',
        dueDate: dueDate ??
            DateTime.tryParse(map['dueDate'] as String? ?? '') ??
            DateTime.now(),
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// Where one instalment stands, once what was actually paid is known.
enum InstallmentState {
  /// Settled in full.
  paid,

  /// Some of it has arrived, and its due date has not passed.
  partial,

  /// Nothing or not enough has arrived, and the due date has passed.
  /// This is the only state that means the school should be chasing.
  overdue,

  /// Not due yet, nothing allocated to it.
  upcoming;

  String get displayLabel => switch (this) {
        InstallmentState.paid => 'Paid',
        InstallmentState.partial => 'Partly paid',
        InstallmentState.overdue => 'Overdue',
        InstallmentState.upcoming => 'Not yet due',
      };
}

/// One line of the plan with the money applied to it.
class InstallmentStanding {
  final Installment installment;

  /// How much of this instalment the payments cover, oldest instalment
  /// first. Never more than the instalment's amount.
  final double settled;

  final InstallmentState state;

  /// Days past the due date, or 0 if it is not overdue. Whole days, so a
  /// payment due yesterday is one day late rather than 0.4.
  final int daysLate;

  const InstallmentStanding({
    required this.installment,
    required this.settled,
    required this.state,
    required this.daysLate,
  });

  double get outstanding {
    final left = installment.amount - settled;
    return left < 0.005 ? 0 : left;
  }
}

/// The plan, and where a family stands against it.
///
/// Deliberately holds no student, no assessment id and no repository:
/// it is arithmetic, and everything that uses it -- the family's own
/// screen, the cashier's, the overdue report, the exam permit -- passes
/// in the two numbers and asks the same questions.
class BillingSchedule {
  final List<Installment> installments;

  const BillingSchedule(this.installments);

  static const empty = BillingSchedule(<Installment>[]);

  bool get isEmpty => installments.isEmpty;
  bool get isNotEmpty => installments.isNotEmpty;

  double get total => installments.fold(0, (sum, i) => sum + i.amount);

  /// The plan in the order a family reads it, which is by date. A school
  /// that types the rows out of order should still get a schedule that
  /// makes sense, and oldest-first allocation depends on this ordering
  /// being right rather than being trusted from the document.
  List<Installment> get inDueOrder {
    final sorted = [...installments]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return sorted;
  }

  /// What the plan says should have arrived by [asOf], inclusive of
  /// anything falling due that day.
  double amountDueBy(DateTime asOf) {
    final cutoff = _dayOf(asOf);
    return installments
        .where((i) => !_dayOf(i.dueDate).isAfter(cutoff))
        .fold<double>(0, (sum, i) => sum + i.amount);
  }

  /// How far behind the plan a family is, given what they have paid.
  ///
  /// Not "the sum of unpaid instalments": money is not earmarked, so a
  /// family who paid ₱10,000 against a plan whose first two instalments
  /// total ₱9,000 is ahead, not overdue on the second. Comparing running
  /// totals is what makes an early payment count.
  ///
  /// Never negative. Paying ahead is not a debt owed the other way.
  double overdueAmount({required double paid, required DateTime asOf}) {
    final behind = amountDueBy(asOf) - paid;
    return behind < 0.005 ? 0 : _round(behind);
  }

  /// Every line with its money applied, oldest first.
  List<InstallmentStanding> standing({
    required double paid,
    required DateTime asOf,
  }) {
    final today = _dayOf(asOf);
    var remaining = paid < 0 ? 0.0 : paid;

    return inDueOrder.map((installment) {
      final settled = remaining >= installment.amount ? installment.amount : remaining;
      remaining = _round(remaining - settled);
      if (remaining < 0) remaining = 0;

      final due = _dayOf(installment.dueDate);
      final isPast = due.isBefore(today);
      final fullySettled = installment.amount - settled < 0.005;

      final state = fullySettled
          ? InstallmentState.paid
          : isPast
              ? InstallmentState.overdue
              : settled > 0
                  ? InstallmentState.partial
                  : InstallmentState.upcoming;

      return InstallmentStanding(
        installment: installment,
        settled: _round(settled),
        state: state,
        daysLate: state == InstallmentState.overdue ? today.difference(due).inDays : 0,
      );
    }).toList();
  }

  /// The next thing a family owes, or null when the plan is settled.
  /// What a dashboard shows, and what a reminder is written about.
  InstallmentStanding? nextDue({required double paid, required DateTime asOf}) {
    final lines = standing(paid: paid, asOf: asOf);
    for (final line in lines) {
      if (line.state == InstallmentState.overdue) return line;
    }
    for (final line in lines) {
      if (line.state != InstallmentState.paid) return line;
    }
    return null;
  }

  /// Midnight of the day, so "due today" is not overdue at 00:01 and
  /// "paid on the due date" is on time. Comparing raw DateTimes here
  /// would make a due date typed at 8am overdue for the rest of that day.
  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
