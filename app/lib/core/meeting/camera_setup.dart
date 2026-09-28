/// Choosing a camera, and what to do with the picture once chosen.
///
/// A school laptop has a built-in camera and, often, a better one on a
/// USB lead; a phone has two. The lesson opens whichever the browser
/// hands over first, which is not reliably the one pointing at the
/// teacher. Everything here is the arithmetic and the naming around
/// that choice -- pure, so it can be tested without a camera, which is
/// the only way any of it gets tested at all.
library;

/// One camera the browser is willing to hand over.
class CameraOption {
  /// What the browser calls it. Stable enough to remember a choice by.
  final String id;

  /// What the browser says it is called, which may be nothing at all.
  final String label;

  const CameraOption({required this.id, required this.label});
}

/// What to put in front of a person choosing between cameras.
///
/// A browser gives no label until somebody has granted permission
/// once, so before that every camera is an empty string and a list of
/// empty strings is not a choice. Numbering them at least makes them
/// distinguishable, which is enough to try one and see.
String cameraLabel(CameraOption camera, int position) {
  final label = camera.label.trim();
  if (label.isNotEmpty) return label;
  return position == 0 ? 'Built-in camera' : 'Camera ${position + 1}';
}

/// The camera to open, given what is plugged in and what was chosen
/// last time.
///
/// Remembering the choice matters more than it sounds: a teacher who
/// sets up a document camera for a lesson should not have to set it up
/// again for the next one, and an external camera that was unplugged
/// over the weekend must not leave the lesson with no picture at all.
CameraOption? preferredCamera(List<CameraOption> cameras, String? remembered) {
  if (cameras.isEmpty) return null;
  if (remembered != null) {
    for (final camera in cameras) {
      if (camera.id == remembered) return camera;
    }
  }
  return cameras.first;
}

/// Whether a camera's picture should be flipped for the person in it.
///
/// A front camera is a mirror: raise your right hand and the hand on
/// your right goes up. Everybody expects that of themselves and nobody
/// expects it of anybody else, so this applies only to one's own tile.
/// A rear or document camera is pointed at the world, and mirroring the
/// world makes writing unreadable -- which is precisely what a document
/// camera is for.
bool mirrorByDefault(String label) {
  final text = label.toLowerCase();
  if (text.contains('back') || text.contains('rear')) return false;
  if (text.contains('document') || text.contains('doc cam')) return false;
  if (text.contains('environment')) return false;
  return true;
}

/// What the browser can do about the background behind a person.
enum BackgroundSupport {
  /// Not tried yet. The switch is offered, because the only honest way
  /// to find out is to flip it.
  unknown,

  /// It was flipped and the camera did as it was told.
  available,

  /// It was flipped and nothing happened, or the camera does not
  /// report the setting at all.
  unavailable,
}

/// The name the browser uses for the setting.
const backgroundBlurSetting = 'backgroundBlur';

/// Whether this camera admits to having the setting.
///
/// The blur is the operating system's own -- Windows Studio Effects,
/// macOS, a ChromeOS device -- reached through a property on the camera
/// track. A camera that does not report the property does not have it,
/// and on most school hardware it will not.
///
/// The browser's list of what the property *can* be set to would say
/// whether there is a switch or whether it is stuck one way, but the
/// Dart side of the WebRTC binding does not expose that list. So the
/// detection is the honest one: flip it, read it back, and believe what
/// the camera says it is now.
bool cameraReportsBackground(Map<String, dynamic> settings) =>
    settings.containsKey(backgroundBlurSetting);

/// What the camera's settings say after being asked to change.
BackgroundSupport backgroundAfterTrying({
  required Map<String, dynamic> settings,
  required bool wanted,
}) {
  if (!cameraReportsBackground(settings)) return BackgroundSupport.unavailable;
  return settings[backgroundBlurSetting] == wanted
      ? BackgroundSupport.available
      : BackgroundSupport.unavailable;
}

/// Why the blur switch is greyed out, in words for a teacher.
String? backgroundUnavailableBecause(BackgroundSupport support) =>
    switch (support) {
      BackgroundSupport.available => null,
      BackgroundSupport.unknown => null,
      BackgroundSupport.unavailable =>
        'This camera cannot blur its own background. The blur comes '
            'from the camera and the computer -- Windows Studio Effects, '
            'macOS, a Chromebook -- and not from LogicClass, so there is '
            'nothing here to switch on.',
    };
