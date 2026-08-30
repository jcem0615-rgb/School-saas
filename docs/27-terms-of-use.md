# Module 27: Terms of Use

## Overview

The agreement every account accepts before its first use, gated the same
way the privacy notice is and sitting immediately behind it.

The two are deliberately different things and the code keeps them apart.
A notice is **given** -- it tells a person what is held about them, and
`AcknowledgePrivacyScreen` has no decline button because declining would
mean a student cannot see their own grades, which is not a choice a school
can offer. Terms are **entered into**, and an agreement nobody can decline
is not an agreement. So this screen has a way out.

## The order, and why it is that order

```
sign in -> must-change-password -> privacy notice -> terms -> portal
```

Told before asked. A person learns what the system records about them,
and only then is asked to agree to something -- which also lets the terms
point at the notice as already read rather than repeating it.

Owner is exempt from both. These are terms a school issues to its people;
the platform operator is not one of them.

## Declining

"I do not accept - sign out" asks for confirmation, then signs out. The
account is untouched, nothing is recorded against it, and the page comes
back next time they sign in. The dialog says exactly that, because the
fear the button raises is that declining does something irreversible.

The page also says it in the clauses: if not being able to accept is a
problem, that is a conversation with the school rather than with this
screen. Nothing here can resolve it and pretending otherwise would waste
somebody's afternoon.

## Versioning

`TermsOfService.version` is bumped only when the substance changes. A
typo fix does not put a gate in front of eight hundred families.

An account stores `termsVersion` and `termsAcceptedAt`. The gate is
`(user.termsVersion ?? 0) < TermsOfService.version`, so raising the
version puts the page back in front of everybody -- which is the only way
a school can say what was agreed to and when.

`termsAcceptedAt` is a server timestamp. "When did they accept?" is the
one question the record exists to answer, and a phone with a wrong clock
would answer it wrongly.

## Written as data

The clauses are a `List<TermsClause>`, not prose inside a widget, for the
same reason the privacy notice is: the same words render on screen and
can be diffed when they change. Terms nobody can diff are terms nobody
can tell have changed.

## The scroll gate

Accept stays disabled until the page has been scrolled to the end. A
button that is live before the text has moved is one people press without
looking, and that press is what the school would be relying on later. On
a screen tall enough that nothing scrolls, a post-frame check enables it
-- there is nothing to reach the end of.

## Security

`termsVersion` and `termsAcceptedAt` join `privacyNoticeVersion` and
`privacyNoticeAcknowledgedAt` in `onlySelfEditableFieldsChanged()`. No
callable, for the same reason: accepting an agreement is a person
asserting something about themselves, and the uid check already
guarantees they cannot assert it about anybody else.

Three rules tests pin it: a person can record their own acceptance,
nobody can record it for somebody else, and it cannot be smuggled into
the same write as a `status` change.

## This is a template

The clauses describe honestly what the software does and what it asks of
the person using it -- the part a school would otherwise have to
reverse-engineer. **It is not legal advice**, and the school's counsel
should read it before a single account is issued, the same way
`legal/data-processing-agreement.md` is a starting point rather than a
signed document.

It is deliberately silent on availability figures and support response
times. Those are commitments the school makes, not ones this file can
invent on their behalf.

## Testing

| Layer | File | Covers |
|---|---|---|
| Boot | `demo_app_boot_test.dart` | the notice hands over to the terms rather than the portal; Accept is dead until the page is read; accepting records the version and opens the portal; the decline route exists |
| Rules | `data-requests.rules.test.ts` | self-acceptance allowed, on somebody else refused, and refused beside a status change |

Six existing tests had to learn about the new gate -- anything that
stepped past the privacy notice now steps past this too. A gate that no
test noticed appearing would be a gate that could disappear the same way.

## Deferred

- **A printable copy**, for a school that wants the agreement on paper in
  a personnel file.
- **Per-school clauses.** Right now every school issues the same terms;
  a school with its own acceptable-use policy has nowhere to put it.
