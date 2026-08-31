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

The transaction reads the item **inside** it rather than trusting the
copy the screen is holding. Two people issuing the last two projectors
at once should not both succeed against a count they each read a moment
earlier.

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

## Rules

Readable tenant-wide. A teacher wanting to know whether there is chalk
before walking down there is the point, and there is nothing sensitive in
forty reams of bond paper.

Writable by Staff, who run the stock room, plus Director and Admin, who
own what the school buys. Not faculty, who read it every day — the
request path is how they draw stock, and that already exists.

## Where things are

| Thing | File |
| --- | --- |
| Movements, stock, low stock, who holds what | `inventory/domain/entities/inventory_item.dart` |
| Validation | `inventory/domain/usecases/inventory_usecases.dart` |
| The transaction that moves both | `inventory/data/datasources/inventory_remote_datasource.dart` |
| The screen | `inventory/presentation/screens/inventory_screen.dart` |
| Firestore | `schools/{id}/inventory/{itemId}`, `inventoryTransactions/{id}` |
