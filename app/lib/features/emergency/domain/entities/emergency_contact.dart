/// One number to call when something goes wrong: BFP, PNP, the nearest
/// hospital, the school clinic.
///
/// Maintained by the school's admin roles and readable by *everyone* in
/// the tenant -- students, parents and staff alike. That is unusual in
/// this schema, where most collections are scoped tightly, and it is
/// deliberate: a number nobody can reach in a fire is not a safety
/// feature. Nothing here is personal data; it is the same information a
/// school prints on a poster by the door.
class EmergencyContact {
  final String id;

  /// Who answers: "Bureau of Fire Protection", "PNP - San Nicolas".
  final String label;

  final String phone;

  /// Optional context a caller needs in the moment -- "Ask for the desk
  /// officer", "Landline only", a station address.
  final String? notes;

  /// Lower sorts first. The order is a safety decision, not a
  /// preference: whoever should be called first in this school's
  /// situation belongs at the top of the list, and that is not always
  /// the same service.
  final int sortOrder;

  final DateTime updatedAt;
  final String updatedByName;

  const EmergencyContact({
    required this.id,
    required this.label,
    required this.phone,
    required this.sortOrder,
    required this.updatedAt,
    required this.updatedByName,
    this.notes,
  });

  /// Strips everything a dialler cannot use. PH numbers get written a
  /// dozen ways -- "(043) 555-0100", "0917 555 0142" -- and a tel: link
  /// built from the raw string fails on the punctuation.
  String get dialable => phone.replaceAll(RegExp(r'[^0-9+]'), '');
}
