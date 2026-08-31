import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/contribution_scheme.dart';
import '../../domain/entities/payslip.dart';

class CompensationModel extends Compensation {
  const CompensationModel({
    required super.employeeUid,
    required super.employeeName,
    required super.basis,
    required super.rate,
    super.allowance,
    super.deductAbsences,
  });

  factory CompensationModel.fromFirestore(String id, Map<String, dynamic> data) =>
      CompensationModel(
        employeeUid: id,
        employeeName: data['employeeName'] as String? ?? '',
        basis: PayBasis.fromString(data['basis'] as String? ?? ''),
        rate: (data['rate'] as num?)?.toDouble() ?? 0,
        allowance: (data['allowance'] as num?)?.toDouble() ?? 0,
        // Defaults true, matching the entity: a school that has not said
        // otherwise deducts, which is the common arrangement.
        deductAbsences: data['deductAbsences'] as bool? ?? true,
      );

  static Map<String, dynamic> toMap(Compensation c) => {
        'employeeUid': c.employeeUid,
        'employeeName': c.employeeName,
        'basis': c.basis.value,
        'rate': c.rate,
        'allowance': c.allowance,
        'deductAbsences': c.deductAbsences,
      };
}

class ContributionSchemeModel extends ContributionScheme {
  const ContributionSchemeModel({
    super.tables,
    super.confirmedBySchool,
    super.confirmedByName,
    super.confirmedAt,
  });

  /// A missing document is a school that has not been to the payroll
  /// settings screen. Empty tables, unconfirmed — which is exactly the
  /// state that refuses to issue a payslip, and deliberately not seeded
  /// with numbers nobody has checked.
  factory ContributionSchemeModel.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return const ContributionSchemeModel();
    return ContributionSchemeModel(
      tables: [
        for (final t in (data['tables'] as List<dynamic>? ?? []))
          if (t is Map<String, dynamic>) ContributionTable.fromMap(t),
      ],
      confirmedBySchool: data['confirmedBySchool'] as bool? ?? false,
      confirmedByName: data['confirmedByName'] as String?,
      confirmedAt: (data['confirmedAt'] as Timestamp?)?.toDate(),
    );
  }

  static Map<String, dynamic> toMap(ContributionScheme scheme) => {
        'tables': [for (final t in scheme.tables) t.toMap()],
      };
}

class PayslipModel extends Payslip {
  const PayslipModel({
    required super.employeeUid,
    required super.employeeName,
    required super.periodFrom,
    required super.periodTo,
    required super.earnings,
    required super.deductions,
    required super.basicPay,
    required super.grossPay,
    required super.totalDeductions,
    required super.netPay,
    required super.employerContributions,
    required super.daysWorked,
    required super.daysAbsent,
    required super.daysLate,
    required super.daysMissingTimeOut,
  });

  factory PayslipModel.fromFirestore(String id, Map<String, dynamic> data) {
    List<PayslipLine> lines(String key) => [
          for (final l in (data[key] as List<dynamic>? ?? []))
            if (l is Map<String, dynamic>)
              PayslipLine(
                label: l['label'] as String? ?? '',
                amount: (l['amount'] as num?)?.toDouble() ?? 0,
                basis: l['basis'] as String?,
              ),
        ];

    return PayslipModel(
      employeeUid: data['employeeUid'] as String? ?? '',
      employeeName: data['employeeName'] as String? ?? '',
      periodFrom: data['periodFrom'] as String? ?? '',
      periodTo: data['periodTo'] as String? ?? '',
      earnings: lines('earnings'),
      deductions: lines('deductions'),
      basicPay: (data['basicPay'] as num?)?.toDouble() ?? 0,
      grossPay: (data['grossPay'] as num?)?.toDouble() ?? 0,
      totalDeductions: (data['totalDeductions'] as num?)?.toDouble() ?? 0,
      netPay: (data['netPay'] as num?)?.toDouble() ?? 0,
      employerContributions: (data['employerContributions'] as num?)?.toDouble() ?? 0,
      daysWorked: (data['daysWorked'] as num?)?.toInt() ?? 0,
      daysAbsent: (data['daysAbsent'] as num?)?.toInt() ?? 0,
      daysLate: (data['daysLate'] as num?)?.toInt() ?? 0,
      daysMissingTimeOut: (data['daysMissingTimeOut'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, dynamic> toMap(Payslip p) => {
        'employeeUid': p.employeeUid,
        'employeeName': p.employeeName,
        'periodFrom': p.periodFrom,
        'periodTo': p.periodTo,
        'earnings': [
          for (final l in p.earnings)
            {'label': l.label, 'amount': l.amount, 'basis': l.basis},
        ],
        'deductions': [
          for (final l in p.deductions)
            {'label': l.label, 'amount': l.amount, 'basis': l.basis},
        ],
        'basicPay': p.basicPay,
        'grossPay': p.grossPay,
        'totalDeductions': p.totalDeductions,
        'netPay': p.netPay,
        'employerContributions': p.employerContributions,
        'daysWorked': p.daysWorked,
        'daysAbsent': p.daysAbsent,
        'daysLate': p.daysLate,
        'daysMissingTimeOut': p.daysMissingTimeOut,
      };
}
