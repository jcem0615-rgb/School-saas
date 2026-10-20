/// Somebody the school buys from.
///
/// Thin on purpose. A school's supplier list is a name, a way to reach
/// them, a TIN for the BIR, and how long they give you to pay -- and a
/// form asking for twelve fields is a form filled in with one.
class Vendor {
  final String id;
  final String name;

  /// Taxpayer Identification Number. Printed on a voucher and asked for
  /// at audit; optional because a sari-sari store down the road has
  /// none and the school still buys chalk there.
  final String? tin;

  /// How many days after the bill date it falls due.
  ///
  /// Zero means cash on delivery, which is most of them. Stored on the
  /// vendor so a bill can fill its own due date in -- a date somebody
  /// has to work out by hand is a date that gets typed as today.
  final int paymentTermsDays;

  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;

  const Vendor({
    required this.id,
    required this.name,
    this.tin,
    this.paymentTermsDays = 0,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.isActive = true,
  });

  /// "Net 30", "Cash on delivery" -- the way it is said out loud.
  String get termsLabel =>
      paymentTermsDays <= 0 ? 'Cash on delivery' : 'Net $paymentTermsDays';

  /// When a bill dated [billDate] from this vendor falls due.
  DateTime dueDateFor(DateTime billDate) =>
      DateTime(billDate.year, billDate.month, billDate.day + paymentTermsDays);

  Vendor copyWith({
    String? name,
    String? tin,
    int? paymentTermsDays,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool? isActive,
  }) =>
      Vendor(
        id: id,
        name: name ?? this.name,
        tin: tin ?? this.tin,
        paymentTermsDays: paymentTermsDays ?? this.paymentTermsDays,
        contactName: contactName ?? this.contactName,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        isActive: isActive ?? this.isActive,
      );
}
