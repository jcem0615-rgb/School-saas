# Light and dark

Both themes have existed since the app shell was built — `AppTheme.light()`
and `AppTheme.dark()`, with a palette whose own comment says light and
dark are "two different rooms rather than one inverted". Nothing ever
chose between them, so the app followed the device and every screen in
it had only ever been painted light.

Now each account chooses.

## Where it is

**Profile → Appearance**, on every role's Profile screen, and a single
cycling button at the bottom of the sign-in page.

Three choices, not a switch:

| | |
|---|---|
| **Automatic** | Follows the device. The default. |
| **Light** | Always light. |
| **Dark** | Always dark. |

Three because two of the answers are not opposites. "Dark" turned off
could mean light, or it could mean follow my phone, and a switch cannot
say which — so somebody who turns dark off on a phone that is itself
dark gets a result nobody chose. Three named choices have no such gap.

It applies the moment it is pressed. There is no Save: a setting whose
result you are looking at does not need confirming.

## It belongs to the account, not the computer

A school's front desk has a morning receptionist and an afternoon one.
One of them preferring dark is not a decision about the other.

So the choice is stored per account — `logicclass.theme.user.<uid>` —
and the provider watches who is signed in, which means signing out and
signing in as somebody else swaps the theme with the account. An account
that has never chosen follows the device rather than inheriting whatever
the last person at that computer preferred.

There are two other slots, and each earns its place:

- `logicclass.theme.signed-out` — somebody reading a sign-in page at
  night should be able to turn the lights down before they have an
  account to remember it against.
- `logicclass.theme.last` — the device's most recent choice, whoever
  made it. Used for the very first frame, before anyone is known.

## Why it is read synchronously

The theme is needed by the *first* frame. Read a frame late, somebody
who chose dark watches the app open white and then change its mind in
front of them — which reads as a bug rather than as a preference being
applied.

So the preference store is opened once in `main()` before `runApp`, the
same thing the demo session already does and for the same reason, and
every read after that is off the copy in memory.

## What happens when the device will not remember anything

A private window, a locked-down browser, a full disk. Every read and
write swallows the failure: the setting applies for that session and is
forgotten after it. It must never be the reason an app will not open.

## One race, closed deliberately

Riverpod re-runs the provider whenever the account stream emits —
including when it emits the *same* account, which a profile edit does.
Re-reading storage there would undo a choice made a moment earlier whose
write had not yet reached the disk, so the controller also keeps what
has been chosen this session, per account, and prefers it.

## Covered by tests

| Layer | File | Covers |
|---|---|---|
| Pure | `unit/core/theme_choice_test.dart` | each choice maps to a `ThemeMode` and is read back by name; anything unrecognised — including a value written by a newer build — falls back to following the device rather than refusing to start; every account gets its own slot, and signed-out has one that is nobody's |
| Pure | `unit/core/theme_choice_test.dart` (storage) | two accounts keep separate choices; a new account is not handed the last person's; the first frame may borrow the device's last choice; a device that remembers nothing still answers rather than throwing |
| Widget | `unit/core/theme_switch_test.dart` | the app actually changes brightness, not just the setting; all three are offered and the chosen one says what it means; the choice is written against the account that made it; it swaps with the account on a shared computer; it applies on the first pumped frame with no flash; it survives the account stream re-emitting; the cycling button names where it has got to and wraps round; a device that remembers nothing still switches |
| Smoke | `smoke/demo_app_boot_test.dart` | **every one of the ten portals opens in dark mode without throwing**, with an assertion that the theme really is dark so the test cannot pass while still light |

That last row is the one that matters most. Both themes existed long
before anything selected between them, so a hard-coded colour that reads
as invisible on a dark surface would have shipped and nothing would have
caught it.

The hard-coded colours that remain are deliberate and were checked: the
QR code keeps a white backing because a scanner needs the light modules
light, the branding screen keeps a white panel because a scanned
signature is black ink on paper, and the ID card renders its own fixed
palette because it is a card.
