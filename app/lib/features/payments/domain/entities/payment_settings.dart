import 'bank_account.dart';
import 'payment.dart';

/// Where a family should send an online payment.
///
/// School-level rather than per-user: there is one school e-wallet, and
/// every student and parent paying online needs to see the same QR. The
/// registrar owns it; everyone in the tenant can read it.
class PaymentSettings {
  /// The school's e-wallet QR image. Null until a registrar uploads one,
  /// which is why the pay screen has to handle its absence rather than
  /// assuming a QR is always there.
  final String? qrCodeUrl;
  final String? qrCodeFileName;

  /// Account name and number shown alongside the QR, for anyone paying by
  /// transfer instead of by scanning.
  final String? accountName;
  final String? accountNumber;

  /// Free-text instructions from the school, e.g. which reference to put
  /// in the e-wallet message field.
  final String? instructions;

  /// The school's bank accounts, for families paying by transfer rather
  /// than by scanning. Empty for a school that only takes e-wallet.
  final List<BankAccount> bankAccounts;

  final DateTime? updatedAt;
  final String? updatedByName;

  const PaymentSettings({
    this.qrCodeUrl,
    this.qrCodeFileName,
    this.accountName,
    this.accountNumber,
    this.instructions,
    this.bankAccounts = const [],
    this.updatedAt,
    this.updatedByName,
  });

  static const empty = PaymentSettings();

  /// The accounts a family may actually be sent to. A closed account
  /// stays on file for the submissions that point at it, and is not
  /// offered to anybody.
  List<BankAccount> get activeBankAccounts =>
      bankAccounts.where((a) => a.isActive).toList();

  /// Whether a family has enough information to actually pay.
  bool get isConfigured =>
      qrCodeUrl != null ||
      (accountNumber?.trim().isNotEmpty ?? false) ||
      activeBankAccounts.isNotEmpty;

  /// Whether this method can be paid at all, given what the school has
  /// published.
  ///
  /// Checked before a family is offered the method rather than after
  /// they have chosen it: "Bank Transfer" on a school that has published
  /// no bank account is an option that leads to a screen saying it
  /// cannot be done, which is worse than not offering it.
  bool supports(PaymentMethod method) => switch (method) {
        PaymentMethod.bankTransfer => activeBankAccounts.isNotEmpty,
        PaymentMethod.gcash || PaymentMethod.online =>
          qrCodeUrl != null || (accountNumber?.trim().isNotEmpty ?? false),
        // Cash is over the counter. It is never a way to pay online, and
        // this screen never offers it.
        PaymentMethod.cash => false,
      };

  /// The methods a family may choose, in the order they are offered.
  List<PaymentMethod> get payableMethods => [
        for (final method in const [
          PaymentMethod.gcash,
          PaymentMethod.bankTransfer,
          PaymentMethod.online,
        ])
          if (supports(method)) method,
      ];
}
