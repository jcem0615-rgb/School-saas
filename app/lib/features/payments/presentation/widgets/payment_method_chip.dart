import 'package:flutter/material.dart';

import '../../domain/entities/payment.dart';

class PaymentMethodChip extends StatelessWidget {
  final PaymentMethod method;
  const PaymentMethodChip({super.key, required this.method});

  IconData get _icon => switch (method) {
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.gcash => Icons.phone_iphone,
        PaymentMethod.bankTransfer => Icons.account_balance_outlined,
        PaymentMethod.online => Icons.language,
      };

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(_icon, size: 16),
      label: Text(method.displayLabel),
      visualDensity: VisualDensity.compact,
    );
  }
}
