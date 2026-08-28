import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/schedules/domain/entities/schedule_block.dart';
import 'package:logicclass/features/schedules/presentation/documents/timetable_pdf.dart';

/// The printed timetable builds.
///
/// This is the sheet that gets taped to a classroom door, so the grid
/// has to survive the awkward shapes: a slot nobody else shares, two
/// blocks starting at the same minute on different days, and a class
/// with no room recorded.
ScheduleBlock block({
  required String subject,
  required int day,
  required int start,
  required int end,
  String? room = 'Room 201',
}) =>
    ScheduleBlock(
      id: '$subject$day$start',
      subject: subject,
      section: 'Grade 10 - Rizal',
      teacherId: 'u_faculty',
      teacherName: 'Maria Santos',
      room: room,
      dayOfWeek: day,
      startMinute: start,
      endMinute: end,
      schoolYear: '2026-2027',
    );

void main() {
  test('a week renders to a PDF', () async {
    final bytes = await TimetablePdf.build(
      title: 'Grade 10 - Rizal',
      subtitle: 'School Year 2026-2027',
      blocks: [
        for (var day = 1; day <= 5; day++)
          block(subject: 'Mathematics', day: day, start: 450, end: 510),
        for (final day in [1, 3, 5])
          block(subject: 'Science', day: day, start: 520, end: 580, room: 'Science Lab'),
        for (final day in [2, 4]) block(subject: 'English', day: day, start: 520, end: 580),
        // A 40-minute homeroom nobody else shares, and no room for it --
        // the two shapes a fixed hourly grid gets wrong.
        block(subject: 'Homeroom', day: 3, start: 590, end: 630, room: null),
      ],
      branding: const SchoolBranding(
        schoolName: 'Demo Academy of Bulacan',
        addressLine: 'Malolos, Bulacan',
        schoolYear: '2026-2027',
      ),
      preparedByName: 'Joel Bautista',
      on: DateTime(2026, 8, 27, 9, 15),
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF'));
  });

  test('an empty timetable still renders rather than throwing', () async {
    final bytes = await TimetablePdf.build(
      title: 'Grade 9 - Mabini',
      subtitle: 'School Year 2026-2027',
      blocks: const [],
      branding: const SchoolBranding(schoolName: 'Demo Academy of Bulacan'),
      preparedByName: 'Joel Bautista',
    );
    expect(String.fromCharCodes(bytes.take(5)), startsWith('%PDF'));
  });
}
