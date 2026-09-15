import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/storage/uploaded_image.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/admin_portal/presentation/controllers/admin_controller.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/branding_screen.dart';

/// The school's printed identity: the logo and the two signatures that go
/// on every ID card, report card and TOR.
void main() {
  ProviderContainer asAdmin() {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    c.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.admin),
        );
    return c;
  }

  /// Writes branding into the store with no round trip to wait on.
  void seedLogo(ProviderContainer c, String logoUrl, {String? principalSignature}) {
    final store = c.read(demoStoreProvider);
    final current = store.branding.value;
    store.branding.add(SchoolBranding(
      schoolName: current.schoolName,
      addressLine: current.addressLine,
      logoUrl: logoUrl,
      logoFileName: 'seeded.png',
      principalName: current.principalName,
      principalSignatureUrl: principalSignature ?? current.principalSignatureUrl,
      directorName: current.directorName,
      directorSignatureUrl: current.directorSignatureUrl,
      schoolYear: current.schoolYear,
      updatedAt: current.updatedAt,
      updatedByName: current.updatedByName,
    ));
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: BrandingScreen()),
    ));
    await tester.pumpAndSettle();
  }

  group('an upload can be taken back', () {
    testWidgets('the logo offers Remove once there is one', (tester) async {
      // Upload existed; remove did not. A school that put up the wrong
      // file -- last year's logo, the wrong school's -- had it on every
      // printed document with replacing it the only way out and no way
      // back to none at all.
      final c = asAdmin();
      // Seeded straight into the store: `updateBranding` sleeps to
      // imitate a round trip, and an await on the real clock inside
      // testWidgets never returns while the widget clock stands still.
      seedLogo(c, 'data:image/png;base64,iVBORw0KGgo=');
      await pump(tester, c);

      expect(find.widgetWithText(TextButton, 'Remove'), findsWidgets);
    });

    test('and removing it clears what the documents print', () async {
      final c = asAdmin();
      final notifier = c.read(adminActionControllerProvider.notifier);
      await notifier.updateBranding(
        logoUrl: 'data:image/png;base64,iVBORw0KGgo=',
        logoFileName: 'wrong-logo.png',
      );
      // The clear itself, at the layer the screen calls. Null already
      // means "leave this one alone" on every field -- that is what lets
      // renaming the school keep the logo -- so the empty string is what
      // says "remove it".
      await notifier.updateBranding(logoUrl: '', logoFileName: '');

      final branding = c.read(demoStoreProvider).branding.value;
      expect(branding.logoUrl, isEmpty);
      expect(branding.hasLogo, isFalse);
    });

    test('clearing one signature leaves the other alone', () async {
      // The most likely mistake on this screen is uploading a signature
      // into the wrong one of the two slots, so undoing it must not take
      // the good one with it.
      final c = asAdmin();
      final notifier = c.read(adminActionControllerProvider.notifier);
      await notifier.updateBranding(
        principalSignatureUrl: 'data:image/png;base64,cHJpbmNpcGFs',
      );
      await notifier.updateBranding(
        directorSignatureUrl: 'data:image/png;base64,ZGlyZWN0b3I=',
      );

      await notifier.updateBranding(principalSignatureUrl: '');

      final branding = c.read(demoStoreProvider).branding.value;
      expect(branding.principalSignatureUrl, isEmpty);
      expect(branding.directorSignatureUrl, 'data:image/png;base64,ZGlyZWN0b3I=');
    });

    test('renaming the school still leaves the logo alone', () async {
      // The property the null-means-leave-alone rule exists for, kept
      // here so adding the empty-string clear cannot have broken it.
      final c = asAdmin();
      final notifier = c.read(adminActionControllerProvider.notifier);
      await notifier.updateBranding(logoUrl: 'data:image/png;base64,iVBORw0KGgo=');
      await notifier.updateBranding(schoolName: 'Renamed Academy');

      final branding = c.read(demoStoreProvider).branding.value;
      expect(branding.schoolName, 'Renamed Academy');
      expect(branding.logoUrl, 'data:image/png;base64,iVBORw0KGgo=');
    });
  });

  testWidgets('the logo and signatures render on a phone, not only a browser',
      (tester) async {
    // An upload is a Storage URL in a real deployment and a data: URI in
    // demo mode. `Image.network` cannot fetch the second one outside a
    // browser, so these were blank in the APK and the desktop build --
    // the same defect UploadedImage was written for and then used in one
    // place only.
    final c = asAdmin();
    seedLogo(c, 'data:image/png;base64,iVBORw0KGgo=',
        principalSignature: 'data:image/png;base64,cHJpbmNpcGFs');
    await pump(tester, c);

    expect(find.byType(UploadedImage), findsWidgets);
    expect(find.byType(Image), findsWidgets,
        reason: 'UploadedImage decodes to an Image, network or memory');
  });
}
