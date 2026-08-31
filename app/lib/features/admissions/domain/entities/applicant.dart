import '../../../../core/constants/education_level.dart';

/// Where a family has got to.
///
/// A private school's year is won or lost between January and June, and
/// the thing that loses it is not a decision -- it is a family who
/// enquired in February, was never rung back, and enrolled somewhere
/// else in April. Nobody at the school can say how many of those there
/// were, because the enquiry was a note in a logbook and the logbook has
/// no column for what happened next.
///
/// So the stages are the ones a school actually moves a family through,
/// and every applicant is in exactly one of them at all times. The two
/// endings are as important as the middle: a family that went elsewhere
/// is not the same as one nobody has got back to, and a pipeline that
/// cannot tell them apart is a pipeline that reports itself as busy
/// while it is really just stuck.
enum AdmissionStage {
  /// Somebody asked. A phone call, a walk-in, a message.
  inquiry('inquiry', 'Enquiry'),

  /// They have handed in a form and requirements.
  applied('applied', 'Applied'),

  /// Booked in for the entrance test.
  examScheduled('exam_scheduled', 'Exam scheduled'),

  /// Sat it. The score lives on the applicant.
  examTaken('exam_taken', 'Exam taken'),

  /// The school has said yes and the family has not answered yet.
  offered('offered', 'Offered a place'),

  /// The reservation fee is in. The place is held.
  reserved('reserved', 'Place reserved'),

  /// They are a student. This is the only stage with a student record
  /// behind it.
  enrolled('enrolled', 'Enrolled'),

  /// The school said no.
  declined('declined', 'Not accepted'),

  /// The family stopped, or went elsewhere. Kept apart from [declined]
  /// because "we turned down forty" and "forty walked away" are
  /// different problems and only one of them is the school's doing.
  withdrawn('withdrawn', 'Withdrew');

  final String value;
  final String displayLabel;
  const AdmissionStage(this.value, this.displayLabel);

  static AdmissionStage fromString(String value) => AdmissionStage.values
      .firstWhere((s) => s.value == value, orElse: () => AdmissionStage.inquiry);

  /// Whether this is an ending. Nothing moves on from here.
  bool get isClosed =>
      this == AdmissionStage.enrolled ||
      this == AdmissionStage.declined ||
      this == AdmissionStage.withdrawn;

  /// Whether the family is still in play. What the funnel counts as
  /// "open", and what the follow-up list is drawn from.
  bool get isOpen => !isClosed;
}

/// The stages a school moves a family forward through, in order.
///
/// The two endings are not in it: they are reachable from anywhere and
/// are not steps along the way.
const admissionPipeline = <AdmissionStage>[
  AdmissionStage.inquiry,
  AdmissionStage.applied,
  AdmissionStage.examScheduled,
  AdmissionStage.examTaken,
  AdmissionStage.offered,
  AdmissionStage.reserved,
  AdmissionStage.enrolled,
];

/// Which stages an applicant may be moved to from where they are.
///
/// Deliberately not "any stage to any stage". A pipeline whose stages can
/// be set freely stops meaning anything within a term -- somebody marks a
/// family as offered because that is the outcome they expect, and the
/// funnel then reports offers the school never made.
///
/// What it allows: the next step forward, either ending, and one step
/// back. The step back is not a nicety: a family gets marked as offered
/// by mistake, and a pipeline with no way to correct that is one people
/// work around by making a second record for the same child.
List<AdmissionStage> nextStagesFrom(AdmissionStage current) {
  if (current == AdmissionStage.enrolled) {
    // The one stage with a student record behind it. Moving out of it
    // would leave a student enrolled in the school with an applicant
    // record saying they withdrew.
    return const [];
  }
  if (current.isClosed) {
    // A family who was turned down or walked away can come back, and
    // they come back to the beginning of what is left rather than to
    // wherever they had reached months ago.
    return const [AdmissionStage.inquiry];
  }

  final at = admissionPipeline.indexOf(current);
  return [
    if (at >= 0 && at + 1 < admissionPipeline.length) admissionPipeline[at + 1],
    if (at > 0) admissionPipeline[at - 1],
    AdmissionStage.declined,
    AdmissionStage.withdrawn,
  ];
}

/// One family, from the first phone call to the day they enrol.
class Applicant {
  final String id;

  /// What the school calls this enquiry on paper. Sequential, so a
  /// family ringing back can be found by it.
  final String referenceNumber;

  final String firstName;
  final String lastName;
  final String? middleName;

  /// Which division and year they are applying into. Free text for the
  /// year, the same as a student record, because the school names its
  /// own years.
  final EducationLevel educationLevel;
  final String gradeLevel;

  /// Senior High strand or a college program, when the division uses the
  /// catalogue.
  final String? programId;
  final String? programName;

  final String guardianName;
  final String guardianPhone;
  final String? guardianEmail;

  /// Where they heard about the school. The single most useful field on
  /// this record for a school deciding where to spend next year's
  /// advertising, and the one nobody records anywhere today.
  final String? source;

  final AdmissionStage stage;
  final DateTime inquiredAt;

  /// When the stage last changed. What the follow-up list is computed
  /// from -- not [inquiredAt], because a family being actively worked
  /// through the stages is not going cold.
  final DateTime stageChangedAt;

  final DateTime? examScheduledFor;

  /// Out of [examMaxScore]. Null until they sit it.
  final double? examScore;
  final double? examMaxScore;

