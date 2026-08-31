import 'payment.dart';
import 'receipt_booklet.dart';

/// A booklet reconciled: every number in its range, and what became of it.
///
/// The whole value of this feature is in one column. A school can already
/// list the receipts it issued; what it cannot do, and what an examiner
/// asks for, is account for the ones it *did not*. A booklet of five
/// hundred with four hundred and ninety issued and nine cancelled has one
/// number nobody can explain, and finding that in December rather than in
/// the following October is the difference between a correction and a
/// finding.
class ReceiptSeries {
  final ReceiptBooklet booklet;
  final List<ReceiptSeriesEntry> entries;

  const ReceiptSeries({required this.booklet, required this.entries});

  Iterable<ReceiptSeriesEntry> get issued =>
      entries.where((e) => e.status == ReceiptStatus.issued);

  Iterable<ReceiptSeriesEntry> get cancelled =>
      entries.where((e) => e.status == ReceiptStatus.cancelled);

  Iterable<ReceiptSeriesEntry> get unaccounted =>
      entries.where((e) => e.status == ReceiptStatus.unaccounted);

  double get collected =>
      issued.fold<double>(0, (sum, e) => sum + (e.amount ?? 0));

  /// The highest number actually used, or null if none has been. What the
  /// cashier's next receipt should follow.
  int? get highestUsed {
    int? highest;
    for (final entry in entries) {
      if (entry.status == ReceiptStatus.unaccounted) continue;
      if (highest == null || entry.number > highest) highest = entry.number;
    }
    return highest;
  }

  /// The number the next receipt is expected to carry, or null when the
  /// booklet is exhausted.
  int? get nextExpected {
    final used = highestUsed;
    final next = used == null ? booklet.firstNumber : used + 1;
    return booklet.covers(next) ? next : null;
  }

  /// Gaps *inside* what has been used, as human-readable ranges.
  ///
  /// Deliberately not every unused number: a booklet in progress has
  /// hundreds of unused numbers at the end and none of them is a
  /// question. A hole in the middle is.
  List<String> get gapLabels {
    final used = highestUsed;
    if (used == null) return const [];

    final labels = <String>[];
    int? runStart;
    for (var n = booklet.firstNumber; n <= used; n++) {
      final entry = entries[n - booklet.firstNumber];
      if (entry.status == ReceiptStatus.unaccounted) {
        runStart ??= n;
        continue;
      }
      if (runStart != null) {
        labels.add(_range(runStart, n - 1));
        runStart = null;
      }
    }
    if (runStart != null) labels.add(_range(runStart, used));
    return labels;
  }

  String _range(int from, int to) => from == to
      ? booklet.format(from)
      : '${booklet.format(from)}-${booklet.format(to)}';
}

/// Builds the reconciliation.
///
/// Pure, and takes lists rather than reading anything, so the awkward
/// cases -- a receipt number outside the booklet, two payments citing the
/// same number, a cancellation for a number nobody issued -- can each be
/// written down as a test rather than discovered on an audit.
///
/// [payments] may contain refunds and payments from other booklets; both
/// are filtered here. A refund does not consume an OR number in this
/// model: the school issues a separate document for it, and counting the
/// refund against the original's number would make the series say a
/// receipt was used twice.
ReceiptSeries reconcileSeries({
  required ReceiptBooklet booklet,
  required Iterable<Payment> payments,
  Iterable<CancelledReceipt> cancellations = const [],
}) {
  final issuedByNumber = <int, Payment>{};
  for (final payment in payments) {
    if (payment.isRefund) continue;
    final number = payment.officialReceiptNo;
    if (number == null) continue;
    if (!booklet.covers(number)) continue;
    // First write wins. Two payments citing one number is a data fault,
    // not a thing to average -- and the series has to show the number as
    // used exactly once, which is what the duplicate guard on the write
    // side is for.
    issuedByNumber.putIfAbsent(number, () => payment);
  }

  final cancelledByNumber = <int, CancelledReceipt>{};
  for (final cancellation in cancellations) {
    if (!booklet.covers(cancellation.number)) continue;
    cancelledByNumber.putIfAbsent(cancellation.number, () => cancellation);
  }

  final entries = <ReceiptSeriesEntry>[];
  for (var n = booklet.firstNumber; n <= booklet.lastNumber; n++) {
    final payment = issuedByNumber[n];
    if (payment != null) {
      entries.add(ReceiptSeriesEntry(
        number: n,
        formatted: booklet.format(n),
        status: ReceiptStatus.issued,
        amount: payment.amount,
        studentId: payment.studentId,
        issuedAt: payment.createdAt,
        collectedByName: payment.collectedByName,
      ));
      continue;
    }
    final cancellation = cancelledByNumber[n];
    if (cancellation != null) {
      entries.add(ReceiptSeriesEntry(
        number: n,
        formatted: booklet.format(n),
        status: ReceiptStatus.cancelled,
        cancelReason: cancellation.reason,
        issuedAt: cancellation.cancelledAt,
        collectedByName: cancellation.cancelledByName,
      ));
      continue;
    }
    entries.add(ReceiptSeriesEntry(
      number: n,
      formatted: booklet.format(n),
      status: ReceiptStatus.unaccounted,
    ));
  }

  return ReceiptSeries(booklet: booklet, entries: entries);
}
