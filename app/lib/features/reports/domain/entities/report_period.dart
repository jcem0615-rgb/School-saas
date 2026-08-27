import 'package:intl/intl.dart';

final _dayFormat = DateFormat('d MMM y');

/// The stretch of time a report covers.
///
/// Inclusive at both ends, which is not the usual half-open convention
/// and is deliberate: a registrar asked for "June to August" means
/// through the last day of August, and a report that quietly stopped on
/// the 30th would be wrong in a way nobody would catch until the totals
/// were compared against a bank statement.
class ReportPeriod {
  final DateTime start;
  final DateTime end;

  ReportPeriod(DateTime start, DateTime end)
      : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

  /// The current school year as Philippine schools run it: June through
  /// March. Asked for in January, that means the year that began last
  /// June, not the one that starts in five months.
  factory ReportPeriod.schoolYearOf(DateTime day) {
    final startYear = day.month >= 6 ? day.year : day.year - 1;
    return ReportPeriod(DateTime(startYear, 6, 1), DateTime(startYear + 1, 3, 31));
  }

  factory ReportPeriod.monthOf(DateTime day) =>
      ReportPeriod(DateTime(day.year, day.month, 1), DateTime(day.year, day.month + 1, 0));

  factory ReportPeriod.lastDays(int days, {DateTime? endingOn}) {
    final end = endingOn ?? DateTime.now();
    return ReportPeriod(end.subtract(Duration(days: days - 1)), end);
  }

  bool contains(DateTime moment) => !moment.isBefore(start) && !moment.isAfter(end);

  String get label => '${_dayFormat.format(start)} - ${_dayFormat.format(end)}';

  /// Whole days covered, both ends included.
  int get dayCount => end.difference(start).inDays + 1;

  ReportPeriod copyWith({DateTime? start, DateTime? end}) =>
      ReportPeriod(start ?? this.start, end ?? this.end);
}
