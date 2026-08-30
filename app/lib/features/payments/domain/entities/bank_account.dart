/// One account a family can transfer to.
///
/// A school takes bank transfers into named accounts -- BPI, BDO,
/// LandBank -- and which one the money went into is what a cashier needs
/// to know before they can find it. The settings screen used to hold a
/// single unlabelled account number beside the e-wallet QR, which was
/// enough for a school with one account and useless for one with three:
/// a family typed a reference number and the cashier had no idea which
/// statement to look in.
class BankAccount {
  /// Stable across edits, so a submission that recorded where it was
  /// sent still points at the same account after the number is
  /// corrected for a typo.
  final String id;

  final String bankName;
  final String accountName;
  final String accountNumber;

  /// Optional. Plenty of schools bank at one branch and never say which.
  final String? branch;

  /// A closed account stays on file rather than being deleted: old
  /// submissions point at it, and a row that vanishes takes the meaning
  /// of those submissions with it. Inactive accounts are simply not
  /// offered to families.
  final bool isActive;

  const BankAccount({
    required this.id,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
    this.branch,
    this.isActive = true,
  });

  /// What a family sees in a list: enough to pick the right one.
  String get label => branch == null || branch!.trim().isEmpty
      ? bankName
      : '$bankName - ${branch!.trim()}';

  /// What is recorded on a submission, so a cashier reading it months
  /// later knows which account was meant even if it has since been
  /// closed and removed from the list.
  String get reconciliationLabel => '$label · $accountNumber';

  Map<String, dynamic> toMap() => {
        'id': id,
        'bankName': bankName,
        'accountName': accountName,
        'accountNumber': accountNumber,
        'branch': branch,
        'isActive': isActive,
      };

  static BankAccount? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final bankName = (raw['bankName'] as String?)?.trim();
    final accountNumber = (raw['accountNumber'] as String?)?.trim();
    // An account without a bank or a number cannot be paid into, and
    // offering it to a family would send money nowhere.
    if (id == null || bankName == null || bankName.isEmpty) return null;
    if (accountNumber == null || accountNumber.isEmpty) return null;
    return BankAccount(
      id: id,
      bankName: bankName,
      accountName: (raw['accountName'] as String?)?.trim() ?? '',
      accountNumber: accountNumber,
      branch: (raw['branch'] as String?)?.trim(),
      isActive: (raw['isActive'] as bool?) ?? true,
    );
  }

  BankAccount copyWith({
    String? bankName,
    String? accountName,
    String? accountNumber,
    String? branch,
    bool? isActive,
  }) =>
      BankAccount(
        id: id,
        bankName: bankName ?? this.bankName,
        accountName: accountName ?? this.accountName,
        accountNumber: accountNumber ?? this.accountNumber,
        branch: branch ?? this.branch,
        isActive: isActive ?? this.isActive,
      );
}
