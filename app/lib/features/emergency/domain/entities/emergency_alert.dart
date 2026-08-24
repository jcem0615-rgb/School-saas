import '../../../../core/location/location_probe.dart';

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

  /// Where the student was when they pressed it, if their device could
  /// say. "Send help" is not actionable without "and here is where I am":
  /// a school is a big place and a student in trouble may not be able to
  /// describe where they are, or may not know.
  ///
  /// Captured once, at the moment the button is pressed, and never
  /// updated afterwards -- this is where they raised the alert, not a
  /// live track. Following someone around the campus after the fact is a
  /// different and much larger decision than recording where they called
  /// for help from.
  final double? latitude;
  final double? longitude;

  /// Radius in metres the true position is expected to lie within, as
  /// reported by the device. Shown to staff because a fix good to 5m and
  /// one good to 2km call for very different responses.
  final double? locationAccuracyMeters;

  /// Set instead when there is no fix, so staff can tell "the student
  /// declined to share" from "nobody ever asked". Without it, an alert
  /// with no location is ambiguous in exactly the moment when guessing is
  /// most expensive.
  final LocationFailure? locationFailure;

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
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.locationFailure,
    this.acknowledgedByName,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNote,
  });

  /// Both halves or neither -- a lone latitude is not a place.
  bool get hasLocation => latitude != null && longitude != null;

  bool get isAcknowledged => acknowledgedAt != null;
  bool get isResolved => resolvedAt != null;

  /// Still needs somebody. Drives the alert badge, so it is the one
  /// derived value worth naming rather than recomputing per screen.
  bool get isActive => resolvedAt == null;
}
