/**
 * What a class is told when their lesson starts.
 *
 * Pure, and its own file, for the reason every other message in this
 * folder is: these are read on a lock screen by a twelve-year-old, they
 * are the part of a notification anybody actually judges, and a string
 * built inside a trigger is a string nobody can test without an
 * emulator.
 */

/** The line on the lock screen. Short, because that is all that shows. */
export function onlineClassTitle(subject: string): string {
  const named = subject.trim();
  // The subject first and by name. "LogicClass" on a lock screen says
  // which app; it does not say which lesson, and a pupil with four
  // classes a day needs the second one.
  return named ? `${named} is online now` : "Your class is online now";
}

/** The sentence under it. */
export function onlineClassBody(subject: string, section: string): string {
  const named = subject.trim();
  const room = section.trim();
  const lesson = named || "Your class";

  // The section is named when there is one, because a pupil in a school
  // that runs two Grade 10 sections of the same subject has to know
  // which of them started -- and because a family sharing a device may
  // have two children in it.
  const where = room ? ` for ${room}` : "";
  return `${lesson}${where} has started. Tap to join — your teacher will ` +
    "read out the class code.";
}
