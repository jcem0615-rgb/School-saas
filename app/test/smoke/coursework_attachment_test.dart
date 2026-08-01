import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/core/errors/result.dart';
import 'package:school_saas/core/storage/upload_providers.dart';
import 'package:school_saas/core/storage/upload_repository.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/faculty_portal/domain/entities/coursework_item.dart';
import 'package:school_saas/features/faculty_portal/presentation/controllers/faculty_controller.dart';
import 'package:school_saas/features/student_portal/presentation/controllers/student_controller.dart';

/// The attachment flow cannot be clicked through in a headless browser --
/// it opens an OS file dialog -- so this drives the same path the picker
/// feeds: upload bytes, attach the result to a coursework item, and check a
/// student can actually reach the file. That last hop is the point of the
/// feature and the easiest part to get wrong.
void main() {
  /// One container per test, not one per role: demoStoreProvider is scoped
  /// to a container, so two containers are two separate schools and a
  /// teacher's upload would be invisible to "the student". Switching the
  /// signed-in user inside one container is what the demo switcher does
  /// and what actually exercises the hand-off.
  Future<ProviderContainer> freshContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    return container;
  }

  Future<void> signIn(ProviderContainer container, UserRole role) async {
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    // Let the auth stream settle before anything reads a repository -- the
    // demo repositories watch authStateProvider and rebuild on its first
    // emission, which would otherwise dispose whatever was just read.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  test('an uploaded file reaches the student who has to read it', () async {
    final container = await freshContainer();
    await signIn(container, UserRole.faculty);
    final sub = container.listen(facultyActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 pretend worksheet'));
    final upload = await container.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.coursework,
          fileName: 'worksheet.pdf',
          bytes: bytes,
          contentType: 'application/pdf',
        );

    final attachment = switch (upload) {
      Success<UploadedFile>(:final value) => value,
      Error<UploadedFile>(:final failure) => fail('upload failed: ${failure.message}'),
    };
    expect(attachment.fileName, 'worksheet.pdf');
    expect(attachment.sizeBytes, bytes.lengthInBytes);

    final posted = await container.read(facultyActionControllerProvider.notifier).createCourseworkItem(
          type: CourseworkType.assignment,
          title: 'Worksheet 5',
          description: 'See the attached file.',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          // Gradable types require a due date -- CreateCourseworkItemUseCase
          // rejects an assignment without one.
          dueDate: DateTime.now().add(const Duration(days: 7)),
          totalPoints: 20,
          attachmentUrl: attachment.url,
          attachmentName: attachment.fileName,
        );
    expect(posted, isTrue);

    // The student side reads from the same store, filtered to published
    // items in their section -- this is the hop that makes the attachment
    // useful rather than merely stored.
    await signIn(container, UserRole.student);
    final visible = await container
        .read(studentRepositoryProvider)
        .watchMyCoursework('Grade 10 - Rizal')
        .first;

    final item = visible.firstWhere((c) => c.title == 'Worksheet 5');
    expect(item.attachmentName, 'worksheet.pdf');
    expect(item.attachmentUrl, isNotNull);
    expect(
      item.attachmentUrl,
      startsWith('data:application/pdf;base64,'),
      reason: 'demo mode serves the file inline rather than from Storage',
    );
  });

  test('an oversized attachment is rejected before it is stored', () async {
    final container = await freshContainer();
    await signIn(container, UserRole.faculty);

    // storage.rules caps uploads at 10MB; the client checks the same bound
    // so the failure is a clear message rather than a permission error
    // after the bytes have gone over the wire.
    final tooBig = Uint8List(10 * 1024 * 1024 + 1);
    final result = await container.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.coursework,
          fileName: 'huge.pdf',
          bytes: tooBig,
          contentType: 'application/pdf',
        );

    expect(result, isA<Error<dynamic>>());
  });

  test('an unpublished item stays hidden from students', () async {
    final container = await freshContainer();
    await signIn(container, UserRole.faculty);
    final sub = container.listen(facultyActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    await container.read(facultyActionControllerProvider.notifier).createCourseworkItem(
          type: CourseworkType.lessonPlan,
          title: 'Draft plan, not for students',
          description: 'Working notes.',
          subject: 'Mathematics',
          section: 'Grade 10 - Rizal',
          published: false,
        );

    await signIn(container, UserRole.student);
    final visible = await container
        .read(studentRepositoryProvider)
        .watchMyCoursework('Grade 10 - Rizal')
        .first;

    expect(
      visible.where((c) => c.title == 'Draft plan, not for students'),
      isEmpty,
      reason: 'an unpublished draft is the teacher\'s working copy',
    );
  });
}
