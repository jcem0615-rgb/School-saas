/// The address of a lesson, in a form a teacher can paste into a chat.
///
/// ## What the link is, and what it deliberately is not
///
/// It is an address. It is not a key, and it is not a permission.
///
/// A link sent to a class gets forwarded, pasted into a group chat,
/// screenshotted and posted. Any design where holding the link is
/// enough to be in the lesson is a design where one forwarded message
/// puts a stranger in a room of children. So the link carries the least
/// it can: which school, and which lesson. Not the room name, which is
/// the secret the media server actually accepts; not the passcode,
/// which the teacher reads out to the people who are there.
///
/// Everything that decides who comes in is decided on the server, after
/// the person has signed in: the school from their own account, a line
/// of their own in the register, the passcode, and the section, grade,
/// department and programme they are in *now*. The link only saves them
/// hunting for the lesson.
///
/// That is why this file has no secrets in it and can be tested without
/// any of them.
library;

/// Where a shared lesson link points.
class MeetingInvite {
  final String schoolId;
  final String sessionId;

  const MeetingInvite({required this.schoolId, required this.sessionId});

  @override
  bool operator ==(Object other) =>
      other is MeetingInvite &&
      other.schoolId == schoolId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(schoolId, sessionId);
}

/// The path within the app that an invitation opens.
const invitePath = '/join';

/// Builds the link a teacher copies.
///
/// [base] is wherever the app is being served from, so a school on its
/// own domain sends links to its own domain and the demo sends links to
/// the demo. Passing it in rather than reading it here keeps this
/// testable and keeps one hard-coded hostname out of the product.
Uri inviteLink({
  required Uri base,
  required String schoolId,
  required String sessionId,
}) =>
    base.replace(
      path: invitePath,
      queryParameters: {'school': schoolId, 'class': sessionId},
      // Anything the page was already carrying is not part of an
      // invitation.
      fragment: '',
    );

/// Reads a link somebody has just opened, or null if it is not one.
///
/// Null rather than an exception for anything unexpected: this runs on
/// whatever a browser was pointed at, including a half-copied link from
/// a chat app that truncated it, and the right answer to that is the
/// ordinary "sign in and find your class" screen rather than a crash.
MeetingInvite? readInviteLink(Uri link) {
  if (!link.path.startsWith(invitePath)) return null;
  final school = link.queryParameters['school']?.trim() ?? '';
  final session = link.queryParameters['class']?.trim() ?? '';
  if (school.isEmpty || session.isEmpty) return null;
  // Firestore ids, not free text. A link is the one place a stranger
  // chooses what this app looks up, so what it may name is bounded
  // before it reaches a query.
  if (!_id.hasMatch(school) || !_id.hasMatch(session)) return null;
  return MeetingInvite(schoolId: school, sessionId: session);
}

/// What a Firestore document id may be, and nothing else.
final _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// The message a teacher sends, with the link but never the code.
///
/// Written out here rather than left to whoever builds the button,
/// because the one thing that must never happen is the passcode being
/// swept into the same copy as the link. Together in one message they
/// are a single thing to forward, and the passcode stops being a second
/// lock at all.
String inviteMessage({
  required String subject,
  required String section,
  required Uri link,
}) =>
    'Join $subject ($section) on LogicClass:\n'
    '$link\n\n'
    'You will need the class code. I will read it out at the start.';

/// The location inside the app that an invitation opens.
///
/// A path and a query, with no host: what a router wants, where
/// [inviteLink] gives what a chat app wants.
String inviteRoute(MeetingInvite invite) => Uri(
      path: invitePath,
      queryParameters: {'school': invite.schoolId, 'class': invite.sessionId},
    ).toString();

/// The link for a lesson, from wherever this app is being served.
///
/// Null rather than a guess when there is nowhere to point at. On a
/// phone build `Uri.base` is a file path, not a website, and a link
/// built from one would be a link that opens nothing -- so the teacher
/// is told to read the code out instead.
Uri? classInviteLink({required String? schoolId, required String sessionId}) {
  if (schoolId == null || schoolId.isEmpty || sessionId.isEmpty) return null;
  final base = Uri.base;
  if (base.scheme != 'http' && base.scheme != 'https') return null;
  return inviteLink(base: base, schoolId: schoolId, sessionId: sessionId);
}
