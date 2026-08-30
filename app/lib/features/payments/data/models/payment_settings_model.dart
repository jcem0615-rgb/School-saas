import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/bank_account.dart';
import '../../domain/entities/payment_settings.dart';

class PaymentSettingsModel extends PaymentSettings {
  const PaymentSettingsModel({
    super.qrCodeUrl,
    super.qrCodeFileName,
    super.accountName,
    super.accountNumber,
    super.instructions,
    super.bankAccounts,
    super.updatedAt,
    super.updatedByName,
  });

  /// [data] is null before a registrar has ever saved settings, which is
  /// the normal state for a new school -- the pay screen has to cope with
  /// an unconfigured school rather than assuming a QR exists.
  factory PaymentSettingsModel.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const PaymentSettingsModel();
    return PaymentSettingsModel(
      qrCodeUrl: data['qrCodeUrl'] as String?,
      qrCodeFileName: data['qrCodeFileName'] as String?,
      accountName: data['accountName'] as String?,
      accountNumber: data['accountNumber'] as String?,
      instructions: data['instructions'] as String?,
      // Anything unreadable is dropped rather than throwing. A malformed
      // row in the list would otherwise take the whole pay screen down,
      // and a family that cannot see the other two accounts because of
      // one bad one is worse off than one that sees two.
      bankAccounts: [
        for (final raw in (data['bankAccounts'] as List<dynamic>? ?? const []))
          if (BankAccount.fromMap(raw) case final account?) account,
      ],
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedByName: data['updatedByName'] as String?,
    );
  }
}
