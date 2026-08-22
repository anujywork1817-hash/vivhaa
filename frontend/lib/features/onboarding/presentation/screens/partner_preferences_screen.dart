import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/partner_preferences.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../reference/data/reference_models.dart';
import '../../../reference/presentation/reference_providers.dart';
import '../../data/api_preferences_repository.dart';
import '../controllers/profile_creation_controller.dart';

const _motherTongueOptions = [
  'Hindi',
  'English',
  'Marathi',
  'Tamil',
  'Gujarati',
  'Open to All'
];
const _openToAll = 'Open to All';

const _maritalOptions = ['Never Married', 'Divorced', 'Widowed', 'Open to All'];
const _qualificationOptions = [
  "Bachelor's Degree",
  "Master's Degree",
  'MBA',
  'PhD',
  'Open to All'
];
const _workingWithOptions = [
  'Private Company',
  'Government / Public Sector',
  'Business / Self Employed',
  'Open to All'
];
const _professionOptions = [
  'Software Engineer',
  'Doctor',
  'Chartered Accountant',
  'Teacher',
  'Open to All'
];
const _incomeOptions = [
  'INR below 1 Lakh',
  'INR 1–5 Lakh',
  'INR 5–10 Lakh',
  'INR 10–20 Lakh',
  'Open to All'
];
const _managedByOptions = [
  'Self',
  'Parent',
  'Sibling',
  'Relative',
  'Friend',
  'Open to All'
];
const _dietOptions = [
  'Veg',
  'Non-Veg',
  'Eggetarian',
  'Jain',
  'Vegan',
  'Open to All'
];

/// A pre-filled, editable summary rather than a form from scratch — every
/// value is derived from the profile just built, and tapping a row opens
/// a small sheet to override it.
class PartnerPreferencesScreen extends ConsumerStatefulWidget {
  /// True when reached from the menu as a standalone settings screen
  /// rather than as an onboarding step — changes what "Confirm & Continue"
  /// does next (just pop back, instead of continuing onboarding).
  final bool standalone;

  const PartnerPreferencesScreen({super.key, this.standalone = false});

  @override
  ConsumerState<PartnerPreferencesScreen> createState() =>
      _PartnerPreferencesScreenState();
}

