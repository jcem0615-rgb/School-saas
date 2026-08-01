/// The school's visual identity: logo and name as they should appear on
/// screen and on printed IDs.
///
/// Stored per school rather than per user, and readable by the whole
/// tenant -- a student's own e-ID has to carry the school's logo, so
/// restricting reads to staff would break the thing the logo is for.
class SchoolBranding {
  final String? logoUrl;
  final String? logoFileName;

  /// Shown on the e-ID. Falls back to the tenant's registered name when
  /// the admin has not set a display name.
  final String? schoolName;

  /// Printed under the school name on an ID card.
  final String? addressLine;

  final DateTime? updatedAt;
  final String? updatedByName;

  const SchoolBranding({
    this.logoUrl,
    this.logoFileName,
    this.schoolName,
    this.addressLine,
    this.updatedAt,
    this.updatedByName,
  });

  static const empty = SchoolBranding();

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;
}
