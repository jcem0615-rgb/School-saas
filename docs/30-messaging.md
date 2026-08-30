# Module 30: Parent–teacher messaging

## Overview

A parent and a teacher can message each other about a child. That is the
whole feature, and every design decision in it follows from one
question: **who may talk to whom, and who may read it.**

## Who may talk

A parent may message a teacher when that teacher teaches that parent's
child. Resolved server-side from three records neither of them can edit:

* the teacher's assignments (`teacherAssignments`),
* the student's section (`students/{id}.section`),
* the parent's linked children (`users/{uid}.linkedStudentIds`).

**This cannot be a rule.** Deciding it needs a *query* — which of this
teacher's assignments covers that section — and `firestore.rules` can
only fetch a document by path. So opening a thread is the
`startConversation` callable. Once it has written the conversation,
membership *is* a field on a document, which rules can police, and every
message after that is an ordinary client write.

Nobody else can open one. Not an admin, not the director, not guidance.
A school with something to say to every family has announcements.

## Who may read

Only the two participants. Not the office.

That is a real decision with a real cost, and it is deliberate. A parent
who believes the principal is reading tells the teacher nothing worth
reading, and a channel nobody trusts is a channel nobody uses. A school
that genuinely needs to see one of these conversations has a
lawful-request path and an audit trail; what it does not have is a rule
that quietly makes every private conversation readable by whoever holds
an admin login.

## The shape of it

| Collection | One document per | Written by |
| --- | --- | --- |
| `conversations/{teacherUid}__{parentUid}__{studentId}` | teacher, parent and child | `startConversation` and `onMessageCreated` only |
| `conversations/{id}/messages/{messageId}` | message | the sender, as a client write |

**One thread per child, not per pair.** A parent with two children taught
by the same teacher gets two threads, so "which child is this about"
stays answerable without anybody having to say so in the first message.

**The id is derived, not generated.** Two people opening a conversation
with each other in the same moment land in the same thread. A generated
id gives them two, each holding half the conversation, and neither knows
the other exists — the classic way messaging goes wrong.

**Messages are a subcollection** because they are only ever read through
their conversation. There is no "all messages in the school" screen, and
there must not be one.

## Deliberate choices

**The summary is server-written.** `lastMessage`, `lastMessageAt` and the
unread counts are set by `onMessageCreated`, never by a client. A client
that could write them could push its own thread to the top of somebody's
list, or mark its messages read on the other person's behalf.

**Each side clears only its own unread count.** The one client write
allowed on a conversation document, and the rule spells out both
participants explicitly — mine goes to zero, theirs comes back exactly as
it was. Rules have no loops, and being explicit is what makes it
checkable. Without the second half, "I read it" becomes "you read it" and
the other side's badge disappears without them ever opening the thread.

**A message is never edited and never unsent.** `allow update, delete: if
false`. It is the record of what was said, and a thread either side could
rewrite afterwards is worth nothing to either of them.

**The sender is pinned to the caller**, in the rules as well as in the
client. Otherwise either side could put words in the other's mouth in a
thread the school might one day be asked to produce.

**Every message notifies**, through the same delivery path as everything
else (Module 17), and the notification names the child — a teacher with
thirty families and a parent with four teachers both need to know which
conversation rang before they open it.

**Empty messages are refused** in three places: the send button, the
controller, and the rules. An empty bubble tells the other person nothing
and still rings their phone.

## Starting a thread

Both sides go through the same sheet, and it asks a different number of
questions depending on who is looking:

* **Parent** → which child (skipped when there is only one) → which of
  that child's teachers. The class adviser is listed first: they are the
  one person responsible for the class as a whole, and usually who a
  parent means.
* **Teacher** → which class → which student → which guardian.

Both end in the callable, which checks the relationship again. The
pickers are what make the screen usable; they are not what makes it safe.

## Covered by tests

* `functions/test/shared/messaging/conversation.test.ts` — the derived
  id (same for both people, different per child), section matching that
  survives a stray space or a capital letter, an empty section matching
  nothing rather than everything, and a malformed `linkedStudentIds`
  failing closed rather than opening every child in the school.
* `test-rules/messaging.rules.test.ts` — only participants read a thread
  (an admin and a director are asserted *not* to), the sender pin, empty
  and oversized messages, no edits and no unsends, and an unread count
  that cannot be cleared on the other person's behalf.
* `app/test/smoke/messaging_test.dart` — the four refusals (wrong child,
  wrong teacher, wrong role, outsider sending), an existing thread being
  returned rather than duplicated, the unread count moving on one side
  only, and the notification that follows a message.
* `app/test/smoke/portal_actions_test.dart` — the screen renders for
  both roles.

## Not covered

The callable and the trigger are not run against the emulator. The
relationship logic inside them is pure and tested, the rules that guard
what they produce are tested, and the demo repositories mirror both — but
"the deployed function refuses what the demo refuses" is asserted by
reading, not by running.
