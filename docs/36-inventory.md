# Module 36 — Inventory

`FirestorePaths` has declared `inventory` and `inventoryTransactions`
since the Admin portal landed, with nothing behind them, and the Admin
dashboard's own header comment said Inventory was "explicitly deferred".
Three modules later, this is it.

It answers two questions, and the screen is built around them: **what is
running out**, and **where is the good projector**.

## The log is the record

The quantity on an item is a running total. It is never typed — it moves
when a movement is recorded, in the same Firestore transaction that
writes the movement, and `stockFromMovements` recomputes it from the log
so a drift is detectable rather than invisible.

That is the whole design. A stock figure nobody can trace back to a
movement is the spreadsheet this module replaces, and an item whose
quantity could be edited directly would be exactly that with a nicer
font. The rules make it stick: `inventoryTransactions` is create-only,
with `update` and `delete` denied to everybody.

### Where that is enforced

**On the server.** `recordInventoryMovement` reads the item, checks the
result, and writes the movement and the new total in one transaction —
and firestore.rules refuses any client write to `quantityOnHand`, so a
count can only move by a movement.

Both halves of that used to be wrong, and each contradicted a comment
sitting beside it.

The transaction was a client one. It read the item inside the
transaction, which was the right instinct, and then checked nothing
against what it read: the "would this go below zero" test lived in the
use case, on the device, against the copy of the item the screen was
holding. Two people issuing the last two projectors at the same moment
both passed it and the shelf went to -2 — the exact case the comment
above the transaction said it existed to prevent.

And the rules said `allow write` for the three roles that keep the room,
which is create, update *and* delete with no field guard. Any of them
could set `quantityOnHand` to whatever they liked with no movement behind
it, and could hard-delete an item the log still referred to — while the
code that deletes has always soft-deleted, with a comment saying the
rules denied the other kind. Nothing tested either, which is why both
survived.

The use case still checks below-zero before the round trip, and says so
in its own comment: it buys a message a moment earlier, and it is not the
guarantee.

Each movement also stores `quantityBefore` and `quantityAfter`, so the
log alone can be replayed and checked without joining back to the item.

## Five kinds of movement

| | Effect |
| --- | --- |
| Received | in — a delivery, a donation |
| Issued | out — to a person or a room |
| Returned | in — the projector came back |
| Stock count | either — the shelf disagreed with the books |
| Written off | out — broken, lost, expired |

A stock count is the one kind whose quantity carries its own sign,
because it is the only one where "minus three" is a real thing to
record. Every other movement is refused at zero or below: use a count to
correct a figure downwards, so the correction says it was a correction.

**Going below zero is refused**, not allowed and flagged. A negative
stock figure is always wrong — either the movement is a mistake or the
shelf was already wrong — and both want somebody to stop and count
rather than a number that cannot be true.

**An issue needs a name.** "Where is the good projector" is the question,
and a movement out with nobody on it leaves the same shrug the logbook
did. Issues and returns net per person per item, so somebody who took
three chairs and brought two back shows as holding one, not two rows
that have to be read together — and anybody who has returned everything
drops off the list rather than sitting there to be mentally filtered.

The netting keys on the item's **id**. It used to key on `who|itemName`,
which had two failure modes: renaming "Projector" to "Projector (Epson)"
split whoever was holding one across two rows that each looked like a
different loan and never cancelled each other, and a recipient or item
name containing the separator could be read as somebody else's row. The
label shows the name the item was last moved under, since nobody in the
stock room calls it the old thing any more.

## What is running out

Sorted by how far below the reorder level, not alphabetically. The thing
that ran out entirely matters more than the thing with two left, and an
alphabetical list buries it.

A reorder level of zero means the school does not track one for that
item — not that it needs reordering the moment it is empty.

## Units

Every quantity is printed with its unit, because "12" of an unstated
thing is not information, and the item form refuses to save without one.
The pluraliser is deliberately small: it handles the sibilant endings
that take *-es* and the *-y* that becomes *-ies*, leaves anything already
ending in *s* alone (so "scissors" survives), and would get "bus" wrong.
Nobody stocks buses by the ream.

## Where it meets the rest

Material requests already existed as generic approvals
([Module 6](06-director-portal.md)) — Faculty and Staff file them,
Director and Admin decide them. This is the stock those requests draw
down, which is why the tile sits beside them on the Staff dashboard: the
person deciding a request is the person who knows whether there is any
left. A movement's `reference` field is where the request number goes.

## A quantity that is not a number

`double.tryParse('NaN')` returns NaN and `'1e400'` returns Infinity, and
every guard on the quantity was a comparison — `quantity <= 0` for a
movement, `quantity == 0` for a stock count. Both are false for NaN, so
one word typed into the quantity box went straight into the running
total, where it is permanent: everything added to NaN stays NaN, and the
item reads "NaN reams" until somebody rebuilds the document by hand.

Checked with `isFinite` now, on both sides, before any comparison runs.
A total that somehow already holds one is read as zero rather than
spread further.

## Rules

Readable tenant-wide. A teacher wanting to know whether there is chalk
before walking down there is the point, and there is nothing sensitive in
forty reams of bond paper.

Staff, Director and Admin edit what an item **is** — its name, unit,
reorder level, where it is kept. Not faculty, who read it every day; the
request path is how they draw stock, and that already exists.

Nobody, at any role, writes `quantityOnHand` or a movement. A new item is
created at zero and the first delivery is a movement like any other,
which is what makes the opening figure traceable rather than asserted.
Deleting an item is denied outright — removing it from the shelves is
`isDeleted`, which is an update.

## Where things are

| Thing | File |
| --- | --- |
| **The transaction that moves both** | `functions/src/callable/inventory/recordInventoryMovement.ts` |
| Kinds, effects, validation, reconciliation | `functions/src/shared/inventory/movement.ts` |
| Movements, stock, low stock, who holds what | `inventory/domain/entities/inventory_item.dart` |
| The check before the round trip | `inventory/domain/usecases/inventory_usecases.dart` |
| The screen | `inventory/presentation/screens/inventory_screen.dart` |
| Firestore | `schools/{id}/inventory/{itemId}`, `inventoryTransactions/{id}` |

Tests: `functions/test/shared/inventory/` (pure),
`functions/test/shared/inventory-emulator/` (the callable against a real
Firestore, including six hands reaching for one projector at once),
`test-rules/inventory.rules.test.ts`, and the Dart copies under
`app/test/unit/features/inventory/` and `app/test/smoke/inventory_stock_test.dart`.
