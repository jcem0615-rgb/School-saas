import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../admin_portal/presentation/controllers/admin_controller.dart'
    show employeesStreamProvider;
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../domain/entities/timesheet.dart';
import '../controllers/timekeeping_controller.dart';

final _monthFormat = DateFormat('MMMM y');
final _dayFormat = DateFormat('EEE d');
final _clock = DateFormat('h:mm a');

/// What an employee's month came to.
///
/// Built from the gate scans the admin already takes with the QR
/// scanner, plus approved leave, which is the piece that turns a blank
/// day from "absent" into "away, and the office said so". Payroll is not
/// run here -- this is the sheet a payroll clerk reads before they run
/// it somewhere else.
class TimesheetScreen extends ConsumerStatefulWidget {
  /// Fixed to one person when an employee is looking at their own. Null
  /// gives the picker, for the office.
  final String? employeeUid;
  final String? employeeName;

  const TimesheetScreen({super.key, this.employeeUid, this.employeeName});

  @override
  ConsumerState<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends ConsumerState<TimesheetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _pickedUid;
  String? _pickedName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixed = widget.employeeUid != null;
    final uid = widget.employeeUid ?? _pickedUid;
    final name = widget.employeeName ?? _pickedName ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(fixed ? 'My timesheet' : 'Timesheets')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                if (!fixed) _EmployeePicker(
                  selected: _pickedUid,
                  onChanged: (uid, name) => setState(() {
                    _pickedUid = uid;
                    _pickedName = name;
                  }),
                ),
                if (!fixed) const SizedBox(height: 8),
                _MonthPicker(
                  month: _month,
                  onChanged: (month) => setState(() => _month = month),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: uid == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Choose an employee to see their month.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : _Sheet(
                    query: TimesheetQuery(
                      employeeUid: uid,
                      employeeName: name,
                      month: _month,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmployeePicker extends ConsumerWidget {
  final String? selected;
  final void Function(String uid, String name) onChanged;

  const _EmployeePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesStreamProvider).valueOrNull ?? const [];

    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Employee',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final employee in employees)
          DropdownMenuItem(
            value: employee.uid,
            child: Text(
              '${employee.firstName} ${employee.lastName} · ${employee.role.displayName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (uid) {
        if (uid == null) return;
        final match = employees.where((e) => e.uid == uid).firstOrNull;
        onChanged(uid, match == null ? '' : '${match.firstName} ${match.lastName}');
      },
    );
  }
}

class _MonthPicker extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  const _MonthPicker({required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
    final atLatest = !month.isBefore(thisMonth);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Text(
          _monthFormat.format(month),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          // Nothing to see in the future: there are no scans yet, and a
          // sheet of thirty absences for a month that has not happened
          // is a screen that looks broken.
          onPressed: atLatest
              ? null
              : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

class _Sheet extends ConsumerWidget {
  final TimesheetQuery query;
  const _Sheet({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheet = ref.watch(timesheetProvider(query));
    // Null means one half is still loading. A sheet drawn from half the
    // data says everybody was absent all month, which looks exactly like
    // a damning one rather than an incomplete one.
    if (sheet == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      children: [
        _Totals(sheet: sheet),
        const Divider(height: 1),
        for (final day in sheet.days) _DayRow(day: day),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  final Timesheet sheet;
  const _Totals({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _Figure(label: 'Days worked', value: '${sheet.daysWorked}'),
              _Figure(label: 'Hours', value: sheet.hoursWorkedLabel),
              _Figure(label: 'Late', value: '${sheet.daysLate}'),
              _Figure(label: 'On leave', value: '${sheet.daysOnLeave}'),
              _Figure(
                label: 'Absent',
                value: '${sheet.daysAbsent}',
                alarming: sheet.daysAbsent > 0,
              ),
            ],
          ),
          if (sheet.daysMissingTimeOut > 0) ...[
            const SizedBox(height: 10),
            Text(
              // The hours total is incomplete, and a payroll clerk has to
              // know that before they use it. Guessing the missing end
              // of a day would put invented hours on a payslip.
              sheet.daysMissingTimeOut == 1
                  ? '1 day has a time in and no time out, so its hours are not counted.'
                  : '${sheet.daysMissingTimeOut} days have a time in and no time out, '
                      'so their hours are not counted.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final bool alarming;

  const _Figure({required this.label, required this.value, this.alarming = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: alarming ? theme.colorScheme.error : theme.colorScheme.onSurface,
          ),
        ),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final TimesheetDay day;
  const _DayRow({required this.day});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.tryParse(day.date);
    final (label, colour) = switch (day.kind) {
      WorkDayKind.worked => ('Worked', theme.colorScheme.primary),
      WorkDayKind.late => ('Late', theme.colorScheme.tertiary),
      WorkDayKind.onLeave => (
          day.leave?.type.displayLabel ?? 'On leave',
          theme.colorScheme.secondary
        ),
      WorkDayKind.absent => ('Absent', theme.colorScheme.error),
      WorkDayKind.restDay => ('Rest day', theme.colorScheme.outline),
    };

    return ListTile(
      dense: true,
      // Rest days are dimmed rather than hidden. A month with gaps in it
      // reads as missing data; a month that shows its weekends reads as
      // a month.
      tileColor: day.kind == WorkDayKind.restDay
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
          : null,
      title: Text(
        date == null ? day.date : _dayFormat.format(date),
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: day.timeIn == null
          ? null
          : Text(
              day.timeOut == null
                  ? 'In ${_clock.format(day.timeIn!)} · no time out'
                  : '${_clock.format(day.timeIn!)} - ${_clock.format(day.timeOut!)}'
                      '${day.minutes == null ? '' : ' · ${_hours(day.minutes!)}'}',
              style: theme.textTheme.bodySmall,
            ),
      trailing: Text(
        label,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: colour, fontWeight: FontWeight.w700),
      ),
    );
  }

  static String _hours(int minutes) =>
      '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// The signed-in employee's own month, with no picker.
class MyTimesheetScreen extends ConsumerWidget {
  const MyTimesheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return TimesheetScreen(employeeUid: user.uid, employeeName: user.fullName);
  }
}
