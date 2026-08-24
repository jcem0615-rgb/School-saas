import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/demo/demo_attachments.dart';
import 'package:logicclass/demo/demo_store.dart';

/// The demo's attachments have to be real files, because a student
/// tapping the only piece of material on the screen and getting nothing
/// reads as a broken app rather than as a demo with no bucket behind it.
void main() {
  Uint8List? decode(String uri) {
    final comma = uri.indexOf(',');
    if (comma < 0) return null;
    return base64Decode(uri.substring(comma + 1));
  }

  group('demo coursework attachments', () {
    test('every one is a data URI, since demo mode has no Storage', () {
      for (final uri in [
        DemoAttachments.problemSet4,
        DemoAttachments.quiz3CellDivision,
        DemoAttachments.floranteAtLaura,
      ]) {
        expect(uri.startsWith('data:application/pdf;base64,'), isTrue);
      }
    });

    test('and each decodes to an actual PDF', () {
      for (final uri in [
        DemoAttachments.problemSet4,
        DemoAttachments.quiz3CellDivision,
        DemoAttachments.floranteAtLaura,
      ]) {
        final bytes = decode(uri)!;
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-',
            reason: 'a header a PDF reader will accept');
        expect(String.fromCharCodes(bytes.skip(bytes.length - 8)), contains('%%EOF'),
            reason: 'and a complete file, not a truncated one');
      }
    });

    test('no seeded attachment points at a host that does not exist', () {
      // The bug this replaces: a plausible https://example.org/... link
      // that failed on tap, which is worse than no attachment at all.
      final external = DemoStore()
        ..dispose();
      for (final item in external.coursework.value) {
        final url = item.attachmentUrl;
        if (url == null) continue;
        expect(url.startsWith('data:'), isTrue,
            reason: '${item.title} points at $url, which nothing can open offline');
      }
    });

    test('the material a student is asked to work from is attached', () {
      final store = DemoStore();
      addTearDown(store.dispose);

      final withFiles = store.coursework.value.where((c) => c.attachmentUrl != null);
      expect(withFiles.length, greaterThanOrEqualTo(3),
          reason: 'one attachment across the whole feed left every other '
              'item with nothing to open');
    });
  });
}
