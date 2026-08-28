import '../entities/system_check.dart';

abstract class SystemCheckRepository {
  /// Runs every check and reports what it found.
  ///
  /// Nothing here changes the school's data. The probes are built to be
  /// safe by construction rather than by cleanup: a callable is called
  /// with arguments it must reject before it writes anything, and the
  /// rules probe attempts a write the rules must refuse. The one thing
  /// that does write -- the storage probe -- writes a few bytes to a
  /// dedicated path and removes them.
  Future<SystemCheckReport> run();
}
