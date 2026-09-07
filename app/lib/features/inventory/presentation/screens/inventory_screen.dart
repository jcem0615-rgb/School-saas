import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/combo_field.dart';
import '../../data/datasources/inventory_remote_datasource.dart';
import '../../domain/entities/inventory_item.dart';
import '../controllers/inventory_controller.dart';

final _dateFormat = DateFormat('d MMM y');

/// The stock room.
///
/// Two questions, and the screen is built around them: what is running
/// out, and where is the good projector. The first is a list at the top;
/// the second is the movement log, which is the record — the quantity on
/// each item is a running total kept alongside it, not a number anybody
/// types.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool _lowOnly = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final low = ref.watch(lowStockProvider);
    final held = ref.watch(outstandingIssuesProvider);

    ref.listen(inventoryActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showItemForm(context),
        icon: const Icon(Icons.add),
        label: const Text('New item'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load the stock: $error')),
        data: (items) {
          final visible = _lowOnly ? low : items;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (low.isNotEmpty)
                Card(
                  color: theme.colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.production_quantity_limits_outlined),
                    title: Text('${low.length} to reorder'),
                    subtitle: Text(
                      low.take(3).map((i) => i.name).join(', ') +
                          (low.length > 3 ? ' and more' : ''),
                    ),
                    trailing: Switch(
                      value: _lowOnly,
                      onChanged: (value) => setState(() => _lowOnly = value),
                    ),
                  ),
                ),

              if (held.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Out on issue', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                // The answer to "where is the good projector", netted so
                // somebody who took three and returned two shows as
                // holding one.
                for (final issue in held)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.output_outlined),
                    title: Text(issue.holder),
                    subtitle: Text(issue.itemName),
                    trailing: Text(_trim(issue.quantity)),
                  ),
              ],

              const SizedBox(height: 12),
              Text(_lowOnly ? 'Running out' : 'Everything', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),

              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    items.isEmpty
                        ? 'Nothing on file yet. Add what the stock room holds and '
                            'every movement in and out is recorded against it.'
                        : 'Nothing is below its reorder level.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                for (final item in visible) _ItemTile(item: item, onMove: _showMoveForm),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showItemForm(BuildContext context, {InventoryItem? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final category = TextEditingController(text: existing?.category ?? '');
    final unit = TextEditingController(text: existing?.unit ?? '');
    final reorder =
        TextEditingController(text: existing == null ? '' : _trim(existing.reorderLevel));
    final location = TextEditingController(text: existing?.location ?? '');

    final categories = (ref.read(inventoryItemsProvider).valueOrNull ?? [])
        .map((i) => i.category)
        .toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'New item' : 'Edit ${existing.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'What is it'),
              ),
              const SizedBox(height: 12),
              ComboField(
                controller: category,
                label: 'Category',
                suggestions: categories,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unit,
                decoration: const InputDecoration(
                  labelText: 'One of them is a…',
                  hintText: 'ream, box, piece, set',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reorder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tell me when it falls to',
                  hintText: 'Blank or 0 to never',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: 'Kept where (optional)'),
              ),
              if (existing != null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'The quantity is not edited here. It moves when a movement '
                    'is recorded, which is what makes it traceable.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await ref
                  .read(inventoryActionControllerProvider.notifier)
                  .saveItem(
                    itemId: existing?.id,
                    name: name.text,
                    category: category.text,
                    unit: unit.text,
                    reorderLevel: double.tryParse(reorder.text.trim()) ?? 0,
                    location: location.text,
                  );
              if (ok && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveForm(InventoryItem item) async {
    var kind = MovementKind.received;
    final quantity = TextEditingController();
    final issuedTo = TextEditingController();
    final reference = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(item.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.quantityLabel} on hand'),
                const SizedBox(height: 12),
                DropdownButtonFormField<MovementKind>(
                  initialValue: kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'What happened'),
                  items: [
                    for (final k in MovementKind.values)
                      DropdownMenuItem(value: k, child: Text(k.displayLabel)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  decoration: InputDecoration(
                    labelText: kind == MovementKind.adjusted
                        ? 'Difference, + or -'
                        : 'How many ${item.unit}',
                  ),
                ),
                if (kind.needsRecipient) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: issuedTo,
                    decoration: const InputDecoration(
                      labelText: 'To whom, or which room',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                    hintText: 'Delivery receipt, request number',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await ref
                    .read(inventoryActionControllerProvider.notifier)
                    .recordMovement(
                      item: item,
                      kind: kind,
                      quantity: double.tryParse(quantity.text.trim()) ?? 0,
                      issuedTo: issuedTo.text,
                      reference: reference.text,
                    );
                if (ok && dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  final InventoryItem item;
  final Future<void> Function(InventoryItem) onMove;

  const _ItemTile({required this.item, required this.onMove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final movements =
        ref.watch(inventoryMovementsProvider(item.id)).valueOrNull ??
            const <InventoryMovement>[];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: item.isLow ? theme.colorScheme.tertiary : theme.colorScheme.outlineVariant,
        ),
      ),
      child: ExpansionTile(
        title: Text(item.name),
        subtitle: Text(
          '${item.category}${item.location == null || item.location!.isEmpty ? '' : ' · ${item.location}'}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              item.quantityLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: item.isLow ? theme.colorScheme.tertiary : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.isLow)
              Text('reorder at ${_trim(item.reorderLevel)}',
                  style: theme.textTheme.bodySmall),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => onMove(item),
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Record a movement'),
                ),
              ],
            ),
          ),
          // The reconciliation, which had a function and no screen. The
          // running total is kept for the lists; the movements are the
          // record it is supposed to be derivable from, and the two
          // disagreeing is how a school finds out something wrote a
          // quantity without writing a movement. It should now be
          // impossible -- firestore.rules refuses a client write to the
          // count -- and a check that can only ever pass is still worth
          // showing, because it is the sentence that makes the figure
          // above it trustworthy rather than asserted.
          if (movements.isNotEmpty &&
              movements.length < InventoryRemoteDataSource.movementPageSize)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Builder(builder: (context) {
                final fromLog = stockFromMovements(movements);
                final agrees = (fromLog - item.quantityOnHand).abs() < 0.001;
                return Row(
                  children: [
                    Icon(
                      agrees ? Icons.check_circle_outline : Icons.error_outline,
                      size: 16,
                      color: agrees ? null : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        agrees
                            ? 'The ${movements.length} movements below add up to '
                                '${item.quantityLabel}.'
                            : 'The movements below add up to ${_trim(fromLog)}, not '
                                '${item.quantityLabel}. Something moved this count '
                                'without recording why.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: agrees ? null : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),

          if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Nothing recorded against this yet.'),
            )
          else
            for (final movement in movements.take(6))
              ListTile(
                dense: true,
                leading: Icon(_iconFor(movement.kind), size: 18),
                title: Text(
                  '${movement.kind.displayLabel} '
                  '${_trim(movement.quantity)} ${item.unit}'
                  '${movement.issuedTo == null ? '' : ' to ${movement.issuedTo}'}',
                ),
                subtitle: Text(
                  '${_dateFormat.format(movement.recordedAt)} · '
                  '${movement.recordedByName}'
                  '${movement.reference == null || movement.reference!.isEmpty ? '' : ' · ${movement.reference}'}',
                ),
              ),
        ],
      ),
    );
  }

  static IconData _iconFor(MovementKind kind) => switch (kind) {
        MovementKind.received => Icons.call_received,
        MovementKind.issued => Icons.call_made,
        MovementKind.returned => Icons.undo,
        MovementKind.adjusted => Icons.tune,
        MovementKind.writtenOff => Icons.delete_outline,
      };
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();
