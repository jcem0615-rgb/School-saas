# Going live

The app ships in demo mode: an in-memory store, twelve demo accounts, no
network. That stays exactly as it is — everything below is the *other*
mode, and turning it on takes nothing away.

Real mode is `DEMO_MODE=false`. It needs a Firebase project, which only
you can create, so this is the list of steps that are yours.

## 1. Create the Firebase project

In the Firebase console, create a project and enable:

- **Authentication** → Email/Password provider
- **Cloud Firestore**
- **Cloud Storage**
- **Cloud Functions** (needs the Blaze plan; the free tier does not run
  functions)

Register an app per platform you intend to ship — Android, iOS, Web —
and keep the config values from each.

## 2. Deploy the rules and functions

```sh
firebase deploy --only firestore:rules,storage:rules
cd functions && npm install && npm run build
firebase deploy --only functions
```

The functions are deployed to `asia-southeast1`. That is set per-function
in the source; changing it means editing every `onCall` region.

## 3. Set the owner email, before anything else

`bootstrapOwner` reads `OWNER_EMAIL` from its own environment. Nothing the
client sends is trusted — this is the only thing that decides who may
claim the owner role.

```sh
firebase functions:secrets:set OWNER_EMAIL
# enter your address when prompted, then redeploy functions
```

## 4. Claim the owner role, once

1. Sign up through Firebase Auth with that exact email.
2. **Verify the address.** `bootstrapOwner` refuses an unverified one, so
   that nobody can claim the configured address on a provider that hands
   out unverified sign-ups.
3. Call the `bootstrapOwner` callable while signed in as that account.
4. Sign out and back in. The role lives in a custom claim, and your
   client is still holding the token from before it was granted.

The function then closes the door behind you: it writes
`platform_config/owner` and refuses everyone afterwards, including your
own email. There is no second owner and no way to re-run it. If you ever
genuinely need to move the role to a different account, delete that
document with the Admin SDK — deliberately, not from the app; the rules
deny every client write to it.

## 5. Build with the project settings

The Firebase values arrive as `--dart-define` rather than a generated
`firebase_options.dart`, so the repository still compiles for anyone who
only wants the demo. See `app/lib/firebase_config.dart`.

```sh
flutter build apk --release \
  --dart-define=DEMO_MODE=false \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=...   # web only
```

Missing values fail at startup naming the ones that are absent, rather
than with the SDK's own "no Firebase app" message, which says nothing
about which.

Android additionally needs `google-services.json` in `app/android/app/`
and the Google Services Gradle plugin applied if you want push
notifications; iOS needs `GoogleService-Info.plist`.

## Who can create whom

Enforced in `functions/src/callable/users/provisionUser.ts`, server-side.
The client never decides this.

| Signed in as | Can create |
| --- | --- |
| Owner | Director, Admin |
| Director | Admin, Principal, Registrar, Faculty, Staff, Guidance |
| Admin | Principal, Registrar, Faculty, Staff, Guidance |
| Registrar | Student, Parent |

**Owner appears in no row.** `provisionUser` refuses the owner role
outright, so the only route to it is step 4 above — which runs once.

The Owner can create a Director *and* an Admin so a new school can be
stood up without signing in as its Director first just to make the Admin.

## Adding a school

There is no sign-up. Schools exist because you add them: Owner portal →
School Management → **Add School**.

A school is three documents — the platform record, its subscription, and
the tenant-side profile — written in one transaction. Half a school is
invisible in your list and unusable by its Director, so it is all or
nothing. The id is derived from the name and is **permanent**: every
account and every record in that school is scoped to it, and Firestore
document ids cannot be renamed.

Then provision its Director, who staffs the rest.