  /// What has actually been paid to hold the place.
  final double reservationFeePaid;
  final DateTime? reservationPaidAt;
  final String? reservationReference;

  /// Set once, when the applicant becomes a student. Its presence is
  /// what makes enrolling twice impossible.
  final String? studentId;

  final String? notes;
  final String? lastUpdatedByName;

  const Applicant({
    required this.id,
    required this.referenceNumber,
    required this.firstName,
    required this.lastName,
    required this.educationLevel,
    required this.gradeLevel,
    required this.guardianName,
    required this.guardianPhone,
    required this.stage,
    required this.inquiredAt,
    required this.stageChangedAt,
    this.middleName,
    this.programId,
    this.programName,
    this.guardianEmail,
    this.source,
    this.examScheduledFor,
    this.examScore,
    this.examMaxScore,
    this.reservationFeePaid = 0,
    this.reservationPaidAt,
    this.reservationReference,
    this.studentId,
    this.notes,
    this.lastUpdatedByName,
  });

  String get fullName => '$firstName $lastName';

  bool get hasEnrolled => studentId != null;

  /// The exam as a percentage, or null when it has not been sat.
  ///
  /// Null rather than zero: a child who has not taken the test has not
  /// failed it, and a list sorted by score would otherwise put them
  /// below everybody who did badly.
  double? get examPercentage {
    final score = examScore;
    final max = examMaxScore;
    if (score == null || max == null || max <= 0) return null;
    return (score / max * 1000).roundToDouble() / 10;
  }

  /// How long they have been sitting where they are.
  int daysInStage(DateTime asOf) =>
      _dayOf(asOf).difference(_dayOf(stageChangedAt)).inDays;
}

DateTime _dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

/// How long an open applicant may sit in one stage before the office
/// should be ringing them.
///
/// A week. Short enough that a family who enquired on Monday is chased
/// before they enrol somewhere else, long enough that a normal week does
/// not fill the list with everybody. It is one number rather than one per
/// stage on purpose: a per-stage table is a thing nobody tunes and
/// everybody argues about, and the office's real question is simply "who
/// have we not spoken to lately".
const admissionFollowUpDays = 7;

/// The open applicants nobody has moved in a while, longest wait first.
///
/// This is the list that makes the whole module earn its keep. The funnel
/// tells a director what happened last year; this tells the office who to
/// ring this morning.
List<Applicant> applicantsNeedingFollowUp(
  Iterable<Applicant> applicants, {
  required DateTime asOf,
  int afterDays = admissionFollowUpDays,
}) {
  final waiting = applicants
      .where((a) => a.stage.isOpen)
      .where((a) => a.daysInStage(asOf) >= afterDays)
      .toList()
    ..sort((a, b) => b.daysInStage(asOf).compareTo(a.daysInStage(asOf)));
  return waiting;
}

/// The funnel: how many reached each stage, and how many are still there.
///
/// "Reached" and "are there now" are different numbers and a school needs
/// both. Forty families are at the enquiry stage today; four hundred
/// passed through it this year. A report that gave only the second looks
/// like a school with no pipeline at all by June.
class AdmissionFunnel {
  /// How many applicants are sitting in each stage right now.
  final Map<AdmissionStage, int> nowIn;

  /// How many have reached at least each stage. An enrolled student is
  /// counted at every stage up to and including enrolled, because they
  /// went through all of them.
  final Map<AdmissionStage, int> reached;

  final int total;

  const AdmissionFunnel({
    required this.nowIn,
    required this.reached,
    required this.total,
  });

  factory AdmissionFunnel.of(Iterable<Applicant> applicants) {
    final nowIn = {for (final stage in AdmissionStage.values) stage: 0};
    final reached = {for (final stage in admissionPipeline) stage: 0};
    var total = 0;

    for (final applicant in applicants) {
      total++;
      nowIn[applicant.stage] = (nowIn[applicant.stage] ?? 0) + 1;

      // A closed applicant reached whatever they had reached before
      // closing, which this record does not carry. Counting them only
      // where they are is the honest reading: the funnel says how far
      // the families who are still in it have got, and the two endings
      // are counted on their own.
      final at = admissionPipeline.indexOf(applicant.stage);
      for (var i = 0; i <= at; i++) {
        reached[admissionPipeline[i]] = (reached[admissionPipeline[i]] ?? 0) + 1;
      }
    }

    return AdmissionFunnel(nowIn: nowIn, reached: reached, total: total);
  }

  int get enrolled => nowIn[AdmissionStage.enrolled] ?? 0;
  int get declined => nowIn[AdmissionStage.declined] ?? 0;
  int get withdrawn => nowIn[AdmissionStage.withdrawn] ?? 0;
  int get open => total - enrolled - declined - withdrawn;

  /// Enrolments as a percentage of everybody who ever enquired, to one
  /// decimal place. Null when nobody has.
  double? get conversionRate {
    if (total == 0) return null;
    return (enrolled / total * 1000).roundToDouble() / 10;
  }

  /// What share of the families who reached [from] went on to reach
  /// [to]. Null when nobody reached [from] -- which is not zero, and a
  /// report showing 0% for a stage nobody has got to yet is a report
  /// that reads as a disaster.
  double? rateBetween(AdmissionStage from, AdmissionStage to) {
    final start = reached[from] ?? 0;
    if (start == 0) return null;
    return ((reached[to] ?? 0) / start * 1000).roundToDouble() / 10;
  }
}
