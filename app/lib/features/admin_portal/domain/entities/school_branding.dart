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

  /// Signatories printed on the back of an ID card. A school ID is only
  /// treated as valid with these on it, and they are school-wide rather
  /// than per-student, so they live here rather than on the record.
  final String? principalName;
  final String? directorName;

  /// The current school year, e.g. "2026-2027". Printed on every ID, which
  /// is what makes last year's card visibly expired.
  final String? schoolYear;

  final DateTime? updatedAt;
  final String? updatedByName;

  const SchoolBranding({
    this.logoUrl,
    this.logoFileName,
    this.schoolName,
    this.addressLine,
    this.principalName,
    this.directorName,
    this.schoolYear,
    this.updatedAt,
    this.updatedByName,
  });

  static const empty = SchoolBranding();

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;
}
