import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/meeting/camera_setup.dart';
import 'package:logicclass/core/meeting/webrtc/stage.dart';

/// Who gets the big tile, and which camera the lesson opens.
///
/// Both are decisions taken sixty times a second in front of a class
/// and neither can be checked by looking, so both are arithmetic here
/// rather than conditions buried in a build method.
void main() {
  const teacher = StageSeat(id: 'teacher', moderator: true, isMe: true);
  const pupil = StageSeat(id: 'pupil');

  group('the stage', () {
    test('is a plain grid while nobody is sharing anything', () {
      final stage = stageFor(const [teacher, pupil]);

      expect(stage.isGrid, isTrue);
      expect(stage.spotlight, isNull);
      expect(stage.strip, isEmpty);
    });

    test('gives the big tile to a shared screen', () {
      final stage = stageFor(const [
        teacher,
        StageSeat(id: 'pupil', sharingScreen: true),
      ]);

      expect(stage.spotlight?.id, 'pupil');
      expect(stage.isGrid, isFalse);
    });

    test('keeps every face in the strip, including the one sharing', () {
      // A teacher sharing a spreadsheet is a spreadsheet in the middle
      // and a face in the strip. A class that cannot see the face of
      // the person talking is listening to a spreadsheet.
      final stage = stageFor(const [
        StageSeat(id: 'teacher', moderator: true, isMe: true, sharingScreen: true),
        pupil,
      ]);

      expect([for (final s in stage.strip) s.id], ['teacher', 'pupil']);
    });

    test('shows my own share rather than somebody else\'s', () {
      // A teacher who has just shared needs to see what the class is
      // seeing, to know whether they shared the right window.
      final stage = stageFor(const [
        StageSeat(id: 'pupil', sharingScreen: true),
        StageSeat(id: 'teacher', moderator: true, isMe: true, sharingScreen: true),
      ]);

      expect(stage.spotlight?.id, 'teacher');
    });

    test('settles on one when two others share at once', () {
      // Not a coin toss: the same list has to give the same answer
      // every rebuild, or the layout flickers between two screens.
      const seats = [
        StageSeat(id: 'a', sharingScreen: true),
        StageSeat(id: 'b', sharingScreen: true),
        teacher,
      ];

      expect(stageFor(seats).spotlight?.id, 'a');
      expect(stageFor(seats).spotlight?.id, 'a');
    });

    test('an empty lesson is still a grid, not a crash', () {
      expect(stageFor(const []).isGrid, isTrue);
      expect(stageFor(const []).seats, isEmpty);
    });
  });

  group('the strip', () {
    test('is a share of the window, within what a face needs', () {
      expect(stripExtentFor(400), 90, reason: 'never smaller than a face');
      expect(stripExtentFor(700), closeTo(126, 0.01));
      expect(stripExtentFor(2000), 150, reason: 'never eats the screen');
    });

    test('runs down the side of a wide window and under a tall one', () {
      expect(stripBesideSpotlight(width: 1400, height: 800), isTrue);
      expect(stripBesideSpotlight(width: 390, height: 840), isFalse);
      expect(stripBesideSpotlight(width: 1000, height: 800), isFalse,
          reason: 'a nearly-square window keeps the width for the screen');
    });
  });

  group('choosing a camera', () {
    const built = CameraOption(id: 'built-in', label: 'Integrated Webcam');
    const usb = CameraOption(id: 'usb-1', label: 'Logitech C920');

    test('takes the one chosen last time when it is still plugged in', () {
      expect(preferredCamera([built, usb], 'usb-1')?.id, 'usb-1');
    });

    test('falls back rather than leaving the lesson with no picture', () {
      // The document camera was unplugged over the weekend. The lesson
      // still has to start.
      expect(preferredCamera([built], 'usb-1')?.id, 'built-in');
      expect(preferredCamera([built], null)?.id, 'built-in');
      expect(preferredCamera(const [], 'usb-1'), isNull);
    });

    test('names an unlabelled camera so two of them are still a choice', () {
      // A browser gives no label until somebody has granted permission
      // once, and a list of empty strings is not a choice.
      const blank = CameraOption(id: 'x', label: '');

      expect(cameraLabel(blank, 0), 'Built-in camera');
      expect(cameraLabel(blank, 1), 'Camera 2');
      expect(cameraLabel(usb, 1), 'Logitech C920');
    });

    test('mirrors a camera pointed at you and not one pointed at the desk',
        () {
      expect(mirrorByDefault('Integrated Webcam'), isTrue);
      expect(mirrorByDefault('FaceTime HD Camera'), isTrue);
      expect(mirrorByDefault('camera2 0, facing back'), isFalse);
      expect(mirrorByDefault('Rear Camera'), isFalse);
      // Mirroring a document camera makes writing unreadable, which is
      // the one thing a document camera is for.
      expect(mirrorByDefault('IPEVO Document Camera'), isFalse);
    });
  });

  group('the background', () {
    test('is available once the camera has actually done it', () {
      expect(
        backgroundAfterTrying(
          settings: const {'backgroundBlur': true, 'width': 1280},
          wanted: true,
        ),
        BackgroundSupport.available,
      );
      expect(
        backgroundAfterTrying(
          settings: const {'backgroundBlur': false},
          wanted: false,
        ),
        BackgroundSupport.available,
      );
    });

    test('is unavailable when the camera took no notice', () {
      // The browser accepts the request and the camera carries on as
      // before. Nothing throws, nothing changes, and a switch that does
      // nothing is worse than one that says it cannot.
      expect(
        backgroundAfterTrying(
          settings: const {'backgroundBlur': false},
          wanted: true,
        ),
        BackgroundSupport.unavailable,
      );
    });

    test('is unavailable when the camera never heard of it', () {
      expect(
        backgroundAfterTrying(
          settings: const {'width': 1280, 'height': 720},
          wanted: true,
        ),
        BackgroundSupport.unavailable,
      );
      expect(cameraReportsBackground(const {'width': 1280}), isFalse);
      expect(cameraReportsBackground(const {'backgroundBlur': false}), isTrue);
    });

    test('says why, in words a teacher can act on', () {
      expect(backgroundUnavailableBecause(BackgroundSupport.available), isNull);
      expect(backgroundUnavailableBecause(BackgroundSupport.unknown), isNull,
          reason: 'untried is not a complaint');
      expect(
        backgroundUnavailableBecause(BackgroundSupport.unavailable),
        contains('not from LogicClass'),
      );
    });
  });
}
