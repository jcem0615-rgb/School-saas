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

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `login_usecase_test.dart` | validation short-circuit, repo delegation |
| Domain | `change_password_usecase_test.dart` | validation, ordering of the two repo calls |
| Data | `auth_repository_impl_test.dart` | exception → Failure mapping |
| Functions | `claims.test.ts` | role/tenant guard helpers |
| Rules | `auth.rules.test.ts` | tenant isolation, self-edit whitelist, audit log lock-down |

Run Flutter tests: `flutter test` (from `app/`).
Run Functions tests: `npm test` (from `functions/`).
Run rules tests: `firebase emulators:exec --only firestore "jest test-rules/auth.rules.test.ts"`
(from repo root, requires the Firebase CLI + emulator suite installed).

## What's intentionally deferred to later modules

- Session timeout / idle logout (Security module)
- Device tracking & login history list (Security module)
- App Check enforcement on callables (Security module)
- Owner's own login path UI (Owner Portal module — same `AuthRepository`,
  different landing route via `AppRoutes.homeFor`)
