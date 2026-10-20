import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/vendor.dart';

class ActingBuyer {
  final String uid;
  final String schoolId;
  final String name;
  const ActingBuyer({required this.uid, required this.schoolId, required this.name});
}

class VendorModel extends Vendor {
  const VendorModel({
    required super.id,
    required super.name,
    super.tin,
    super.paymentTermsDays,
    super.contactName,
    super.phone,
    super.email,
    super.address,
    super.notes,
    super.isActive,
  });

  factory VendorModel.fromFirestore(String id, Map<String, dynamic> data) => VendorModel(
        id: id,
        name: data['name'] as String? ?? 'Unnamed supplier',
        tin: data['tin'] as String?,
        paymentTermsDays: (data['paymentTermsDays'] as num?)?.toInt() ?? 0,
        contactName: data['contactName'] as String?,
        phone: data['phone'] as String?,
        email: data['email'] as String?,
        address: data['address'] as String?,
        notes: data['notes'] as String?,
        isActive: data['isActive'] as bool? ?? true,
      );
}

class BillModel extends Bill {
  const BillModel({
    required super.id,
    required super.vendorId,
    required super.vendorName,
    required super.billNumber,
    required super.billDate,
    required super.dueDate,
    required super.lines,
    required super.total,
    required super.recordedByName,
    required super.recordedAt,
    super.amountPaid,
    super.status,
    super.notes,
    super.journalEntryId,
    super.payments,
    super.voidedAt,
    super.voidedByName,
    super.voidReason,
  });

  factory BillModel.fromFirestore(String id, Map<String, dynamic> data) {
    final now = DateTime.now();
    return BillModel(
      id: id,
      vendorId: data['vendorId'] as String? ?? '',
      vendorName: data['vendorName'] as String? ?? 'Unknown supplier',
      billNumber: data['billNumber'] as String? ?? '',
      // Written from the server clock, so null in the local echo of a
      // document that has not round-tripped yet.
      billDate: (data['billDate'] as Timestamp?)?.toDate() ?? now,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate() ?? now,
      lines: [
        for (final raw in (data['lines'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>)
            BillLine(
              accountCode: raw['accountCode'] as String? ?? '',
              accountName: raw['accountName'] as String? ?? 'Unknown account',
              description: raw['description'] as String? ?? '',
              amount: (raw['amount'] as num?)?.toDouble() ?? 0,
            ),
      ],
      total: (data['total'] as num?)?.toDouble() ?? 0,
      amountPaid: (data['amountPaid'] as num?)?.toDouble() ?? 0,
      status: BillStatus.fromString(data['status'] as String? ?? ''),
      notes: data['notes'] as String?,
      journalEntryId: data['journalEntryId'] as String?,
      payments: [
        for (final raw in (data['payments'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>)
            BillPayment(
              id: raw['id'] as String? ?? '',
              date: (raw['date'] as Timestamp?)?.toDate() ?? now,
              amount: (raw['amount'] as num?)?.toDouble() ?? 0,
              paidFromAccountCode: raw['paidFromAccountCode'] as String? ?? '',
              reference: raw['reference'] as String?,
              paidByName: raw['paidByName'] as String? ?? 'Unknown',
              journalEntryId: raw['journalEntryId'] as String?,
            ),
      ],
      recordedByName: data['recordedByName'] as String? ?? 'Unknown',
      recordedAt: (data['recordedAt'] as Timestamp?)?.toDate() ?? now,
      voidedAt: (data['voidedAt'] as Timestamp?)?.toDate(),
      voidedByName: data['voidedByName'] as String?,
      voidReason: data['voidReason'] as String?,
    );
  }
}

/// Reads the payables ledger; never writes a bill.
///
/// Every bill write goes through a callable, because the entry it posts
/// has to balance and has to commit with the bill -- and rules cannot
/// prove either. The supplier list is an ordinary write: it is a list of
/// names.
class PayablesRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingBuyer _actingUser;

  const PayablesRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingBuyer actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  Stream<List<VendorModel>> watchVendors() => _firestore
      .collection(FirestorePaths.vendors(_actingUser.schoolId))
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => VendorModel.fromFirestore(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Stream<List<BillModel>> watchBills() => _firestore
      .collection(FirestorePaths.bills(_actingUser.schoolId))
      .where('isDeleted', isEqualTo: false)
      .orderBy('billDate', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => BillModel.fromFirestore(d.id, d.data())).toList());

  Future<void> saveVendor(Vendor vendor) async {
    final ref = vendor.id.isEmpty
        ? _firestore.collection(FirestorePaths.vendors(_actingUser.schoolId)).doc()
        : _firestore.doc(FirestorePaths.vendorDoc(_actingUser.schoolId, vendor.id));
    await ref.set({
      'id': ref.id,
      'schoolId': _actingUser.schoolId,
      'name': vendor.name,
      'tin': vendor.tin,
      'paymentTermsDays': vendor.paymentTermsDays,
      'contactName': vendor.contactName,
      'phone': vendor.phone,
      'email': vendor.email,
      'address': vendor.address,
      'notes': vendor.notes,
      'isActive': vendor.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
    }, SetOptions(merge: true));
  }

  Future<String> recordBill({
    required String vendorId,
    required String billNumber,
    required DateTime billDate,
    required DateTime dueDate,
    required List<BillLine> lines,
    String? notes,
  }) async {
    final result = await _functions
        .httpsCallable('recordBill')
        .call<Map<String, dynamic>>({
      'schoolId': _actingUser.schoolId,
      'vendorId': vendorId,
      'billNumber': billNumber,
      'billDate': billDate.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'lines': [
        for (final line in lines)
          {
            'accountCode': line.accountCode,
            'description': line.description,
            'amount': line.amount,
          },
      ],
      if (notes != null) 'notes': notes,
    });
    return result.data['billId'] as String? ?? '';
  }

  Future<void> payBill({
    required String billId,
    required double amount,
    required String paidFromAccountCode,
    DateTime? date,
    String? reference,
  }) async {
    await _functions.httpsCallable('payBill').call<Map<String, dynamic>>({
      'schoolId': _actingUser.schoolId,
      'billId': billId,
      'amount': amount,
      'paidFromAccountCode': paidFromAccountCode,
      if (date != null) 'date': date.toIso8601String(),
      if (reference != null) 'reference': reference,
    });
  }

  Future<void> voidBill({required String billId, required String reason}) async {
    await _functions.httpsCallable('voidBill').call<Map<String, dynamic>>({
      'schoolId': _actingUser.schoolId,
      'billId': billId,
      'reason': reason,
    });
  }
}
