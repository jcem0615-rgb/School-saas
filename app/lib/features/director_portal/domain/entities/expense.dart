/// Money the school spent.
///
/// [receiptUrl] is the substantiation, and until recently it was a field
/// nothing could fill: it existed on this entity, in the model, through
/// the repository and the data source and into the document, and no
/// screen ever set it. Worse, the update path wrote it unconditionally
/// from a dialog that did not carry it -- so on the day something did
/// populate it, the first edit would have quietly erased it.
class Expense {
  final String id;
  final String category;
  final String description;
  final double amount;
  final DateTime date;
  final String recordedByName;

  /// The scanned or photographed receipt. Null when the school has not
  /// attached one, which is a state worth being able to see rather than
  /// one to pretend away.
  final String? receiptUrl;

  /// What the file was called when it was attached. Shown on the row and
  /// used as the name it is saved under, so "receipt.pdf" for everything
  /// is not what lands in somebody's Downloads folder.
  final String? receiptFileName;

  const Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.recordedByName,
    this.receiptUrl,
    this.receiptFileName,
  });

  bool get hasReceipt => receiptUrl != null && receiptUrl!.isNotEmpty;
}
