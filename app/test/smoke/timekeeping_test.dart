import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/notifications/domain/entities/app_notification.dart';
import 'package:logicclass/features/timekeeping/domain/entities/leave_request.dart';
import 'package:logicclass/features/timekeeping/domain/entities/timesheet.dart';
import 'package:logicclass/features/timekeeping/presentation/controllers/timekeeping_controller.dart';

/// Filing leave, deciding it, and the timesheet that reads both.
///
/// The demo repositories mirror what firestore.rules enforces, so the
/// refusals here are the same refusals a real deployment makes. The last
/// group is the point of the whole feature: an approved day is leave and
/// an unexplained one is absence, and only the pairing of the two
/// records can tell them apart.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  /// Held open: these notifiers set state after an await, and Riverpod
  /// disposes one the moment nothing is listening.
  TimekeepingActionController actions(ProviderContainer container) {
    final sub = container.listen(timekeepingActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(timekeepingActionControllerProvider.notifier);
  }

  LeaveRequest byId(DemoStore store, String id) =>
      store.leaveRequests.value.firstWhere((r) => r.id == id);

  group('filing', () {
    test('records it as pending, under the person who filed it', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final before = store.leaveRequests.value.length;

      final ok = await actions(container).fileLeave(
        type: LeaveType.vacation,
        from: DateTime.now().add(const Duration(days: 7)),
        to: DateTime.now().add(const Duration(days: 9)),
        reason: 'Wedding in Iloilo.',
      );

      expect(ok, isTrue);
      expect(store.leaveRequests.value.length, before + 1);
      final filed = store.leaveRequests.value.first;
      expect(filed.employeeUid, 'u_faculty');
      // Never pre-approved. A request that arrived decided would make
      // the decision step decorative.
      expect(filed.status, LeaveStatus.pending);
      expect(filed.decidedByUid, isNull);
      expect(filed.days, greaterThan(0));
    });

    test('counts working days, not calendar days', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);

      // A Monday to the following Monday: six working days, not eight.
      final monday = _nextWeekday(DateTime.now(), DateTime.monday);
      await actions(container).fileLeave(
        type: LeaveType.vacation,
        from: monday,
        to: monday.add(const Duration(days: 7)),
        reason: 'A week away.',
      );

      expect(store.leaveRequests.value.first.days, 6);
    });
  });

  group('withdrawing', () {
    test('an employee withdraws their own pending request', () async {
      final container = await signedInAs(UserRole.staff);
      final store = container.read(demoStoreProvider);

      // lv_001 is Ricardo Bautista's pending vacation leave.
      expect(byId(store, 'lv_001').isPending, isTrue);
      expect(await actions(container).cancelLeave('lv_001'), isTrue);
      expect(byId(store, 'lv_001').status, LeaveStatus.cancelled);
    });

    test('but not a colleague\'s', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);

      expect(await actions(container).cancelLeave('lv_001'), isFalse);
      expect(byId(store, 'lv_001').status, LeaveStatus.pending);
    });

    test('and not one already approved', () async {
      // A request cannot be un-approved by the person it was approved
      // for -- the timesheet is already built on it.
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);

      expect(byId(store, 'lv_002').status, LeaveStatus.approved);
      expect(await actions(container).cancelLeave('lv_002'), isFalse);
      expect(byId(store, 'lv_002').status, LeaveStatus.approved);
    });
  });

  group('deciding', () {
    test('the office approves, and is named on the decision', () async {
      final container = await signedInAs(UserRole.admin);
      final store = container.read(demoStoreProvider);

      final ok = await actions(container).decideLeave(
        requestId: 'lv_001',
        approved: true,
        remarks: 'Enjoy it.',
      );

      expect(ok, isTrue);
      final decided = byId(store, 'lv_001');
      expect(decided.status, LeaveStatus.approved);
      // The account that decided, not whatever a client claimed.
      expect(decided.decidedByUid, 'u_admin');
      expect(decided.decidedByRole, 'admin');
      expect(decided.decidedAt, isNotNull);
      expect(decided.decisionRemarks, 'Enjoy it.');
    });

    test('and tells the employee', () async {
      final container = await signedInAs(UserRole.admin);
      final store = container.read(demoStoreProvider);
      final before = (store.notifications.value['u_staff'] ?? const []).length;

      await actions(container).decideLeave(requestId: 'lv_001', approved: false);

      final inbox = store.notifications.value['u_staff'] ?? const [];
      expect(inbox.length, before + 1);
      expect(inbox.first.kind, NotificationKind.approval);
      expect(inbox.first.body, contains('declined'));
      // Somebody who filed for Thursday and never heard back either
      // comes in when they should not have, or stays away when they
      // were expected.
      expect(inbox.first.link, '/my-leave');
    });

    test('a teacher cannot decide anybody\'s, including their own', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);

      expect(
        await actions(container).decideLeave(requestId: 'lv_001', approved: true),
        isFalse,
      );
      expect(byId(store, 'lv_001').status, LeaveStatus.pending);
    });

    test('an already-decided request is not decided twice', () async {
      final container = await signedInAs(UserRole.director);
      final store = container.read(demoStoreProvider);

      expect(
        await actions(container).decideLeave(requestId: 'lv_002', approved: false),
        isFalse,
      );
      // Still approved, still stamped with whoever approved it first.
      expect(byId(store, 'lv_002').status, LeaveStatus.approved);
      expect(byId(store, 'lv_002').decidedByRole, 'admin');
    });
  });

  group('the timesheet', () {
    /// Maria Santos, over the month her approved sick leave falls in.
    Future<Timesheet> mariasMonth(ProviderContainer container) async {
      final leaveStart = DateTime.parse(
        container
            .read(demoStoreProvider)
            .leaveRequests
            .value
            .firstWhere((r) => r.id == 'lv_002')
            .fromDate,
      );
      final query = TimesheetQuery(
        employeeUid: 'u_faculty',
        employeeName: 'Maria Santos',
        month: leaveStart,
      );
      // Both halves are streams; hold them until they have emitted.
      final sub = container.listen(timesheetProvider(query), (_, __) {});
      addTearDown(sub.close);
      for (var i = 0; i < 20 && container.read(timesheetProvider(query)) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final sheet = container.read(timesheetProvider(query));
      expect(sheet, isNotNull, reason: 'the timesheet never loaded');
      return sheet!;
    }

    test('reads an approved absence as leave rather than absence', () async {
      final container = await signedInAs(UserRole.admin);
      final sheet = await mariasMonth(container);

      // The pairing the whole feature turns on. Without the leave
      // record these days are three unexplained absences on a payroll
      // sheet; with it they are leave the office itself granted.
      expect(sheet.daysOnLeave, greaterThan(0));
      final leaveDays =
          sheet.days.where((d) => d.kind == WorkDayKind.onLeave).toList();
      expect(leaveDays.every((d) => d.leave?.type == LeaveType.sick), isTrue);
    });

    test('never counts a weekend as absence', () async {
      final container = await signedInAs(UserRole.admin);
      final sheet = await mariasMonth(container);

      final weekend = sheet.days.where((d) => d.kind == WorkDayKind.restDay);
      expect(weekend, isNotEmpty);
      expect(
        weekend.every((d) {
          final date = DateTime.parse(d.date);
          return date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday;
        }),
        isTrue,
      );
    });

    test('adds up the days somebody was actually at work', () async {
      final container = await signedInAs(UserRole.admin);
      final sheet = await mariasMonth(container);

      expect(sheet.daysWorked, greaterThan(0));
      expect(sheet.minutesWorked, greaterThan(0));
      // Every day is accounted for as exactly one thing.
      expect(
        sheet.daysWorked + sheet.daysOnLeave + sheet.daysAbsent +
            (sheet.days.length - sheet.workingDays),
        sheet.days.length,
      );
    });
  });
}

/// The next [weekday] on or after [from].
DateTime _nextWeekday(DateTime from, int weekday) {
  var day = DateTime(from.year, from.month, from.day);
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return day;
}
