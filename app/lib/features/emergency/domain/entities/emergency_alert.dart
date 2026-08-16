/// A student pressing the emergency button.
///
/// The record exists for its own sake, not only to trigger a push. Push
/// depends on notification permission, a working service worker and a
/// configured Firebase project -- any of which can be missing on the day
/// it matters. An alert that is also a document means staff can see it in
/// the app regardless, and means there is a record afterwards of what was
/// raised and when.
class EmergencyAlert {
  final String id;
  final String studentId;
  final String studentName;
  final String section;

  /// The auth uid of the student who raised it. As with submissions, this
  /// rather than studentId is what firestore.rules anchors ownership on.
  final String userId;

  /// What kind of help is needed. Free text is deliberate: a fixed list
  /// would be a list of the emergencies somebody thought of in advance.
  final String? message;

  /// Server-stamped, like every other time in this app that anyone might
  /// later need to rely on.
  final DateTime raisedAt;

  /// Who acknowledged it, and when. An alert nobody has picked up looks
  /// different from one being dealt with, and staff need to be able to
  /// tell at a glance which is which.
  final String? acknowledgedByName;
  final DateTime? acknowledgedAt;

  /// Closed once the situation is over, with a note of what happened.
  final DateTime? resolvedAt;
  final String? resolutionNote;

  const EmergencyAlert({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.section,
    required this.userId,
    required this.raisedAt,
    this.message,
    this.acknowledgedByName,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNote,
  });

  bool get isAcknowledged => acknowledgedAt != null;
  bool get isResolved => resolvedAt != null;

  /// Still needs somebody. Drives the alert badge, so it is the one
  /// derived value worth naming rather than recomputing per screen.
  bool get isActive => resolvedAt == null;
}
