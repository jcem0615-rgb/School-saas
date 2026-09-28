import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/messaging_repository.dart';
import '../datasources/messaging_remote_datasource.dart';

class MessagingRepositoryImpl implements MessagingRepository {
  final MessagingRemoteDataSource _remote;
  const MessagingRepositoryImpl(this._remote);

  @override
  Stream<List<Conversation>> watchMyConversations() =>
      _remote.watchMyConversations();

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      _remote.watchMessages(conversationId);

  @override
  Future<Result<String>> startConversation({
    required String studentId,
    required String otherUid,
  }) async {
    try {
      return Success(await _remote.startConversation(
        studentId: studentId,
        otherUid: otherUid,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> send({
    required String conversationId,
    required String text,
  }) =>
      _run(() => _remote.send(conversationId: conversationId, text: text));

  @override
  Future<Result<void>> markRead(String conversationId) =>
      _run(() => _remote.markRead(conversationId));

  @override
  Future<Result<List<String>>> mySections() => _read(_remote.mySections);

  @override
  Future<Result<List<MessageablePerson>>> studentsInSection(String section) =>
      _read(() => _remote.studentsInSection(section));

  @override
  Future<Result<List<MessageableGuardian>>> parentsForStudent(String studentId) =>
      _read(() => _remote.parentsForStudent(studentId));

  @override
  Future<Result<List<TeacherAssignment>>> teachersForSection(String section) =>
      _read(() => _remote.teachersForSection(section));

  Future<Result<T>> _read<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}

/// Used when nobody is signed in, so the messages tile and its badge do
/// not blow up in the frame between signing out and the router landing
/// on the login screen.
class SignedOutMessagingRepository implements MessagingRepository {
  const SignedOutMessagingRepository();

  @override
  Stream<List<Conversation>> watchMyConversations() => const Stream.empty();

  @override
  Stream<List<Message>> watchMessages(String conversationId) => const Stream.empty();

  @override
  Future<Result<String>> startConversation({
    required String studentId,
    required String otherUid,
  }) async =>
      const Error(UnknownFailure());

  @override
  Future<Result<void>> send({
    required String conversationId,
    required String text,
  }) async =>
      const Error(UnknownFailure());

  @override
  Future<Result<void>> markRead(String conversationId) async => const Success(null);

  // Nobody to write to when nobody is signed in. Empty rather than an
  // error: the sheet says "no classes yet", which is true, instead of
  // showing a failure in the frame before the router reaches login.
  @override
  Future<Result<List<String>>> mySections() async => const Success([]);

  @override
  Future<Result<List<MessageablePerson>>> studentsInSection(String section) async =>
      const Success([]);

  @override
  Future<Result<List<MessageableGuardian>>> parentsForStudent(String studentId) async =>
      const Success([]);

  @override
  Future<Result<List<TeacherAssignment>>> teachersForSection(String section) async =>
      const Success([]);
}
