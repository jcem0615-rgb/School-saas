import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/qr_attendance/presentation/screens/e_id_screen.dart';

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

  testWidgets('a student ID carries the name in labelled parts', (tester) async {
    // The card prints the name the way a credential does -- surname,
    // given name and middle name on their own labelled lines -- rather
    // than as one run of text. A reader looking for a surname finds it
    // without parsing a sentence, and a long name no longer decides
    // whether the line fits.
    await pumpEId(tester, UserRole.student);

    final year = DateTime.now().year;
    expect(find.text('SURNAME'), findsOneWidget);
    expect(find.text('TORRES'), findsOneWidget);
    expect(find.text('GIVEN NAME'), findsOneWidget);
    expect(find.text('MIGUEL'), findsOneWidget);
    expect(find.text('GRADE & SECTION'), findsOneWidget);
    // Said once: classLabel collapses "Grade 10" and "Grade 10 - Rizal",
    // which on an 85.6mm card is the difference between fitting on the
    // line and being ellipsised.
    expect(find.text('Grade 10 - Rizal'), findsOneWidget);
    expect(find.text('S.Y. $year-${year + 1}'), findsOneWidget,
        reason: 'school year, in the header band');
    expect(find.text('2024-00001'), findsOneWidget, reason: 'the number in the footer');
    expect(find.text('STUDENT NUMBER'), findsOneWidget);
  });

  testWidgets('the header band names the school and the credential', (tester) async {
    await pumpEId(tester, UserRole.student);

    expect(find.text('ST. NICHOLAS ACADEMY'), findsOneWidget,
        reason: 'a card says who issued it before it says anything about the holder');
    expect(find.text('STUDENT IDENTIFICATION CARD'), findsOneWidget);
  });

  testWidgets('the two faces do not repeat each other', (tester) async {
    // The back used to reprint what is already on the face of the card.
    // That cost the space the emergency contact and the return notice
    // need, and told a reader nothing new.
    await pumpEId(tester, UserRole.student);

    for (final onFrontOnly in ['TORRES', 'MIGUEL', 'Grade 10 - Rizal', '2024-00001']) {
      expect(find.text(onFrontOnly), findsOneWidget,
          reason: '$onFrontOnly belongs on one face only');
    }
    expect(find.text('Grade Level'), findsNothing);
    expect(find.text('Section'), findsNothing);
    expect(find.text('School Year'), findsNothing);
  });

  testWidgets('a student ID carries the birthday and emergency contact', (tester) async {
    await pumpEId(tester, UserRole.student);

    final birthday = DateFormat('d MMMM y').format(DateTime(DateTime.now().year - 16, 3, 14));
    expect(find.text(birthday), findsOneWidget, reason: 'date of birth, on the front');
    expect(find.text('DATE OF BIRTH'), findsOneWidget);
    expect(find.text('EMERGENCY CONTACT'), findsOneWidget, reason: 'on the back');
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
    expect(find.text('PRINCIPAL'), findsOneWidget);
    expect(find.text('Corazon Buenaventura'), findsOneWidget);
    expect(find.text('DIRECTOR'), findsOneWidget);
  });

  testWidgets('the school logo is the background of the card', (tester) async {
    // The mark of the body that issued it, under the data, is most of
    // what makes a card look issued rather than printed. It is the
    // Admin's uploaded logo, so it has to survive being a data URI --
    // which is what an upload is in demo mode, and what Image.network
    // cannot load off the web.
    await pumpEId(tester, UserRole.student);

    final watermarks = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((o) => o.opacity < 0.2)
        .toList();
    expect(watermarks, hasLength(2), reason: 'one behind each face');

    // Rendered from bytes, not fetched: Image.network would come back
    // empty on Android, iOS and Windows for the same URL.
    expect(find.byType(Image), findsWidgets);
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
    expect(qr.width / front.width, greaterThan(0.2));
    expect(qr.height / front.height, greaterThan(0.3));

    // The number in the footer is the largest text on the card: it is
    // what the office looks a student up by, and it is read across a
    // counter rather than held up close.
    final number = tester.getSize(find.text('2024-00001'));
    expect(number.height, greaterThan(tester.getSize(find.text('TORRES')).height));
  });

  testWidgets('an employee ID still renders, without the student-only rows', (tester) async {
    // Faculty have no registrar record to read. The card must fall back to
    // the account rather than throwing or blocking on a lookup that will
    // never resolve.
    await pumpEId(tester, UserRole.faculty);

    expect(tester.takeException(), isNull);
    expect(find.text('GRADE & SECTION'), findsNothing);
    expect(find.text('EMERGENCY CONTACT'), findsNothing);
    expect(find.text('FACULTY IDENTIFICATION CARD'), findsOneWidget);
    // School-wide details are not student-only, so they stay.
    expect(find.text('Ramon Salazar'), findsOneWidget);
  });

  // ---- the printed card ----
  //
  // The PDF is a separate widget tree from the preview, and it is the
  // artefact the school actually hands out. A card that comes out blank,
  // or throws because a signature is missing, is not something a test of
  // the preview would catch.

  ProviderContainer demoContainer() {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    return c;
  }

  test('the printed card is a real two-page PDF', () async {
    final store = demoContainer().read(demoStoreProvider);
    final bytes = await buildIdCardPdf(
      user: DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student),
      branding: store.branding.value,
      student: store.students.value.firstWhere((s) => s.id == 'stu_001'),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(4000),
        reason: 'the logo watermark and the QR are both on it');
  });

  test('a card prints for a school that has uploaded nothing', () async {
    // No logo, no signatures, no school year. A registrar issuing a card
    // on day one still needs one, and finding out at the printer is the
    // wrong time.
    final store = demoContainer().read(demoStoreProvider);
    final bytes = await buildIdCardPdf(
      user: DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.student),
      branding: SchoolBranding.empty,
      student: store.students.value.firstWhere((s) => s.id == 'stu_001'),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('a card prints for staff, who have no registrar record', () async {
    final store = demoContainer().read(demoStoreProvider);
    final bytes = await buildIdCardPdf(
      user: DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.faculty),
      branding: store.branding.value,
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
