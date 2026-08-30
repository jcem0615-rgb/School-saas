import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/payments/data/models/payment_settings_model.dart';
import 'package:logicclass/features/payments/domain/entities/bank_account.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/domain/entities/payment_settings.dart';

/// What a school has published, and therefore what a family may choose.
///
/// The point of these is the negative case: a method offered on a school
/// that cannot receive it leads a family to a dead end, and a bank
/// account with no number leads their money nowhere.
void main() {
  BankAccount account({
    String id = 'ba_1',
    String bankName = 'BPI',
    String accountName = 'St. Nicholas Academy',
    String accountNumber = '1234-5678-90',
    String? branch,
    bool isActive = true,
  }) =>
      BankAccount(
        id: id,
        bankName: bankName,
        accountName: accountName,
        accountNumber: accountNumber,
        branch: branch,
        isActive: isActive,
      );

  group('what a family may choose', () {
    test('nothing, on a school that has published nothing', () {
      const settings = PaymentSettings();
      expect(settings.isConfigured, isFalse);
      expect(settings.payableMethods, isEmpty);
    });

    test('bank transfer only, when only bank accounts are published', () {
      final settings = PaymentSettings(bankAccounts: [account()]);
      expect(settings.isConfigured, isTrue);
      expect(settings.payableMethods, [PaymentMethod.bankTransfer]);
      // Offering GCash here would send a family to a screen with no QR
      // and no number on it.
      expect(settings.supports(PaymentMethod.gcash), isFalse);
    });

    test('e-wallet only, when only a QR is published', () {
      const settings = PaymentSettings(qrCodeUrl: 'https://example/qr.png');
      expect(settings.payableMethods, [PaymentMethod.gcash, PaymentMethod.online]);
      expect(settings.supports(PaymentMethod.bankTransfer), isFalse);
    });

    test('both, when the school takes both', () {
      final settings = PaymentSettings(
        qrCodeUrl: 'https://example/qr.png',
        bankAccounts: [account()],
      );
      expect(settings.payableMethods, [
        PaymentMethod.gcash,
        PaymentMethod.bankTransfer,
        PaymentMethod.online,
      ]);
    });

    test('cash is never a way to pay online', () {
      final settings = PaymentSettings(
        qrCodeUrl: 'https://example/qr.png',
        bankAccounts: [account()],
      );
      expect(settings.supports(PaymentMethod.cash), isFalse);
      expect(settings.payableMethods, isNot(contains(PaymentMethod.cash)));
    });

    test('a closed account is not offered, but is still on file', () {
      final settings = PaymentSettings(bankAccounts: [account(isActive: false)]);
      // Kept, because old submissions point at it and a row that
      // vanishes takes their meaning with it.
      expect(settings.bankAccounts, hasLength(1));
      expect(settings.activeBankAccounts, isEmpty);
      expect(settings.supports(PaymentMethod.bankTransfer), isFalse);
    });
  });

  group('how an account reads', () {
    test('names the branch when there is one', () {
      expect(account(branch: 'Lipa City').label, 'BPI - Lipa City');
    });

    test('and just the bank when there is not', () {
      expect(account().label, 'BPI');
      expect(account(branch: '   ').label, 'BPI');
    });

    test('carries the number in what a submission records', () {
      // A cashier reading a submission months later has to know which
      // account was meant, even if it has since been closed and removed.
      expect(
        account(branch: 'Lipa City').reconciliationLabel,
        'BPI - Lipa City · 1234-5678-90',
      );
    });
  });

  group('reading what was stored', () {
    PaymentSettings parse(List<Object?> rows) =>
        PaymentSettingsModel.fromFirestore({'bankAccounts': rows});

    test('round-trips an account', () {
      final settings = parse([account(branch: 'Lipa City').toMap()]);
      expect(settings.bankAccounts, hasLength(1));
      expect(settings.bankAccounts.first.bankName, 'BPI');
      expect(settings.bankAccounts.first.branch, 'Lipa City');
      expect(settings.bankAccounts.first.isActive, isTrue);
    });

    test('drops a row with no account number rather than offering it', () {
      // Money sent to an account with no number goes nowhere.
      final settings = parse([
        {'id': 'ba_1', 'bankName': 'BPI', 'accountNumber': '   '},
        account(id: 'ba_2').toMap(),
      ]);
      expect(settings.bankAccounts, hasLength(1));
      expect(settings.bankAccounts.first.id, 'ba_2');
    });

    test('drops a row with no bank name', () {
      final settings = parse([
        {'id': 'ba_1', 'bankName': '', 'accountNumber': '123'},
      ]);
      expect(settings.bankAccounts, isEmpty);
    });

    test('one bad row does not lose the good ones', () {
      // The whole reason parsing is per-row and forgiving: a family that
      // cannot see two accounts because of a third is worse off than one
      // that sees two.
      final settings = parse([
        'not a map',
        null,
        account(id: 'ba_ok').toMap(),
      ]);
      expect(settings.bankAccounts, hasLength(1));
      expect(settings.bankAccounts.first.id, 'ba_ok');
    });

    test('a school that has never saved settings reads as unconfigured', () {
      final settings = PaymentSettingsModel.fromFirestore(null);
      expect(settings.isConfigured, isFalse);
      expect(settings.bankAccounts, isEmpty);
    });
  });
}