class _PartnerPreferencesScreenState
    extends ConsumerState<PartnerPreferencesScreen> {
  bool _expanded = false;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    // Deferred a frame — Riverpod disallows modifying a provider
    // synchronously while the widget tree (including this screen's own
    // build, which watches that same provider) is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedIfNeeded());
  }

  void _seedIfNeeded() {
    if (_seeded) return;
    _seeded = true;
    final draft = ref.read(profileCreationControllerProvider).draft;
    final prefs = draft.partnerPreferences;
    if (prefs.ageMin != null)
      return; // already has values (e.g. coming back to this screen)
    final age = draft.age ?? 25;
    final height = draft.heightCm ?? 165;
    ref
        .read(profileCreationControllerProvider.notifier)
        .updatePartnerPreferences((_) => PartnerPreferences(
              ageMin: (age - 3).clamp(18, 65),
              ageMax: (age + 4).clamp(18, 65),
              heightMinCm: (height - 15).clamp(122, 213),
              heightMaxCm: (height + 10).clamp(122, 213),
              maritalStatuses: const ['Never Married'],
              religions: draft.religion != null ? [draft.religion!] : const [],
              communities: const [],
              motherTongues: const [],
              country: draft.country,
              state: null,
              highestQualification: null,
              workingWith: null,
              profession: null,
              incomeMin: null,
              profileManagedBy: 'Self',
              diet: null,
            ));
  }

  Future<void> _editRange({
    required String title,
    required double min,
    required double max,
    required double startValue,
    required double endValue,
    required String Function(double) formatValue,
    required void Function(double start, double end) onSave,
  }) async {
    var values = RangeValues(startValue, endValue);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sheetContext.textStyles.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                    '${formatValue(values.start)} – ${formatValue(values.end)}',
                    style: sheetContext.textStyles.bodyMedium),
                RangeSlider(
                  values: values,
                  min: min,
                  max: max,
                  onChanged: (v) => setSheetState(() => values = v),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Save',
                  onPressed: () {
                    onSave(values.start, values.end);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editSingle({
    required String title,
    required List<String> options,
    required String? value,
    required void Function(String) onSave,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(title, style: sheetContext.textStyles.headlineSmall),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options
                    .map((o) => ListTile(
                          title: Text(o),
                          trailing: o == value
                              ? Icon(Icons.check_circle,
                                  color: sheetContext.colors.accent)
                              : null,
                          onTap: () => Navigator.of(sheetContext).pop(o),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) onSave(selected);
  }

  /// True while the profile is being created, so "Confirm & Continue" can't
  /// be tapped twice into two POSTs.
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final controller = ref.read(profileCreationControllerProvider.notifier);
    final prefs =
        ref.read(profileCreationControllerProvider).draft.partnerPreferences;

    // This is the last step that collects profile data, so it's where the
    // draft becomes a real backend profile.
    //
    // It used to happen two screens later, on the premium paywall — which
    // left Connect Matches asking /matches/recommended for a profile that
    // did not exist yet. That endpoint answers 400 profile_required, so
    // every new member saw "Could not load suggested matches", every time.
    // Submitting here also means the recommendations are scored against a
    // real profile rather than being a generic list.
    //
    // Standalone (editing from the menu) skips it: that profile is already
    // on the backend and only the preferences are being changed.
    var profileSaved = true;
    if (!widget.standalone) {
      profileSaved = await controller.submit();
    }

    await ref.read(preferencesRepositoryProvider).upsert(prefs);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (widget.standalone) {
      Navigator.of(context).pop();
      return;
    }

    // Onboarding still continues on failure — Connect Matches degrades to
    // its "you can still continue" state — but say so rather than letting
    // the next screen look inexplicably broken.
    if (!profileSaved) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
            "Couldn't save your profile just yet — we'll retry as you continue."),
      ));
    }
    context.push(AppRoutes.connectMatches);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final prefs = draft.partnerPreferences;
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    // These lists were hardcoded constants that never varied — six religions,
    // and a community list of Hindu castes shown no matter which religion was
    // picked. They come from /reference/* now, and cascade the same way the
    // profile-side pickers do.
    final religions =
        ref.watch(religionsProvider).valueOrNull ?? const <RefReligion>[];
    final chosenReligion =
        prefs.religions.isEmpty ? null : prefs.religions.first;

    final religionOptions = <String>[
      _openToAll,
      for (final r in religions) r.name
    ];

    // With no religion chosen the preference really is "any", so offer every
    // community rather than an empty list the member can't get past.
    final communityOptions = <String>[
      _openToAll,
      ...{
        for (final r in religions)
          if (chosenReligion == null || r.name == chosenReligion)
            for (final c in r.communities) c.name,
      }.toList()
        ..sort(),
    ];

    final countries =
        ref.watch(countriesProvider).valueOrNull ?? const <RefCountry>[];
    final countryOptions = <String>[
      _openToAll,
      for (final c in countries) c.name
    ];

    final countryCode = _codeForCountry(countries, prefs.country);
    final states = countryCode == null
        ? const <RefState>[]
        : (ref.watch(statesProvider(countryCode)).valueOrNull ??
            const <RefState>[]);
    final stateOptions = <String>[_openToAll, for (final st in states) st.name];

    void updatePrefs(PartnerPreferences Function(PartnerPreferences) fn) =>
        controller.updatePartnerPreferences(fn);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded,
                size: 16, color: context.colors.accent),
            const SizedBox(width: 4),
            Text('Vivah',
                style: TextStyle(
                    fontFamily: 'Georgia', color: context.colors.accent)),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recommended Partner Preferences',
                      style: context.textStyles.headlineMedium,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(
                      'We have set these Preferences to show you the best Matches for ${profileFor.possessive} Profile.',
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.colors.muted)),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text('Tap on the field to edit',
                        style: context.textStyles.bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _PrefCard(
                      title: 'Basic Details',
                      color: context.colors.success,
                      rows: [
                        _PrefRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Age Range',
                          value:
                              '${prefs.ageMin ?? 21} to ${prefs.ageMax ?? 35}',
                          onTap: () => _editRange(
                            title: 'Age Range',
                            min: 18,
                            max: 65,
                            startValue: (prefs.ageMin ?? 21).toDouble(),
                            endValue: (prefs.ageMax ?? 35).toDouble(),
                            formatValue: (v) => '${v.round()} yrs',
                            onSave: (s, e) => updatePrefs((p) => p.copyWith(
                                ageMin: s.round(), ageMax: e.round())),
                          ),
                        ),
                        _PrefRow(
                          icon: Icons.height_rounded,
                          label: 'Height Range',
                          value:
                              '${_heightLabel(prefs.heightMinCm)} to ${_heightLabel(prefs.heightMaxCm)}',
                          onTap: () => _editRange(
                            title: 'Height Range',
                            min: 122,
                            max: 213,
                            startValue: (prefs.heightMinCm ?? 150).toDouble(),
                            endValue: (prefs.heightMaxCm ?? 180).toDouble(),
                            formatValue: (v) => _heightLabel(v.round()),
                            onSave: (s, e) => updatePrefs((p) => p.copyWith(
                                heightMinCm: s.round(),
                                heightMaxCm: e.round())),
                          ),
                        ),
                        _PrefRow(
                          icon: Icons.groups_rounded,
                          label: 'Marital Status',
                          value: prefs.maritalStatuses.isEmpty
                              ? 'Open to All'
                              : prefs.maritalStatuses.join(', '),
                          onTap: () => _editSingle(
                            title: 'Marital Status',
                            options: _maritalOptions,
                            value: prefs.maritalStatuses.isEmpty
                                ? null
                                : prefs.maritalStatuses.first,
                            onSave: (v) => updatePrefs((p) => p.copyWith(
                                maritalStatuses:
                                    v == 'Open to All' ? [] : [v])),
                          ),
                        ),
                      ]),
                  _PrefCard(
                      title: 'Community',
                      color: context.colors.warning,
                      rows: [
                        _PrefRow(
                          icon: Icons.menu_book_rounded,
                          label: 'Religion',
                          value: prefs.religions.isEmpty
                              ? 'Open to All'
                              : prefs.religions.join(', '),
                          onTap: () => _editSingle(
                            title: 'Religion',
                            options: religionOptions,
                            value: prefs.religions.isEmpty
                                ? null
                                : prefs.religions.first,
                            // Communities belong to a religion, so a change here
                            // clears the one below rather than leaving e.g.
                            // "Brahmin" sitting under Muslim.
                            onSave: (v) => updatePrefs((p) => p.copyWith(
                                  religions: v == _openToAll ? [] : [v],
                                  communities: [],
                                )),
                          ),
                        ),
                        _PrefRow(
                          icon: Icons.diversity_3_rounded,
                          label: 'Community',
                          value: prefs.communities.isEmpty
                              ? 'Open to All'
                              : prefs.communities.join(', '),
                          onTap: () => _editSingle(
                            title: 'Community',
                            options: communityOptions,
                            value: prefs.communities.isEmpty
                                ? null
                                : prefs.communities.first,
                            onSave: (v) => updatePrefs((p) => p.copyWith(
                                communities: v == _openToAll ? [] : [v])),
                          ),
                        ),
                        _PrefRow(
                          icon: Icons.translate_rounded,
                          label: 'Mother Tongue',
                          value: prefs.motherTongues.isEmpty
                              ? 'Open to All'
                              : prefs.motherTongues.join(', '),
                          onTap: () => _editSingle(
                            title: 'Mother Tongue',
                            options: _motherTongueOptions,
                            value: prefs.motherTongues.isEmpty
                                ? null
                                : prefs.motherTongues.first,
                            onSave: (v) => updatePrefs((p) => p.copyWith(
                                motherTongues: v == 'Open to All' ? [] : [v])),
                          ),
                        ),
                      ]),
                  if (_expanded) ...[
                    _PrefCard(
                        title: 'Location',
                        color: context.colors.accent,
                        rows: [
                          _PrefRow(
                            icon: Icons.public_rounded,
                            label: 'Country living in',
                            value: prefs.country ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Country living in',
                              options: countryOptions,
                              value: prefs.country,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                    country: v == _openToAll ? null : v,
                                    clearCountry: v == _openToAll,
                                    clearState: true,
                                  )),
                            ),
                          ),
                          _PrefRow(
                            icon: Icons.location_on_rounded,
                            label: 'State living in',
                            value: prefs.state ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'State living in',
                              options: stateOptions,
                              value: prefs.state,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                    state: v == _openToAll ? null : v,
                                    clearState: v == _openToAll,
                                  )),
                            ),
                          ),
                        ]),
                    _PrefCard(
                        title: 'Education & Career',
                        color: context.colors.gold,
                        rows: [
                          _PrefRow(
                            icon: Icons.school_rounded,
                            label: 'Qualification',
                            value: prefs.highestQualification ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Qualification',
                              options: _qualificationOptions,
                              value: prefs.highestQualification,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                  highestQualification:
                                      v == 'Open to All' ? null : v)),
                            ),
                          ),
                          _PrefRow(
                            icon: Icons.apartment_rounded,
                            label: 'Working with',
                            value: prefs.workingWith ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Working with',
                              options: _workingWithOptions,
                              value: prefs.workingWith,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                  workingWith: v == 'Open to All' ? null : v)),
                            ),
                          ),
                          _PrefRow(
                            icon: Icons.work_rounded,
                            label: 'Profession',
                            value: prefs.profession ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Profession',
                              options: _professionOptions,
                              value: prefs.profession,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                  profession: v == 'Open to All' ? null : v)),
                            ),
                          ),
                          _PrefRow(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Annual Income',
                            value: prefs.incomeMin ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Annual Income',
                              options: _incomeOptions,
                              value: prefs.incomeMin,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                  incomeMin: v == 'Open to All' ? null : v)),
                            ),
                          ),
                        ]),
                    _PrefCard(
                        title: 'Other Details',
                        color: context.colors.muted,
                        rows: [
                          _PrefRow(
                            icon: Icons.person_rounded,
                            label: 'Profile Managed by',
                            value: prefs.profileManagedBy ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Profile Managed by',
                              options: _managedByOptions,
                              value: prefs.profileManagedBy,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                  profileManagedBy:
                                      v == 'Open to All' ? null : v)),
                            ),
                          ),
                          _PrefRow(
                            icon: Icons.restaurant_menu_rounded,
                            label: 'Diet',
                            value: prefs.diet ?? 'Open to All',
                            onTap: () => _editSingle(
                              title: 'Diet',
                              options: _dietOptions,
                              value: prefs.diet,
                              onSave: (v) => updatePrefs((p) => p.copyWith(
                                  diet: v == 'Open to All' ? null : v)),
                            ),
                          ),
                        ]),
                  ],
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(_expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded),
                      label: Text(_expanded ? 'Less' : 'More'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: PrimaryButton(
              label: 'Confirm & Continue',
              loading: _submitting,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }

  String _heightLabel(int? cm) {
    if (cm == null) return '—';
    final totalInches = (cm / 2.54).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return "$feet' $inches\"";
  }
}

class _PrefCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<_PrefRow> rows;
  const _PrefCard(
      {required this.title, required this.color, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows) row,
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _PrefRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: context.colors.accentSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: context.colors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.textStyles.bodySmall),
                  Text(value, style: context.textStyles.bodyLarge),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

/// Partner preferences store a country by name; the states endpoint is keyed
/// by ISO code, so resolve one from the other. Null until the country list
/// has loaded, which leaves the state picker showing just "Open to All".
String? _codeForCountry(List<RefCountry> countries, String? name) {
  if (name == null) return null;
  for (final c in countries) {
    if (c.name == name) return c.code;
  }
  return null;
}
