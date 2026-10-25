/// A cashier's drawer, from the moment it is opened to the moment it is
/// counted.
///
/// The school already knew what it had collected. What it could not say
/// was whether the money in the drawer matched -- and "the cashier is
/// trustworthy" is not a control, it is a hope. A shift turns the end of
/// the day into one number somebody signs: counted, against expected,
/// and the difference recorded whichever way it falls.
///
/// A shift is a **window of time over one cashier's own collections**,
/// not a label stuck on each payment. Nothing has to remember to tag a
/// receipt, which means nothing can forget to -- every peso that cashier
/// took in cash between opening and closing is in the reckoning by
/// construction.
library;

import '../../../ledger/domain/entities/journal_entry.dart' show centavo, sameMoney;

enum ShiftStatus {
  open('open', 'Open'),
  closed('closed', 'Closed');

  final String value;
  final String displayLabel;
  const ShiftStatus(this.value, this.displayLabel);

  static ShiftStatus fromString(String value) => ShiftStatus.values
      .firstWhere((s) => s.value == value, orElse: () => ShiftStatus.open);
}

class CashierShift {
  final String id;
  final String cashierUid;
  final String cashierName;

  final DateTime openedAt;

  /// The change the drawer started with. Counted by the person opening
  /// it, because a float taken on trust is a discrepancy that was always
  /// there and nobody can date.
  final double openingFloat;

  final DateTime? closedAt;

  /// What was actually in the drawer when it was counted.
  final double? countedAmount;

  /// What should have been: the float plus the cash this cashier took
  /// while the shift was open. Worked out by the server at close, and
  /// stored, so the figure the variance was struck against cannot move
  /// afterwards.
  final double? expectedAmount;

  final String? varianceNote;
  final String? closedByName;
  final String? journalEntryId;
  final String? notes;

  const CashierShift({
    required this.id,
    required this.cashierUid,
    required this.cashierName,
    required this.openedAt,
    required this.openingFloat,
    this.closedAt,
    this.countedAmount,
    this.expectedAmount,
    this.varianceNote,
    this.closedByName,
    this.journalEntryId,
    this.notes,
  });

  ShiftStatus get status =>
      closedAt == null ? ShiftStatus.open : ShiftStatus.closed;

  bool get isOpen => closedAt == null;

  /// Counted less expected. Positive is over, negative is short.
  ///
  /// Null while the shift is open: a drawer nobody has counted has no
  /// variance, and showing zero would say it had been checked.
  double? get variance {
    if (countedAmount == null || expectedAmount == null) return null;
    return countedAmount! - expectedAmount!;
  }

  bool get isBalanced {
    final v = variance;
    return v != null && sameMoney(v, 0);
  }

  bool get isShort => (variance ?? 0) < -centavo;
  bool get isOver => (variance ?? 0) > centavo;

  /// "Short 120.00", "Over 5.00", "Balanced".
  String varianceLabel() {
    final v = variance;
    if (v == null) return 'Not counted';
    if (sameMoney(v, 0)) return 'Balanced';
    return '${v < 0 ? 'Short' : 'Over'} ${v.abs().toStringAsFixed(2)}';
  }

  /// Whether [when] falls inside this shift.
  ///
  /// Inclusive of the opening instant and of the close, because a
  /// receipt written in the same second as the drawer opened belongs to
  /// that drawer. An open shift runs to now.
  bool holds(DateTime when) {
    if (when.isBefore(openedAt)) return false;
    final end = closedAt;
    return end == null || !when.isAfter(end);
  }
}

/// What a shift should have in it, worked out from what it took.
///
/// Kept apart from [CashierShift] because it is a calculation over other
/// records, not a thing stored anywhere -- the same reason the trial
/// balance is derived rather than kept.
class ShiftReckoning {
  final double openingFloat;

  /// Cash this cashier collected during the shift.
  final double cashCollected;

  /// Cash refunded out of the drawer during the shift. Refunds come back
  /// out of the same money, so a shift that ignored them would read
  /// short by exactly the refunds.
  final double cashRefunded;

  /// How many receipts the figure is made of, for the line that says so.
  final int receiptCount;

  const ShiftReckoning({
    required this.openingFloat,
    required this.cashCollected,
    required this.cashRefunded,
    required this.receiptCount,
  });

  /// What should be in the drawer.
  double get expected => openingFloat + cashCollected - cashRefunded;

  /// What to bank: everything but the float, which stays for tomorrow.
  double get toDeposit => cashCollected - cashRefunded;

  double varianceAgainst(double counted) => counted - expected;
}

/// Why a shift cannot be opened, or null.
String? reasonShiftCannotOpen({
  required CashierShift? openShift,
  required double openingFloat,
}) {
  // Two drawers open for one person means every receipt belongs to both
  // and the reckoning is meaningless.
  if (openShift != null) {
    return 'There is already a drawer open, started '
        '${openShift.openedAt.hour.toString().padLeft(2, '0')}:'
        '${openShift.openedAt.minute.toString().padLeft(2, '0')}. '
        'Close it before opening another.';
  }
  if (openingFloat < 0) return 'A float cannot be a negative amount.';
  if (!openingFloat.isFinite) return 'That is not an amount.';
  return null;
}

/// Why a shift cannot be closed, or null.
String? reasonShiftCannotClose({
  required CashierShift shift,
  required double countedAmount,
  required double expectedAmount,
  required String varianceNote,
}) {
  if (!shift.isOpen) return 'That drawer is already closed.';
  if (countedAmount < 0) return 'A count cannot be a negative amount.';
  if (!countedAmount.isFinite) return 'That is not an amount.';

  // A difference with no explanation is the one thing an auditor will
  // ask about and the one thing nobody will remember. It does not have
  // to be a good reason -- "two hundred short, no idea" is a far better
  // record than silence -- but it has to be a reason.
  final variance = countedAmount - expectedAmount;
  if (!sameMoney(variance, 0) && varianceNote.trim().length < 4) {
    return 'The drawer is ${variance < 0 ? 'short' : 'over'} by '
        '${variance.abs().toStringAsFixed(2)}. Say what happened.';
  }
  return null;
}
