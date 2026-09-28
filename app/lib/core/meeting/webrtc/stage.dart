/// Who gets the big tile, and who goes in the strip along the side.
///
/// A lesson has one thing everybody is looking at. Usually that is the
/// teacher; the moment somebody shares a screen it is the screen, and a
/// grid of equal squares is the wrong shape for both -- a shared
/// spreadsheet drawn at a sixth of a laptop is a shared spreadsheet
/// nobody can read.
///
/// Pure, and separate from the widget, because this is the part that
/// has to be right for sixty people at once and the part nobody will
/// check by eye.
library;

/// One participant, as the layout needs to see them.
class StageSeat {
  /// Identity, not name: two pupils are called Maria.
  final String id;

  /// Whether this one is putting a screen in front of the class.
  final bool sharingScreen;

  /// The teacher. The fallback for the big tile when nobody is sharing.
  final bool moderator;

  /// This device's own participant.
  final bool isMe;

  const StageSeat({
    required this.id,
    this.sharingScreen = false,
    this.moderator = false,
    this.isMe = false,
  });
}

/// How the lesson is arranged on screen.
class Stage {
  /// The big tile, or null when everybody is equal and it is a grid.
  final StageSeat? spotlight;

  /// Everybody, in the order they should be drawn.
  final List<StageSeat> seats;

  const Stage({required this.spotlight, required this.seats});

  bool get isGrid => spotlight == null;

  /// The small tiles beside the big one.
  ///
  /// Everybody, including whoever is in the spotlight: a teacher
  /// sharing a spreadsheet is a spreadsheet in the middle and a face in
  /// the strip, and a class that cannot see the face of the person
  /// talking is listening to a spreadsheet.
  List<StageSeat> get strip => spotlight == null ? const [] : seats;
}

/// Arranges the lesson.
///
/// A shared screen wins, and the first one wins if two people share at
/// once -- which happens, and which must not make the layout flicker
/// between them on every rebuild. Otherwise there is no spotlight and
/// everybody is a square, because in an ordinary lesson the faces are
/// the lesson and one of them being larger says something untrue about
/// whose turn it is.
Stage stageFor(List<StageSeat> seats) {
  final sharing = seats.where((s) => s.sharingScreen).toList();
  if (sharing.isEmpty) return Stage(spotlight: null, seats: seats);

  // Mine first when I am one of them: a teacher who has just shared
  // needs to see what the class is seeing, immediately, to know whether
  // they shared the right window.
  final mine = sharing.where((s) => s.isMe).firstOrNull;
  return Stage(spotlight: mine ?? sharing.first, seats: seats);
}

/// How tall the strip of faces is, beside a spotlight.
///
/// A fraction of the shorter side rather than a fixed number of pixels,
/// then held between two limits: below about 90 a face is a smudge, and
/// above about 150 the strip is eating the thing everybody is looking
/// at.
double stripExtentFor(double shortestSide) =>
    (shortestSide * 0.18).clamp(90, 150);

/// Whether the strip runs along the bottom or down the side.
///
/// A shared screen is wide. On a wide window there is room beside it;
/// on a phone held upright there is not, and the faces go underneath.
bool stripBesideSpotlight({required double width, required double height}) =>
    width >= height * 1.3;
