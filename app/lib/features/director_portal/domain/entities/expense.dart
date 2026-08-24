class Expense {
  final String id;
  final String category;
  final String description;
  final double amount;
  final DateTime date;
  final String recordedByName;
  final String? receiptUrl;

  const Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.recordedByName,
    this.receiptUrl,
  });
}
