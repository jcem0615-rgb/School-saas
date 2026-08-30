/**
 * The words a family reads on a lock screen when the guidance office
 * calls their child in.
 *
 * Pure, and in `shared/` rather than inline in the trigger, because
 * assembling a sentence out of three optional parts is exactly the kind
 * of code that reads as obviously correct and is not: the first draft of
 * this appended a full stop to a sentence that already ended in one, so
 * a summons with no stated reason read "...guidance office on Tue 3
 * Mar.." Nobody would have noticed until a parent did.
 */

/** Formats a scheduled date in the school's own timezone, or "" if absent. */
export function formatSummonsWhen(date: Date | null): string {
  if (!date || Number.isNaN(date.getTime())) return "";
  // Hard-coded to Manila rather than read from the school document,
  // because every school on this platform is in one timezone, and a
  // notification that says 1:00 am because the function ran in UTC is
  // worse than one that gives no time at all.
  return new Intl.DateTimeFormat("en-PH", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
    timeZone: "Asia/Manila",
  }).format(date);
}

export function summonsIssuedBody(
  studentName: string,
  when: string,
  reason: string
): string {
  const who = studentName.trim() || "Your child";
  const first = sentence(
    `${who} is asked to come to the guidance office${when ? ` on ${when}` : ""}`
  );
  const why = reason.trim();
  return why ? `${first} Reason: ${sentence(why)}` : first;
}

export function summonsCancelledBody(studentName: string, when: string): string {
  const who = studentName.trim() || "your child";
  return sentence(
    `The guidance office has cancelled the appointment for ${who}${
      when ? ` on ${when}` : ""
    }. There is nothing to attend`
  );
}

/** Ends a fragment with exactly one terminator. */
function sentence(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return "";
  return /[.!?]$/.test(trimmed) ? trimmed : `${trimmed}.`;
}
