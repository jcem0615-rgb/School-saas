/// What a class is told when their lesson starts.
///
/// The product sends this from a Firestore trigger; the twin of this
/// file is `functions/src/shared/notify/onlineClassMessage.ts`. The demo
/// has no Cloud Functions, so it writes the same notification into its
/// own store from the same words -- otherwise the demo would show a
/// feature the product has and word it differently, which is the kind
/// of difference nobody notices until a school asks why.
///
/// Pure strings, tested on their own, because they are read on a lock
/// screen by a twelve-year-old and that is the part anybody judges.
library;

/// The line on the lock screen. Short, because that is all that shows.
String onlineClassTitle(String subject) {
  final named = subject.trim();
  // The subject first and by name. "LogicClass" on a lock screen says
  // which app; it does not say which lesson, and a pupil with four
  // classes a day needs the second one.
  return named.isEmpty ? 'Your class is online now' : '$named is online now';
}

/// The sentence under it.
String onlineClassBody(String subject, String section) {
  final lesson = subject.trim().isEmpty ? 'Your class' : subject.trim();
  // The section is named when there is one, because a pupil in a school
  // that runs two Grade 10 sections of the same subject has to know
  // which of them started -- and because a family sharing a device may
  // have two children in it.
  final where = section.trim().isEmpty ? '' : ' for ${section.trim()}';
  return '$lesson$where has started. Tap to join — your teacher will '
      'read out the class code.';
}

/// Where tapping it lands: the same address as an invitation link.
///
/// One route for both, so a notification and a forwarded link end up in
/// the same place, asking for the same code, checked by the same four
/// locks. In both cases it is an address and never a permission.
String onlineClassLink({required String schoolId, required String sessionId}) =>
    '/join?school=$schoolId&class=$sessionId';
