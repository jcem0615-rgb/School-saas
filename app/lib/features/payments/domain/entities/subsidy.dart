/// Which government programme is paying part of this student's fees.
///
/// Private-school-only, and the reason this is not simply another
/// [DiscountKind]: a discount is money the school gave away, a subsidy is
/// money the school is owed by somebody else. Folding them together
/// would make the discounts report -- the one a board reads to decide
/// whether the sibling policy is affordable -- overstate what the school
/// absorbed by the whole of its ESC intake.
enum SubsidyProgramme {
  /// Education Service Contracting: DepEd, through PEAC, pays part of a
  /// junior high school student's tuition at a private school.
  esc('esc', 'ESC grant', 'ESC certificate no.'),

  /// The Senior High School Voucher Program. A qualified recipient's
  /// voucher is claimed by the school they enrol in.
  shsVoucher('shs_voucher', 'SHS voucher', 'QVR / voucher no.'),

  /// A local government or foundation grant billed to the grantor the
  /// same way. Rarer, and the long tail is real: city scholarships are
  /// common and behave identically.
  other('other', 'Other subsidy', 'Reference no.');

  final String value;
  final String displayLabel;

  /// What the school calls the number it will bill against. ESC and the
  /// voucher programme use different words for it and a bursar looking
  /// for the field expects their own.
  final String referenceLabel;

  const SubsidyProgramme(this.value, this.displayLabel, this.referenceLabel);

  static SubsidyProgramme fromString(String value) => SubsidyProgramme.values
      .firstWhere((p) => p.value == value, orElse: () => SubsidyProgramme.other);
}

/// A third party paying part of what a student was assessed.
///
/// Reduces what the family owes exactly as a discount does, and is
/// counted entirely differently: it is a receivable, and the school has
/// to be able to produce the list it bills against.
///
/// The reference number is required and it is the point. A subsidy the
/// school cannot cite a certificate for is a subsidy it cannot claim,
/// and a family charged less on the strength of one is a family the
/// school has quietly given money to.
class Subsidy {
  final SubsidyProgramme programme;

  /// The ESC certificate number, the QVR number, or whatever the grantor
  /// issues. Stored as typed, because it is transcribed onto a billing
  /// form and a normalised version would not match.
  final String referenceNumber;

  final double amount;

  /// Free text, for the school year the grant belongs to when it is not
  /// the assessment's own -- a late ESC certificate covering the year
  /// just finished is a real case.
  final String? remarks;

  final String recordedByName;

  const Subsidy({
    required this.programme,
    required this.referenceNumber,
    required this.amount,
    required this.recordedByName,
    this.remarks,
  });

  /// "ESC grant · ESC certificate no. 2026-JHS-01184"
  String get displayLine =>
      '${programme.displayLabel} · ${programme.referenceLabel} $referenceNumber';

  Map<String, dynamic> toMap() => {
        'programme': programme.value,
        'referenceNumber': referenceNumber,
        'amount': amount,
        'remarks': remarks,
        'recordedByName': recordedByName,
      };

  factory Subsidy.fromMap(Map<String, dynamic> map) => Subsidy(
        programme: SubsidyProgramme.fromString(map['programme'] as String? ?? ''),
        referenceNumber: map['referenceNumber'] as String? ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        remarks: map['remarks'] as String?,
        recordedByName: map['recordedByName'] as String? ?? 'Unknown',
      );
}

/// Everything a third party is paying, as one figure.
double totalSubsidy(Iterable<Subsidy> subsidies) {
  final sum = subsidies.fold<double>(0, (running, s) => running + s.amount);
  return (sum * 100).roundToDouble() / 100;
}
