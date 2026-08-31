import '../../../../core/constants/education_level.dart';
import '../../../faculty_portal/domain/entities/quarterly_grade.dart';
import 'student_summary.dart';

/// What happens to a student at the end of the year.
///
/// Named for what a registrar writes in the record, not for a state
/// machine: "promoted", "retained", "graduated" are the words on a Form
/// 137 and the words a parent is told.
enum PromotionOutcome {
  promoted('promoted', 'Promoted'),

  /// Passed the year but with subjects to make up first. DepEd's wording
  /// is "promoted after passing remedial classes", which is a promotion
  /// that has not happened yet -- so it is its own outcome rather than a
  /// promotion with an asterisk, and a school that ignores the remedial
  /// classes cannot accidentally promote by leaving the row alone.
  conditional('conditional', 'Remedial required'),

  retained('retained', 'Retained'),

  /// The end of the road at this school: the exit year of the highest
  /// division the school actually runs.
  graduated('graduated', 'Graduated'),

  /// Nothing was decided. A student with no grades on file, or one the
  /// registrar deliberately held back from the run.
  held('held', 'No decision');

  final String value;
  final String displayLabel;
  const PromotionOutcome(this.value, this.displayLabel);

  static PromotionOutcome fromString(String value) => PromotionOutcome.values
      .firstWhere((o) => o.value == value, orElse: () => PromotionOutcome.held);

  /// Whether this outcome moves the student out of their current year.
  bool get advances => this == PromotionOutcome.promoted;
}

/// How many failed subjects turn a promotion into remedial work, and
/// then into retention.
///
/// DepEd Order 8, s. 2015 for Grades 1-10: all subjects passed is a
/// promotion; one or two failed means promotion after passing remedial
/// classes; three or more is retention. Senior High is assessed per
/// semester against its own rules, and a college runs on units and
/// standing rather than on this at all.
///
/// So these are a **starting point for a person**, not a decision. Every
/// row on the rollover screen can be changed, nothing is written until
/// somebody presses the button, and the reason each recommendation says
/// what it says is printed beside it.
const failedSubjectsRequiringRemedial = 1;
const failedSubjectsForcingRetention = 3;

/// One student, their year, and what is recommended for them.
class PromotionCandidate {
  final StudentSummary student;

  /// The final grade per subject across the year -- the mean of the
  /// quarters that have marks in them, which is the number a Form 138
  /// carries.
  final Map<String, int> finalGradeBySubject;

  /// Subjects below the passing mark. The list, not the count, because a
  /// registrar deciding whether to override needs to see which ones.
  final List<String> failedSubjects;

  /// The mean of the final grades, or null when nothing has been graded.
  final int? generalAverage;

  final PromotionOutcome recommended;

  /// Where the student goes if the outcome advances them. Null when the
  /// next year cannot be worked out from the grade level as written --
  /// see [nextGradeLevel].
  final String? nextGradeLevel;

  const PromotionCandidate({
    required this.student,
    required this.finalGradeBySubject,
    required this.failedSubjects,
    required this.generalAverage,
    required this.recommended,
    required this.nextGradeLevel,
  });

  bool get hasGrades => generalAverage != null;

  /// Why the recommendation says what it says, in one line, for the
  /// registrar deciding whether to override it.
  String get reason {
    if (!hasGrades) {
      return 'No grades on file for this year.';
    }
    if (recommended == PromotionOutcome.graduated) {
      return 'Finishing ${student.gradeLevel}, the last year this school runs '
          'for ${student.educationLevel.shortLabel}.';
    }
    if (failedSubjects.isEmpty) {
      return 'General average $generalAverage, every subject passed.';
    }
    final list = failedSubjects.join(', ');
    if (recommended == PromotionOutcome.retained) {
      return '${failedSubjects.length} subjects below 75: $list.';
    }
    return '${failedSubjects.length} subject'
        '${failedSubjects.length == 1 ? '' : 's'} below 75: $list.';
  }
}

