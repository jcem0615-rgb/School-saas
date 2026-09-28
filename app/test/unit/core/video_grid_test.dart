import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/meeting_room.dart';
import 'package:logicclass/core/meeting/webrtc/video_grid.dart';

/// How a class is laid out on screen.
///
/// Pure, because a class of sixty is not something anybody will check by
/// eye, and because the failure -- faces too small to recognise -- is
/// the one thing a lesson on camera cannot afford.
void main() {
  _wording();
  _heading();
  group('the grid', () {
    test('gives one person the whole screen', () {
      expect(gridColumnsFor(tiles: 1, width: 1280), 1);
    });

    test('keeps faces recognisable rather than filling the width', () {
      // A phone must not try to put six across. Below about 180px a
      // person stops being identifiable, which defeats the point of a
      // class being on camera at all.
      expect(gridColumnsFor(tiles: 60, width: 360), lessThanOrEqualTo(2));
      expect(gridColumnsFor(tiles: 60, width: 1280), greaterThan(2));
    });

    test('stays roughly square instead of one long row', () {
      // Six across and two down wastes half a screen and crushes the
      // faces into strips.
      expect(gridColumnsFor(tiles: 4, width: 1280), 3);
      expect(gridColumnsFor(tiles: 2, width: 1280), 2);
    });

    test('never asks for zero or a negative number of columns', () {
      // A GridView with zero columns throws, and it would throw inside
      // a live lesson.
      for (final tiles in const [0, 1, 2, 7, 30, 60, 100]) {
        for (final width in const [200.0, 360.0, 800.0, 1920.0]) {
          expect(gridColumnsFor(tiles: tiles, width: width),
              greaterThanOrEqualTo(1));
        }
      }
    });

    test('a very narrow screen still gets one column, not none', () {
      expect(gridColumnsFor(tiles: 10, width: 100), 1);
    });

    test('caps the columns however wide the screen is', () {
      // A television-sized window must not produce sixty tiles across.
      expect(gridColumnsFor(tiles: 60, width: 5000), lessThanOrEqualTo(8));
    });
  });
}

/// What the screen says when there is no video, which is two different
/// things wearing one sentence until you separate them.
void _wording() {
  group('the no-video message', () {
    test('does not send a demo user to fix a school', () {
      // The demo is where people look at this product first. It has no
      // school and no server to connect, so telling somebody trying it
      // that "the school needs to connect a video server" sends them
      // off after something that is not broken.
      final demo = videoNotConfigured(demo: true);
      expect(demo.toLowerCase(), contains('demo'));
      expect(demo, isNot(contains('The school needs to connect')));
      // And says what does work, so the feature is not written off on
      // the strength of one blank screen.
      expect(demo.toLowerCase(), contains('register'));
      // "not switched on", not "demos cannot do video" -- a demo with
      // the endpoint deployed does carry a real class.
      expect(demo.toLowerCase(), contains('switched on'));
    });

    test('and tells a real school what is missing', () {
      final live = videoNotConfigured(demo: false);
      expect(live, contains('not set up'));
      expect(live.toLowerCase(), contains('video server'));
    });
  });
}

/// The card's heading and its body are read together, so they must not
/// disagree. The heading once said video was "not part of the demo",
/// which stopped being true the moment a demo could hold a class.
void _heading() {
  test('the demo wording does not deny what a demo can do', () {
    final demo = videoNotConfigured(demo: true);
    expect(demo, isNot(contains('not part of the demo')));
    expect(demo.toLowerCase(), contains('switched on'));
  });
}
