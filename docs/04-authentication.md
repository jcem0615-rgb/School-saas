# Module 4: Authentication

## Overview

Every user in the system — from the platform Owner down to a Parent — signs
in through Firebase Authentication (email/password). What differs per role
is not the login mechanism but the **custom claims** attached to their ID
token, which drive both client-side routing and server-side Security Rules.

## Custom Claims

```json
{
  "schoolId": "school_abc123",   // absent for the Owner (platform-level)
  "role": "registrar",
  "status": "active",
  "mustChangePassword": false
}
```

Claims are **only ever set server-side**, from three Cloud Functions:

| Function | Trigger | Sets |
|---|---|---|
| `provisionUser` | Admin/Director/Owner creates a new account | full claim set, `mustChangePassword: true` |
| `resetPasswordAdmin` | Admin/Director/Owner resets someone's password | `mustChangePassword: true` |
| `clearForcePasswordChangeFlag` | User successfully changes their own password | `mustChangePassword: false` |

The client **never** writes claims directly — this is what Security Rules
key off of, so a compromised device can't grant itself a different role or
tenant.

## Flows

**Login** → `LoginScreen` → `AuthController.login()` → `LoginUseCase` (client
validation) → `AuthRepository.login()` → `AuthRemoteDataSource` (FirebaseAuth
sign-in + Firestore profile fetch) → emits `AppUser` via `authStateProvider`.

**Forced password change** → the router (`app_router.dart`) intercepts
*any* navigation while `mustChangePassword == true` and redirects to
`ForcePasswordChangeScreen`. On success, `ChangePasswordUseCase` calls
`changePassword` then `clearForcePasswordChangeFlag` — in that order, and
only if the first succeeds (see `change_password_usecase_test.dart`).

**Forgot password** → standard Firebase Auth reset email, no custom claim
involved.

**Account provisioning** (not by self-registration — schools are B2B
tenants) → an Admin/Director calls `provisionUser`, which creates the Auth
account, sets claims, writes the Firestore profile, and returns a temporary
password for hand-off. The `PROVISIONING_MATRIX` in that function encodes
exactly which role can create which other roles.

## Security Model

- **Path-level isolation**: every tenant collection lives under
  `/schools/{schoolId}/...`, so Security Rules check `schoolId` as part of
  the *path match itself*, not just as a field comparison.
- **Field-level self-edit whitelist**: a user can update their own `phone`,
  `photoUrl`, `privacySettings` — never `role`, `status`, `schoolId`, or
  `mustChangePassword`. Enforced via `diff().affectedKeys()` in
  `firestore.rules`.
- **Audit log is write-only from Cloud Functions**: `allow write: if false`
  in rules; every entry that exists was genuinely written by trusted server
  code via the Admin SDK.
- See `test-rules/auth.rules.test.ts` for the rules-unit-tests that assert
  the above against the Firestore emulator.

## Remember me

Ticked, sign-in stores the **email** and nothing else, so somebody coming
back types a password instead of a password and a long school address.
The box comes back ticked and the field filled in; unticking it forgets,
which is the only way to take a shared computer back off the list.

No password is stored, on any platform, under any setting. A school's
front desk is a shared machine and a remembered password there is
everybody's password -- there is no version of this feature worth that.
The screen says so in a line under the box, because "remember me" is
otherwise read as exactly that promise. A test asserts it by walking
every key in preferences, not just the one this feature owns.

Staying signed in *between sessions* is separate and was already there:
firebase_auth persists its own session in real mode, and `DemoSession`
does the same for the demo.

The email is written before the sign-in attempt rather than after it. A
successful sign-in redirects immediately -- the router reacts to
`authStateProvider` -- so work queued behind that await runs on a screen
already on its way out. It also means unticking and then failing to sign
in still forgets, which is the right way round for the shared-computer
case.

The password field's show/hide toggle lives in `AuthTextField` and is on
every password field in the app, not only this one.

## Signing out

The button is at the bottom of Profile, spelled out, in the error colour,
with a confirmation that names the account being ended. Profile is the one
screen all ten portals link to, so this is the one place it needs to be.

It was there before as an unlabelled icon in the Profile app bar, and
people asked where sign-out was while looking straight at it. An icon is a
reminder for somebody who already knows the button exists; it is not how
anybody finds one. The icon stays -- both now go through the same
confirmation.

The confirmation names the account (`You are signed in as ... (email)`)
because school computers are shared, and the person at the keyboard is not
always the person the app is signed in as.

Sign-out unregisters the device's push token first, and does so inside its
own `try` -- failing to tidy up a token is not a reason to leave somebody
signed in on a shared machine.

## One account, one device

Signing in somewhere new signs you out everywhere else.

A school login is worth sharing: one paid parent account read by three
families, one student account lent to a friend, one staff account left
signed in on a machine in the faculty room. A password does not catch any
of that.

**The mechanism.** One document, `sessions/current`, under the account's
own profile -- `schools/{schoolId}/users/{uid}/sessions/current`, or
`platform_owner_profiles/{uid}/sessions/current` for the Owner, who
belongs to no school. It holds the id of whichever device claimed the
account last. Every signed-in device watches it; a device that reads an id
which is not its own signs itself out through the ordinary sign-out path,
then says why.

