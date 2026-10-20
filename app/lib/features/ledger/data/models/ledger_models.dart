import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/ledger_account.dart';

class LedgerAccountModel extends LedgerAccount {
  const LedgerAccountModel({
    required super.code,
    required super.name,
    required super.type,
    super.isSystem,
    super.isActive,
    super.description,
  });

  factory LedgerAccountModel.fromFirestore(String id, Map<String, dynamic> data) {
    return LedgerAccountModel(
      // The document id is the code: "charge it to 5100" has to find the
      // document without a query.
      code: (data['code'] as String?)?.trim().isNotEmpty == true
          ? (data['code'] as String).trim()
          : id,
      name: data['name'] as String? ?? 'Unnamed account',
      type: AccountType.fromString(data['type'] as String? ?? ''),
      isSystem: data['isSystem'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true,
      description: data['description'] as String?,
    );
  }
}

class JournalEntryModel extends JournalEntry {
  const JournalEntryModel({
    required super.id,
    required super.entryNumber,
    required super.date,
    required super.memo,
    required super.source,
    required super.lines,
    required super.postedByName,
    required super.postedAt,
    super.sourceId,
    super.reversalOf,
    super.reversedBy,
  });

  factory JournalEntryModel.fromFirestore(String id, Map<String, dynamic> data) {
    final rawLines = (data['lines'] as List<dynamic>? ?? const []);
    return JournalEntryModel(
      id: id,
      entryNumber: data['entryNumber'] as String? ?? '',
      // Written from the server clock, so null in the local echo of a
      // document that has not round-tripped yet.
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memo: data['memo'] as String? ?? '',
      source: EntrySource.fromString(data['source'] as String? ?? ''),
      sourceId: data['sourceId'] as String?,
      lines: [
        for (final raw in rawLines)
          if (raw is Map<String, dynamic>)
            JournalLine(
              accountCode: raw['accountCode'] as String? ?? '',
              accountName: raw['accountName'] as String? ?? 'Unknown account',
              debit: (raw['debit'] as num?)?.toDouble() ?? 0,
              credit: (raw['credit'] as num?)?.toDouble() ?? 0,
              memo: raw['memo'] as String?,
            ),
      ],
      postedByName: data['postedByName'] as String? ?? 'Unknown',
      postedAt: (data['postedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reversalOf: data['reversalOf'] as String?,
      reversedBy: data['reversedBy'] as String?,
    );
  }
}
