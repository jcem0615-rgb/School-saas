import '../../../../core/errors/result.dart';
import '../entities/school_totals.dart';

abstract class SchoolTotalsRepository {
  /// The head count, and the money when the reader is allowed it.
  ///
  /// A one-shot read rather than a stream. Every figure here is an
  /// aggregate over the whole school, and a card whose numbers twitch
  /// while somebody is reading them is not more useful for being live --
  /// it is the dashboard equivalent of a table that reshuffles mid-column.
  /// Pulling to refresh is how a newer one is asked for.
  Future<Result<SchoolTotals>> fetch();
}
