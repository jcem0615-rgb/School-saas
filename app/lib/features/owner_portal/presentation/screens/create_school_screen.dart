import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/theme/glass.dart';
import '../../../../core/utils/validators.dart';
import '../../../../demo/demo_store.dart' show DemoStore;
import '../controllers/owner_controller.dart';

/// The Owner adding a school to the platform by hand.
///
/// This is the only way a school comes into existence -- there is no
/// sign-up flow, by design. The Owner takes the school on, then staffs it
/// with a Director, who staffs the rest.
class CreateSchoolScreen extends ConsumerStatefulWidget {
  const CreateSchoolScreen({super.key});

  @override
  ConsumerState<CreateSchoolScreen> createState() => _CreateSchoolScreenState();
}

class _CreateSchoolScreenState extends ConsumerState<CreateSchoolScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _schoolId = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _rate = TextEditingController(text: '50');

  /// Which divisions the school runs. Empty until the Owner says, and the
  /// form will not submit while it is: this is not a detail to be filled
  /// in later, it decides what the school's own registration form offers
  /// on the day after this one.
  final Set<EducationLevel> _levels = <EducationLevel>{};

  /// True once the Owner types an id themselves, after which the name
  /// stops driving it -- otherwise their edit would be overwritten on the
  /// next keystroke in the name field.
  bool _idEdited = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_idEdited) return;
      final slug = DemoStore.slugify(_name.text);
      if (slug != _schoolId.text) {
        _schoolId.value = TextEditingValue(
          text: slug,
          selection: TextSelection.collapsed(offset: slug.length),
        );
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _schoolId, _address, _email, _phone, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final id = await ref.read(createSchoolControllerProvider.notifier).create(
          name: _name.text.trim(),
          billingRatePerStudent: double.parse(_rate.text.trim()),
          educationLevels: _levels,
          schoolId: _schoolId.text.trim(),
          addressLine: _address.text.trim(),
          contactEmail: _email.text.trim(),
          contactPhone: _phone.text.trim(),
        );

    if (!mounted || id == null) return;
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createSchoolControllerProvider);
    final busy = state.isLoading;

    ref.listen(createSchoolControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Add School')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GlassSurface(
            radius: 24,
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'School name',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'The school needs a name.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _schoolId,
                    onChanged: (_) => _idEdited = true,
                    decoration: const InputDecoration(
                      labelText: 'School ID',
                      prefixIcon: Icon(Icons.tag),
                      helperText: 'Permanent. Every account here is scoped to it.',
                    ),
                    validator: (v) {
                      final id = v?.trim() ?? '';
                      if (id.isEmpty) return 'An ID is required.';
                      // Matches SCHOOL_ID_PATTERN in the callable, so the
                      // form refuses what the server would refuse anyway,
                      // before a round trip.
                      if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(id)) {
                        return 'Lowercase letters, digits and single hyphens.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _LevelsField(
                    selected: _levels,
                    onToggle: (level, on) => setState(() {
                      if (on) {
                        _levels.add(level);
                      } else {
                        _levels.remove(level);
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Billing rate per student',
                      prefixIcon: Icon(Icons.payments_outlined),
                      prefixText: '₱ ',
                      helperText: 'Charged per active student, per cycle.',
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null) return 'Enter an amount.';
                      if (n < 0) return 'It cannot be negative.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Contact email (optional)',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? null : Validators.email(v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact phone (optional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create school'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The school starts active with no students. Add its '
                    'Director next so somebody can run it.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four divisions, as chips, with the phrase they add up to
/// underneath.
///
/// A [FormField] rather than a bare [Wrap] so an empty selection is
/// refused by the same `validate()` call as an empty name, and shows its
/// error in the same place -- rather than the Owner pressing Create and
/// being told by the server, one round trip later.
class _LevelsField extends StatelessWidget {
  final Set<EducationLevel> selected;
  final void Function(EducationLevel level, bool on) onToggle;

  const _LevelsField({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormField<Set<EducationLevel>>(
      initialValue: selected,
      // Without this the "pick at least one" error stays on screen after
      // the Owner picks one, until they press Create again -- the field
      // telling them off for something they have just fixed.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Pick at least one level.' : null,
      builder: (field) {
        // The chips write to the parent's set, not to the field's own
        // value, so the field is told about the change explicitly --
        // otherwise it validates against the selection as it was when
        // this widget was built.
        void toggle(EducationLevel level, bool on) {
          onToggle(level, on);
          field.didChange(selected);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Levels offered', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in EducationLevel.values)
                  FilterChip(
                    label: Text(level.displayLabel),
                    selected: selected.contains(level),
                    onSelected: (on) => toggle(level, on),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selected.isEmpty
                  ? 'Elementary, Junior High, Senior High, College -- any '
                      'combination. Pick every one this school runs.'
                  : educationCoverageLabel(selected),
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                fontWeight: selected.isEmpty ? null : FontWeight.w600,
              ),
            ),
            if (field.hasError) ...[
              const SizedBox(height: 6),
              Text(
                field.errorText!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }
}
