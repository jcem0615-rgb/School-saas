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

  final DateTime? updatedAt;
  final String? updatedByName;

  const PaymentSettings({
    this.qrCodeUrl,
    this.qrCodeFileName,
    this.accountName,
    this.accountNumber,
    this.instructions,
    this.updatedAt,
    this.updatedByName,
  });

  static const empty = PaymentSettings();

  /// Whether a family has enough information to actually pay.
  bool get isConfigured => qrCodeUrl != null || (accountNumber?.trim().isNotEmpty ?? false);
}