**Where it lives, and why not on the user document.** `users/{uid}` is
readable by everyone in the school. Where a colleague is signed in is not
the school's business, and -- the half that actually bites -- anyone who
could *write* it could sign that person out at will, which would turn a
sharing deterrent into a way to lock a colleague out of the app on
enrolment day. Only the account holder reads or writes their own. Same
reasoning as `deviceTokens`, same shape.

**Claim first, then watch.** The order is load-bearing. On sign-in the
first thing the stream delivers is whatever claim was already there,
which for anyone who last used a different device is not this one. A
device that enforced on that emission would sign itself out immediately
after every sign-in on a second machine, and the account would be
reachable only from the last device that used it. Claiming first makes
the newest sign-in the winner: the device in your hand works, the one you
left at home is the one that gets signed out.

**The device id** is 128 random bits minted once and kept in
`shared_preferences`. It identifies nothing about the machine, only that
it is the same one as last time. "Device" means one app installation, so
two browsers on the same laptop are two devices -- the honest unit, and
the only one available without fingerprinting, which this app does not do.

If the id cannot be stored -- a private window, site data blocked -- the
rule switches itself **off** for that device rather than minting a fresh
id per launch. A new id every launch would displace the account every
launch, and the person could not stay signed in at all. The same applies
when the claim write fails: a device that never claimed does not act on
what it reads.

**What this is not.** It is an honesty mechanism, not a security
boundary. Enforcement is in the app, and rules cannot require a write a
modified client simply never makes. What it does do is make casual
sharing stop working, every time, which is enough to make a shared
account useless as a shared account.

**Demo mode has none of it.** There is no Firebase to hold the claim and
one browser tab cannot take a session from itself, so `sessionGuardProvider`
is overridden to `NoOpSessionGuard` (`demo_overrides.dart`). Nothing about
the rule can be seen on the demo site; it needs two real devices and a
real project.

| Piece | File |
|---|---|
| The rule, as a pure function | `core/session/session_guard.dart` (`verdictFor`) |
| Firestore claim document | `core/session/session_guard_impl.dart` |
| Per-installation id | `core/session/device_identity.dart` |
| Wiring, and the sign-out on displacement | `core/session/single_device_session.dart` |
| Rules | `firestore.rules`, `test-rules/sessions.rules.test.ts` |

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `login_usecase_test.dart` | validation short-circuit, repo delegation |
| Domain | `change_password_usecase_test.dart` | validation, ordering of the two repo calls |
| Data | `auth_repository_impl_test.dart` | exception → Failure mapping |
| Functions | `claims.test.ts` | role/tenant guard helpers |
| Rules | `auth.rules.test.ts` | tenant isolation, self-edit whitelist, audit log lock-down |
| Rules | `sessions.rules.test.ts` | the single-device claim is the holder's alone -- not a colleague's, not an admin's |
| Widget | `single_device_test.dart` | the verdict, the id's stability, displacement, and the sign-out button |

Run Flutter tests: `flutter test` (from `app/`).
Run Functions tests: `npm test` (from `functions/`).
Run rules tests: `firebase emulators:exec --only firestore "jest test-rules/auth.rules.test.ts"`
(from repo root, requires the Firebase CLI + emulator suite installed).

## What's intentionally deferred to later modules

- Session timeout / idle logout (Security module)
- A login *history* list -- which devices have signed in, and when.
  Only the current one is recorded (see **One account, one device**);
  keeping the past ones is a retention question the privacy notice
  would have to answer first.
- App Check enforcement on callables (Security module)
- Owner's own login path UI (Owner Portal module — same `AuthRepository`,
  different landing route via `AppRoutes.homeFor`)

## Surviving a reload

Demo mode keeps everything in memory, so a browser refresh — or the F5
somebody hits out of habit — used to drop a visitor back at the login
screen mid-demo. Real mode never had this: `firebase_auth` persists its
own session. `DemoSession` is the demo's stand-in for that. It is one of
two things in the app that use `shared_preferences` -- the other is the
device id behind the single-device rule.

Only the **email** is stored. Never a password, and never any of the
demo's data — the fixture is seeded fresh on every load, because
persisting edits would mean each visitor inherited whatever the last one
did to it. The account is looked back up in `DemoStore.demoAccounts` on
the way in, so a stored value that no longer matches an account restores
nobody rather than resurrecting a half-valid session.

The restore is awaited in `main()` **before** `runApp`, and the store is
seeded synchronously from it. Reading it from inside the widget tree
would paint the login screen and then jump to the portal, which reads as
being signed out and immediately signed back in.

Remembering is deliberately not awaited (signing in must not wait on a
disk write; a failed one costs a re-login). Forgetting *is* awaited: a
sign-out that left the session on disk would put the next visitor
straight into the previous one's portal. The demo role switcher is
remembered too — otherwise a reload comes back as whoever typed a
password rather than the role you were actually looking at.

Storage being unavailable (a private window, a locked-down browser) is
caught and ignored. A demo that cannot remember a session must still
open.
