import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/demo/demo_overrides.dart';
import 'package:school_saas/demo/demo_store.dart';
import 'package:school_saas/features/qr_attendance/presentation/screens/e_id_screen.dart';

/// A student ID card is only useful if it carries the details a guard or a
/// teacher actually checks it for. Those come from three different places
/// -- the account, the registrar's student record, and the school's
/// branding -- so a card that renders without throwing can still be
/// missing half of them. These assert the fields are on the card.
void main() {
  Future<void> pumpEId(WidgetTester tester, UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);

    container
        .read(demoAuthRepositoryProvider)
        .signInAs(DemoStore.demoAccounts.firstWhere((a) => a.role == role));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EIdScreen()),
      ),
    );
    // The demo repositories add a small latency and re-subscribe on the
    // auth emission, so the screen's first frame has neither the account
    // nor the student record yet. Time only moves here when the tester
    // pumps it -- a bare Future.delayed would hang on the fake clock.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('a student ID carries name, year, section and school year', (tester) async {
    await pumpEId(tester, UserRole.student);

    final year = DateTime.now().year;
    expect(find.text('Miguel Torres'), findsOneWidget);
    // Said once: classLabel collapses "Grade 10" and "Grade 10 - Rizal",
    // which on an 85.6mm card is the difference between fitting on the
    // line and being ellipsised.
    expect(find.text('Student · Grade 10 - Rizal'), findsOneWidget,
        reason: 'role and class, on the front under the name');
    expect(find.text('SY $year-${year + 1}'), findsOneWidget, reason: 'school year, in the header');
    expect(find.text('2024-00001'), findsOneWidget, reason: 'student number row');
  });

  testWidgets('the two faces do not repeat each other', (tester) async {
    // The back used to reprint the name, year, section and school year
    // that are already on the face of the card. That cost the space the
    // photo and QR now use and told a reader nothing new.
    await pumpEId(tester, UserRole.student);

    for (final repeated in ['Miguel Torres', 'Student · Grade 10 - Rizal']) {
      expect(find.text(repeated), findsOneWidget, reason: '$repeated belongs on one face only');
    }
    expect(find.text('Grade Level'), findsNothing);
    expect(find.text('Section'), findsNothing);
    expect(find.text('School Year'), findsNothing);
  });

  testWidgets('a student ID carries the birthday and emergency contact', (tester) async {
    await pumpEId(tester, UserRole.student);

    final birthday = DateFormat.yMMMd().format(DateTime(DateTime.now().year - 16, 3, 14));
    expect(find.text(birthday), findsOneWidget);
    expect(
      find.textContaining('Rosario Torres'),
      findsOneWidget,
      reason: 'the guardian on the record is the emergency contact',
    );
    expect(find.textContaining('0917 555 0142'), findsOneWidget);
  });

  testWidgets('a student ID names the principal and the director', (tester) async {
    await pumpEId(tester, UserRole.student);

    expect(find.text('Ramon Salazar'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget);
    expect(find.text('Corazon Buenaventura'), findsOneWidget);
    expect(find.text('Director'), findsOneWidget);
  });

  testWidgets('the card stays card-sized on a wide window', (tester) async {
    // The card is laid out at the 85.6:54 proportions of a real CR80 card,
    // so anything that lets it take the full width of a desktop window
    // also makes it proportionally that tall -- it filled the screen and
    // pushed the second face out of view. Cap enforced here because it
    // only shows up above phone width.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpEId(tester, UserRole.student);

    final card = tester.getSize(find.byType(AspectRatio).first);
    expect(card.width, lessThanOrEqualTo(420));
  });

  testWidgets('the photo and the QR get the space on the front', (tester) async {
    // These are the two things a card is actually checked with -- a guard
    // compares the face, a scanner reads the code -- so they are sized in
    // card-millimetres against the print layout rather than in fixed
    // pixels that shrink relative to the card.
    await pumpEId(tester, UserRole.student);

    final front = tester.getSize(find.byType(AspectRatio).first);
    final qr = tester.getSize(find.byType(QrImageView).first);

    // Stated as floors rather than exact ratios so tuning the millimetres
    // does not fail the test -- what matters is that neither shrinks back
    // to the postage stamp they were.
    expect(qr.width / front.width, greaterThan(0.28));
    expect(qr.height / front.height, greaterThan(0.45));

    // The name spans the full width beneath them rather than sharing a
    // row: squeezed into the leftover ~22mm column it wrapped onto two
    // lines, which is what forced this layout.
    final name = tester.getSize(find.text('Miguel Torres'));
    expect(name.width, greaterThan(qr.width));
  });

  testWidgets('an employee ID still renders, without the student-only rows', (tester) async {
    // Faculty have no registrar record to read. The card must fall back to
    // the account rather than throwing or blocking on a lookup that will
    // never resolve.
    await pumpEId(tester, UserRole.faculty);

    expect(tester.takeException(), isNull);
    expect(find.text('Grade Level'), findsNothing);
    expect(find.text('Emergency Contact'), findsNothing);
    // School-wide details are not student-only, so they stay.
    expect(find.text('Ramon Salazar'), findsOneWidget);
  });
}
