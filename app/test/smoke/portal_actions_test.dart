import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/core/widgets/confirm_delete_dialog.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payments/presentation/screens/online_payment_screen.dart';
import 'package:logicclass/features/payments/presentation/screens/payment_settings_screen.dart';
import 'package:logicclass/features/timekeeping/presentation/screens/leave_requests_screen.dart';
import 'package:logicclass/features/timekeeping/presentation/screens/my_leave_screen.dart';
import 'package:logicclass/features/timekeeping/presentation/screens/timesheet_screen.dart';
import 'package:logicclass/features/class_sessions/presentation/screens/subject_attendance_screen.dart';
import 'package:logicclass/features/class_sessions/presentation/screens/todays_classes_screen.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/employee_list_screen.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/programs_screen.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/teacher_assignments_screen.dart';
import 'package:logicclass/features/director_portal/presentation/screens/announcements_screen.dart';
import 'package:logicclass/features/director_portal/presentation/screens/expenses_screen.dart';
import 'package:logicclass/features/director_portal/presentation/screens/meetings_screen.dart';
import 'package:logicclass/features/faculty_portal/presentation/screens/coursework_list_screen.dart';
import 'package:logicclass/features/faculty_portal/presentation/screens/grades_screen.dart';
import 'package:logicclass/features/faculty_portal/presentation/screens/material_requests_screen.dart';
import 'package:logicclass/features/guidance_portal/presentation/screens/guidance_records_screen.dart';
import 'package:logicclass/features/guidance_portal/presentation/screens/summons_screen.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_list_screen.dart';
import 'package:logicclass/features/staff_portal/presentation/screens/checklist_screen.dart';
import 'package:logicclass/features/staff_portal/presentation/screens/daily_reports_screen.dart';
import 'package:logicclass/features/student_portal/presentation/screens/promissory_note_screen.dart';