/// The next year up, read out of a grade level written as free text.
///
/// Grade levels in this system are typed by the school -- "Grade 10",
/// "Grade 4", "1st Year", "Year 2" -- so the next one has to be read out
/// of what they typed rather than looked up in a list this app does not
/// have.
///
/// Returns null when there is no single number in the text to advance.
/// **Refusing is the point.** A rollover puts a child in a year; a guess
/// puts them in the wrong one, and the registrar finds out in June when
/// the class list is wrong. A null here shows on the screen as a row that
/// needs a destination typed in, which is a question, not a silent error.
String? nextGradeLevel(String gradeLevel) {
  final matches = RegExp(r'\d+').allMatches(gradeLevel);
  if (matches.length != 1) return null;

  final match = matches.single;
  final current = int.parse(match.group(0)!);
  final next = current + 1;

  final head = gradeLevel.substring(0, match.start);
  final tail = gradeLevel.substring(match.end);

  // "1st Year" -> "2nd Year": the ordinal suffix belongs to the number
  // and has to move with it, or the school gets "2st Year".
  final ordinal = RegExp(r'^(st|nd|rd|th)', caseSensitive: false).firstMatch(tail);
  if (ordinal != null) {
    return '$head$next${_ordinalSuffix(next)}${tail.substring(ordinal.end)}';
  }
  return '$head$next$tail';
}

