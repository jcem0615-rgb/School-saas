# Module 31: Password recovery by phone

## Overview

Email password reset already existed. It assumes the person has an email
account they can reach, which for a parent whose only device is the
handset in their pocket is often not true — and the account they cannot
get into is frequently the one the school emailed the invitation to.

So there is a second route: **the SIM is the proof.** A code is texted to
the number the school has on the person's record, and confirming it lets
them set a new password on that account.

Both routes are offered. A teacher on a school laptop would rather not
wait for a text; a parent with no working email has nothing else.

## How it works

1. **Enter the number.** Typed the way people write it —
   `09171234567` — and converted to `+639171234567` before it reaches
   Firebase. Asking for the international form would lose people on the
   first field.
2. **Firebase texts a code.** `signInWithPhoneNumber` on the web,
   `verifyPhoneNumber` on mobile — two different APIs, wrapped rather
   than one emulated with the other, because the emulation is where
   Android's auto-retrieval would be lost.
3. **Confirming the code signs them in as the phone.** That is *not*
   their school account. It is proof that they hold that SIM and nothing
   more.
4. **`resetPasswordByPhone` does the rest.** It reads
   `request.auth.token.phone_number` — a number Firebase verified, not
   one the client typed — finds which account the school registered
   against it, and sets the password.
5. **The phone session is signed out**, and they sign in normally with
   the password they just chose.

## Deliberate choices

**Exactly one account, or nothing happens.** Two accounts sharing a
number — a parent who also works at the school, a household with one
handset — is not a tie to be broken by picking the first: whichever one
this chose would be a password reset the other person never asked for.
It refuses and says so, and the office sorts it out.

**Suspended, deleted and Owner accounts are not recoverable.** A text
message is not enough to take the account that can reach every school on
the platform.

**Numbers are matched by normalising, not by string equality.** A
registrar types `0917 555 0100`, a handset reports `+639175550100`,
somebody else writes `(0917) 555-0100`. All three are the same phone, and
comparing them as strings locks a family out of their account over a
space. An unusable number normalises to empty and matches **nothing,
including another empty one** — otherwise every account with a blank
phone would match every other, and a blank number would recover somebody
else's password.

**The whole user collection is read and filtered in memory**, rather than
queried on `phone`. The stored numbers are in three different formats, so
an equality query would miss most of them.

**The school is not asked for.** Somebody who cannot sign in does not
know their school's internal id, so every school on the platform is
searched — with a cap of 200, past which it refuses loudly rather than
quietly reading a hundred thousand documents to answer one reset. A
number registered at two schools comes out as ambiguous, not as whichever
school was read first.

**Every other session on the recovered account is revoked.** Somebody
recovering an account is often doing it because somebody else has it. The
success screen says so, because it will surprise someone.

**"No account here" is said plainly.** A recovery that silently does
nothing leaves somebody waiting for a text that is never coming — and the
number is already proven to be theirs, so it discloses nothing they could
not learn by trying to sign in.

**The phone number is not written into the audit log.** It is on the user
record already, and an audit trail is read by more people than the record
is. The entry says the method was `phone_otp` and nothing else.

**In demo mode no SMS is sent**, the code is `123456`, and the screen
says so. A demo that asked for a code nobody can receive is a dead end,
and texting a stranger to let them look at a demo would be rude, slow and
billable.

## Covered by tests

* `functions/test/shared/auth/phone.test.ts` — the three formats the same
  number gets written in, spaces and brackets, an unusable number
  matching nothing (including another unusable one), and the resolution
  outcomes: one match, none, ambiguous, suspended, deleted, and Owner.
* `app/test/smoke/phone_reset_test.dart` — the steps happening in order,
  a blank number refused before anything is sent, a wrong code not
  advancing, and the number conversion including a foreign number left
  alone.
* `app/test/smoke/portal_actions_test.dart` — the screen renders. This
  caught a crash on the way *out* of it: the screen's `dispose` read a
  provider, which throws once the widget is gone. Ending the phone
  session is the controller's job, and it does it in its own `dispose`.

## Not covered, and what a deployer must do

No test proves an SMS arrives. That needs a live Firebase project, a real
handset and a number, and it is the one thing here that cannot be faked.

Before this works on a real deployment:

1. **Enable Phone as a sign-in provider** in Firebase Authentication.
2. **Web needs reCAPTCHA** — Firebase handles it, but the domain must be
   in the authorised list, or every send fails with no visible reason.
3. **Deploy the callable** — `firebase deploy --only
   functions:resetPasswordByPhone`.
4. **Check the numbers on file.** This is only as good as the `phone`
   field on each user record. A school that never filled it in has given
   its families a recovery route that finds nothing.

SMS is billed per message and phone auth has per-project quotas. It is
worth knowing before a term starts, not during one.
