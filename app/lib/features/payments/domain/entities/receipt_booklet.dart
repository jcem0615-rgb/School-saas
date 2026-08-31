/// A BIR-registered booklet of official receipts.
///
/// ## What this is, and what it deliberately is not
///
/// A private school is a business. It issues Official Receipts from
/// booklets printed under an Authority to Print, each with a serial
/// range, and it must be able to account for every number in that range
/// -- issued, cancelled, or unused. The end of that accounting is not the
/// school's convenience; it is what an examiner asks for.
///
/// This is a **register of the receipts the school issued**, not a
/// BIR-accredited Computerised Accounting System. It does not print an OR
/// and it does not claim the number it holds is machine-generated: the
/// number recorded here is the one pre-printed on the paper the family
/// was handed. Claiming otherwise would put a school in front of an
/// examiner with software that says it is something it has no permit to
/// be.
///
/// What it does do is know which booklet is in use and what the next
/// number should be, so a mis-keyed number is caught at the counter
/// rather than at the end of the year.
class ReceiptBooklet {
  final String id;

  /// The letters before the serial, if the booklet has any. Many do not.
  final String prefix;

  /// The printed range, inclusive at both ends. A booklet of 0001 to 0500
  /// holds five hundred receipts, not four hundred and ninety-nine.
  final int firstNumber;
  final int lastNumber;

  /// How many digits the serial is printed with, so 42 in a booklet
  /// printed 0001-0500 reads back as 0042 rather than 42. Stored rather
  /// than inferred from [lastNumber]: a booklet printed 000001-000500
  /// exists and its numbers are six digits wide.
  final int digits;

  /// The BIR Authority to Print number, as printed on the booklet. Free
  /// text: the format has changed over the years and a school copying it
  /// off the cover should not be told its own permit is invalid.
  final String? atpNumber;

  final DateTime registeredOn;

  /// Only one booklet is in use at a time. Retired rather than deleted:
  /// every payment that cites one of its numbers has to stay explainable.
  final bool isActive;

  final String registeredByName;

  const ReceiptBooklet({
    required this.id,
    required this.prefix,
    required this.firstNumber,
    required this.lastNumber,
    required this.digits,
    required this.registeredOn,
    required this.registeredByName,
    this.atpNumber,
    this.isActive = true,
  });

  int get capacity => lastNumber - firstNumber + 1;

  /// "OR-0042" -- how the number reads on the paper.
  String format(int number) =>
      '$prefix${number.toString().padLeft(digits, '0')}';

  String get rangeLabel => '${format(firstNumber)} to ${format(lastNumber)}';

  bool covers(int number) => number >= firstNumber && number <= lastNumber;

  /// Parses a number back out of what somebody typed.
  ///
  /// Tolerant, because a cashier under a queue types "42", "0042" and
  /// "OR-0042" for the same receipt and all three are the same piece of
  /// paper. Returns null when there are no digits in it at all.
  static int? parseNumber(String typed) {
    final digits = RegExp(r'\d+').allMatches(typed.trim()).map((m) => m.group(0)!).join();
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  Map<String, dynamic> toMap() => {
        'prefix': prefix,
        'firstNumber': firstNumber,
        'lastNumber': lastNumber,
        'digits': digits,
        'atpNumber': atpNumber,
        'isActive': isActive,
      };

  factory ReceiptBooklet.fromMap(String id, Map<String, dynamic> map,
          {required DateTime registeredOn, required String registeredByName}) =>
      ReceiptBooklet(
        id: id,
        prefix: map['prefix'] as String? ?? '',
        firstNumber: (map['firstNumber'] as num?)?.toInt() ?? 0,
        lastNumber: (map['lastNumber'] as num?)?.toInt() ?? 0,
        // Four is the commonest booklet width, and a stored zero would
        // pad nothing and make every number read differently.
        digits: ((map['digits'] as num?)?.toInt() ?? 4).clamp(1, 12),
        atpNumber: map['atpNumber'] as String?,
        isActive: map['isActive'] as bool? ?? true,
        registeredOn: registeredOn,
        registeredByName: registeredByName,
      );
}

/// What became of one number in a booklet's range.
enum ReceiptStatus {
  /// Handed to a family against a payment.
  issued,

  /// Spoiled -- misprinted, torn, written wrong -- and kept. A cancelled
  /// receipt still occupies its number, which is the point: the series
  /// must not have a hole in it.
  cancelled,

  /// Nothing in the system accounts for it. The one an examiner asks
  /// about, and the reason this report exists.
  unaccounted;

  String get displayLabel => switch (this) {
        ReceiptStatus.issued => 'Issued',
        ReceiptStatus.cancelled => 'Cancelled',
        ReceiptStatus.unaccounted => 'Unaccounted',
      };
}

/// One number in the range, and what happened to it.
class ReceiptSeriesEntry {
  final int number;
  final String formatted;
  final ReceiptStatus status;

  /// Set when [status] is issued.
  final double? amount;

  /// Who it was issued to. The id rather than the name: a Payment does
  /// not carry a name, and resolving one here would mean this entity
  /// knowing about students.
  final String? studentId;

  final DateTime? issuedAt;
  final String? collectedByName;

  /// Set when [status] is cancelled.
  final String? cancelReason;

  const ReceiptSeriesEntry({
    required this.number,
    required this.formatted,
    required this.status,
    this.amount,
    this.studentId,
    this.issuedAt,
    this.collectedByName,
    this.cancelReason,
  });
}

/// A number consumed without a payment.
class CancelledReceipt {
  final int number;
  final String reason;
  final DateTime cancelledAt;
  final String cancelledByName;

  const CancelledReceipt({
    required this.number,
    required this.reason,
    required this.cancelledAt,
    required this.cancelledByName,
  });
}