String _ordinalSuffix(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  return switch (n % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

/// The section name carried forward a year.
///
/// Sections in PH schools are usually named after the year they belong
/// to -- "Grade 9 - Rizal" -- so the same group of children next year is
/// "Grade 10 - Rizal". Swapping the year inside the name gets that right
/// far more often than not, and it is only a suggestion: the field is
/// editable, and a school that renames its sections every year overwrites
/// it.
///
/// Returns null when the current year does not appear in the section
/// name at all. Guessing there would produce a section that does not
/// exist and put a whole class in it.
String? nextSectionName({
  required String section,
  required String fromGradeLevel,
  required String toGradeLevel,
}) {
  final from = fromGradeLevel.trim();
  if (from.isEmpty || !section.toLowerCase().contains(from.toLowerCase())) return null;

  final at = section.toLowerCase().indexOf(from.toLowerCase());
  return section.substring(0, at) + toGradeLevel + section.substring(at + from.length);
}

/// The school year today falls in, written the way schools write it.
///
/// The PH school year opens around June, so a date in the first half of
/// the calendar year belongs to the year that started the previous June.
/// Getting this backwards would default the rollover screen to the year
/// that has not happened yet.
String currentSchoolYear(DateTime today) {
  final start = today.month >= 6 ? today.year : today.year - 1;
  return '$start-${start + 1}';
}

/// The last year of a division, as far as this school is concerned.
///
/// Whether a Grade 6 pupil graduates or moves into Grade 7 depends on
/// whether the school runs a Junior High at all, and the same question
/// decides Grade 10. That is answered from the divisions the school
/// actually has students in rather than from a setting somebody would
/// have to keep current: a school with no Senior High students has no
/// Senior High, whatever a checkbox says, and the roster is the thing
/// that cannot be out of date.
bool isExitYear({
  required StudentSummary student,
  required Set<EducationLevel> divisionsInUse,
}) {
  final higher = EducationLevel.values
      .where((level) => level.index > student.educationLevel.index)
      .where(divisionsInUse.contains);

  // Somewhere above them in this school, so the top of their own
  // division is a move rather than an ending -- but only from the last
  // year of it.
  final continues = higher.isNotEmpty;

  return switch (student.educationLevel) {
    EducationLevel.elementary => _yearIn(student.gradeLevel) == 6 && !continues,
    EducationLevel.highSchool => _yearIn(student.gradeLevel) == 10 && !continues,
    // Senior High ends at Grade 12 whatever else the school runs: a
    // college in the same building does not make Grade 12 a middle year,
    // because a Senior High graduate applies to college, they are not
    // rolled into it.
    EducationLevel.seniorHigh => _yearIn(student.gradeLevel) == 12,
    EducationLevel.college => _yearIn(student.gradeLevel) == 4,
  };
}

int? _yearIn(String gradeLevel) {
  final matches = RegExp(r'\d+').allMatches(gradeLevel);
  if (matches.length != 1) return null;
  return int.parse(matches.single.group(0)!);
}

/// Works out what to recommend for one student.
///
/// Pure, and takes the year's computed grades rather than raw marks, so
/// the arithmetic that produces a final grade lives in exactly one place
/// -- the same one the report card prints from.
PromotionCandidate recommendPromotion({
  required StudentSummary student,
  required List<QuarterlyGrade> yearsGrades,
  required Set<EducationLevel> divisionsInUse,
}) {
  final bySubject = <String, List<QuarterlyGrade>>{};
  for (final grade in yearsGrades.where((g) => g.hasWork)) {
    (bySubject[grade.subject] ??= []).add(grade);
  }

  final finals = <String, int>{
    for (final entry in bySubject.entries)
      entry.key: (entry.value.fold<int>(0, (sum, g) => sum + g.finalGrade) /
              entry.value.length)
          .round(),
  };

  final failed = finals.entries
      .where((e) => !isPassing(e.value))
      .map((e) => e.key)
      .toList()
    ..sort();

  final average = finals.isEmpty
      ? null
      : (finals.values.reduce((a, b) => a + b) / finals.length).round();

  final next = nextGradeLevel(student.gradeLevel);

  final PromotionOutcome outcome;
  if (finals.isEmpty) {
    // Nothing to decide on. Recommending a promotion off no evidence
    // would move a child up a year on the strength of a teacher not
    // having entered anything.
    outcome = PromotionOutcome.held;
  } else if (failed.length >= failedSubjectsForcingRetention) {
    outcome = PromotionOutcome.retained;
  } else if (failed.length >= failedSubjectsRequiringRemedial) {
    outcome = PromotionOutcome.conditional;
  } else if (isExitYear(student: student, divisionsInUse: divisionsInUse)) {
    outcome = PromotionOutcome.graduated;
  } else {
    outcome = PromotionOutcome.promoted;
  }

  return PromotionCandidate(
    student: student,
    finalGradeBySubject: finals,
    failedSubjects: failed,
    generalAverage: average,
    recommended: outcome,
    nextGradeLevel: next,
  );
}

/// One student's line in a rollover, as the registrar has left it.
///
/// Separate from [PromotionCandidate] because a recommendation and a
/// decision are different things: the candidate is what the marks say,
/// this is what the school says, and the record keeps both so a decision
/// that departed from the recommendation is visible afterwards.
class PromotionDecision {
  final String studentId;
  final String studentName;
  final PromotionOutcome recommended;
  final PromotionOutcome outcome;

  final String fromGradeLevel;
  final String fromSection;

  /// Where they are going. Empty for an outcome that does not move them.
  final String toGradeLevel;
  final String toSection;

  final int? generalAverage;
  final List<String> failedSubjects;

  const PromotionDecision({
    required this.studentId,
    required this.studentName,
    required this.recommended,
    required this.outcome,
    required this.fromGradeLevel,
    required this.fromSection,
    required this.toGradeLevel,
    required this.toSection,
    required this.generalAverage,
    required this.failedSubjects,
  });

  bool get departsFromRecommendation => outcome != recommended;

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'studentName': studentName,
        'recommended': recommended.value,
        'outcome': outcome.value,
        'fromGradeLevel': fromGradeLevel,
        'fromSection': fromSection,
        'toGradeLevel': toGradeLevel,
        'toSection': toSection,
        'generalAverage': generalAverage,
        'failedSubjects': failedSubjects,
      };
}

/// What a finished rollover looks like: the counts a registrar reports.
class RolloverSummary {
  final int promoted;
  final int conditional;
  final int retained;
  final int graduated;
  final int held;

  const RolloverSummary({
    required this.promoted,
    required this.conditional,
    required this.retained,
    required this.graduated,
    required this.held,
  });

  factory RolloverSummary.of(Iterable<PromotionOutcome> outcomes) {
    var promoted = 0, conditional = 0, retained = 0, graduated = 0, held = 0;
    for (final outcome in outcomes) {
      switch (outcome) {
        case PromotionOutcome.promoted:
          promoted++;
        case PromotionOutcome.conditional:
          conditional++;
        case PromotionOutcome.retained:
          retained++;
        case PromotionOutcome.graduated:
          graduated++;
        case PromotionOutcome.held:
          held++;
      }
    }
    return RolloverSummary(
      promoted: promoted,
      conditional: conditional,
      retained: retained,
      graduated: graduated,
      held: held,
    );
  }

  int get total => promoted + conditional + retained + graduated + held;
}
