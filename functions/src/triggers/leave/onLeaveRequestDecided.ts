import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {deliver} from "../../shared/notify/deliver";

/**
 * Tells an employee what the office decided about their leave.
 *
 * The decision is already visible on their own My Leave screen, but
 * visible is not told -- and leave is the case where that gap costs
 * something specific. Somebody who filed for Thursday and never heard
 * back either comes in when they should not have, or stays away when
 * they were expected. Both are avoidable by saying so.
 *
 * Only on the transition into a decision. An edit to the remarks
 * afterwards, or a re-save of an already-approved request, notifies
 * nobody: the answer has not changed.
 */
export const onLeaveRequestDecided = onDocumentUpdated(
  {region: "asia-southeast1", document: "schools/{schoolId}/leaveRequests/{requestId}"},
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const wasPending = before.status === "pending";
    const nowDecided = after.status === "approved" || after.status === "declined";
    if (!wasPending || !nowDecided) return;

    const employeeUid = after.employeeUid as string | undefined;
    if (!employeeUid) return;

    const approved = after.status === "approved";
    const range = formatRange(after.fromDate as string, after.toDate as string);
    const remarks = ((after.decisionRemarks as string) ?? "").trim();
    const decidedBy = ((after.decidedByName as string) ?? "").trim();

    await deliver({
      schoolId: event.params.schoolId,
      recipientUids: [employeeUid],
      kind: "approval",
      title: approved ? "Leave approved" : "Leave not approved",
      body:
        `Your ${leaveLabel(after.type as string)} for ${range} was ` +
        `${approved ? "approved" : "declined"}` +
        (decidedBy ? ` by ${decidedBy}` : "") +
        "." +
        (remarks ? ` ${remarks}` : ""),
      link: "/my-leave",
      // The request id alone would notify once and never again, which is
      // wrong the day an office reverses itself: the status is part of
      // what makes this notification distinct from the last one.
      sourceId: `${event.params.requestId}:${after.status}`,
      data: {requestId: event.params.requestId},
    });
  }
);

/** "3 to 5 March", or one date when it is a single day. */
function formatRange(from: string, to: string): string {
  if (!from) return "your requested dates";
  if (!to || from === to) return prettyDate(from);
  return `${prettyDate(from)} to ${prettyDate(to)}`;
}

/**
 * Formatted from the date key itself rather than through a Date.
 *
 * The key is already the school's day. Parsing it into a Date and back
 * puts it through the server's timezone, which is how "3 March" becomes
 * "2 March" for every early-morning render.
 */
function prettyDate(key: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!match) return key;
  const [, year, month, day] = match;
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  const name = months[Number(month) - 1] ?? month;
  return `${Number(day)} ${name} ${year}`;
}

function leaveLabel(type: string): string {
  switch (type) {
    case "sick": return "sick leave";
    case "vacation": return "vacation leave";
    case "emergency": return "emergency leave";
    case "bereavement": return "bereavement leave";
    case "maternity": return "maternity or paternity leave";
    case "unpaid": return "leave without pay";
    default: return "leave";
  }
}