/// Exercises the primary action on every screen that has one.
///
/// Written after the demo role switcher was found sitting on top of the
/// FloatingActionButton on all 15 of these screens, which made every "New"
/// / "Add" / "Submit" button unreachable. A screenshot of one portal would
/// not have caught it everywhere, so this taps each one.
void main() {
  /// Screens whose FAB opens a create/edit form, with the role that uses them.
  final formScreens = <String, (UserRole, Widget)>{
    'Director · Announcements': (UserRole.director, const AnnouncementsScreen()),
    'Director · Meetings': (UserRole.director, const MeetingsScreen()),
    'Director · Expenses': (UserRole.director, const ExpensesScreen()),
    'Admin · Teacher Assignments': (UserRole.admin, const TeacherAssignmentsScreen()),
    'Admin · Programs': (UserRole.admin, const ProgramsScreen()),
    'Admin · Employees': (UserRole.admin, const EmployeeListScreen()),
    'Faculty · Coursework': (UserRole.faculty, const CourseworkListScreen()),
    'Faculty · Material Requests': (UserRole.faculty, const MaterialRequestsScreen()),
    'Guidance · Summons': (UserRole.guidance, const SummonsScreen()),
    'Staff · My Leave': (UserRole.staff, const MyLeaveScreen()),
    'Staff · Checklist': (UserRole.staff, const ChecklistScreen()),
    'Staff · Daily Reports': (UserRole.staff, const DailyReportsScreen()),
    'Registrar · Students': (UserRole.registrar, const StudentListScreen()),
    'Student · Promissory Note': (UserRole.student, const PromissoryNoteScreen()),
  };

  Future<ProviderContainer> pumpAs(
    WidgetTester tester,
    UserRole role,
    Widget screen,
  ) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Screens whose whole job is to show something, with no form behind a
  /// button. They are here for the same reason the ones above are: a
  /// screen that throws on open is a dead end, and nothing else in the
  /// suite renders these.
  final readOnlyScreens = <String, (UserRole, Widget)>{
    'Faculty · My classes today': (UserRole.faculty, const TodaysClassesScreen()),
    'Admin · Leave requests': (UserRole.admin, const LeaveRequestsScreen()),
    'Admin · Timesheets': (UserRole.admin, const TimesheetScreen()),
    'Staff · My timesheet': (UserRole.staff, const MyTimesheetScreen()),
    'Registrar · Payment setup': (UserRole.registrar, const PaymentSettingsScreen()),
    'Parent · Pay online': (
      UserRole.parent,
      OnlinePaymentScreen(
        studentId: 'stu_001',
        studentName: 'Miguel Torres',
        outstandingBalance: 12500,
      ),
    ),
    'Student · Attendance by subject': (
      UserRole.student,
      const SubjectAttendanceScreen(studentId: 'stu_001'),
    ),
    'Parent · Attendance by subject': (
      UserRole.parent,
      const SubjectAttendanceScreen(studentId: 'stu_001', studentName: 'Miguel Torres'),
    ),
  };

  group('read-only screens open', () {
    readOnlyScreens.forEach((label, spec) {
      final (role, screen) = spec;

      testWidgets(label, (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await pumpAs(tester, role, screen);

        expect(tester.takeException(), isNull, reason: '$label threw on open');
        expect(find.byType(Scaffold), findsWidgets,
            reason: '$label rendered nothing');
      });
    });
  });

  group('every screen with a primary action can open it', () {
    formScreens.forEach((label, spec) {
      final (role, screen) = spec;

      testWidgets(label, (tester) async {
        // A phone-sized viewport is the tightest case for a FAB being
        // reachable; anything wider only gives it more room.
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await pumpAs(tester, role, screen);

        expect(tester.takeException(), isNull, reason: '$label threw on open');

        final fab = find.byType(FloatingActionButton);
        expect(fab, findsOneWidget, reason: '$label has no primary action button');

        // The button must be tappable, not merely present -- being covered
        // by another widget is exactly the bug this guards against.
        await tester.tap(fab.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '$label threw on tap');

        // Tapping it must surface a form: either a dialog or a bottom sheet.
        final openedForm = find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.byType(BottomSheet).evaluate().isNotEmpty;
        expect(openedForm, isTrue, reason: '$label opened no form when tapped');
      });
    });
  });

  // Grades and Guidance Records gate their primary action behind a
  // selection -- you pick a subject/section, or load a student, and only
  // then can you submit a grade or add a note. That is deliberate, so the
  // test performs the prerequisite instead of asserting a FAB up front.
  group('screens whose action unlocks after a selection', () {
    testWidgets('Faculty · Grades', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpAs(tester, UserRole.faculty, const GradesScreen());
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'no subject/section chosen yet');

      await tester.enterText(find.byType(TextField).at(0), 'Mathematics');
      await tester.enterText(find.byType(TextField).at(1), 'Grade 10 - Rizal');
      await tester.tap(find.widgetWithText(FilledButton, 'Load'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FloatingActionButton), findsOneWidget,
          reason: 'Submit Grade should appear once a section is loaded');

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Guidance · Records', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpAs(tester, UserRole.guidance, const GuidanceRecordsScreen());

      // Unlike Grades, this action is available immediately: a guidance
      // note does not require a student, because a note can be filed
      // against a whole section. Gating the button on a loaded student
      // would make section-level notes impossible to create.
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Section'), findsWidgets);
    });

    testWidgets('Guidance · Records still loads a student roster', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpAs(tester, UserRole.guidance, const GuidanceRecordsScreen());

      await tester.enterText(find.byType(TextField).at(0), 'stu_001');
      await tester.tap(find.widgetWithText(FilledButton, 'Load Records'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('rows expose edit and delete', () {
    final rowScreens = <String, (UserRole, Widget)>{
      'Director · Announcements': (UserRole.director, const AnnouncementsScreen()),
      'Director · Meetings': (UserRole.director, const MeetingsScreen()),
      'Director · Expenses': (UserRole.director, const ExpensesScreen()),
      'Admin · Teacher Assignments': (UserRole.admin, const TeacherAssignmentsScreen()),
      'Admin · Programs': (UserRole.admin, const ProgramsScreen()),
      'Faculty · Coursework': (UserRole.faculty, const CourseworkListScreen()),
      'Guidance · Summons': (UserRole.guidance, const SummonsScreen()),
      'Staff · Checklist': (UserRole.staff, const ChecklistScreen()),
    };

    rowScreens.forEach((label, spec) {
      final (role, screen) = spec;

      testWidgets(label, (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await pumpAs(tester, role, screen);

        final menus = find.byType(RowActionsMenu);
        expect(menus, findsWidgets, reason: '$label rows have no actions menu');

        await tester.tap(menus.first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Edit'), findsOneWidget, reason: '$label has no Edit');
        expect(find.text('Delete'), findsOneWidget, reason: '$label has no Delete');
      });
    });
  });
}
