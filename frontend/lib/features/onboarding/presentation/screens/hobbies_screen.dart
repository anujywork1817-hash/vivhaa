import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../controllers/profile_creation_controller.dart';

// _requiredCount doubled as both "must pick at least this many to
// continue" AND the hard cap on how many could ever be picked — so once
// someone reached 5, every other chip simply stopped responding to taps,
// with nothing telling them why. Splitting these apart: _minRequired still
// gates Save & continue, _maxSelectable is a separate, higher ceiling that
// actually lets a member pick more.
const int _minRequired = 5;
const int _maxSelectable = 10;

const Map<String, List<(IconData, String)>> _categories = {
  'Creative': [
    (Icons.edit_rounded, 'Writing'),
    (Icons.coffee_rounded, 'Cooking'),
    (Icons.mic_rounded, 'Singing'),
    (Icons.camera_alt_rounded, 'Photography'),
    (Icons.music_note_rounded, 'Playing instruments'),
    (Icons.palette_rounded, 'Painting'),
    (Icons.content_cut_rounded, 'DIY crafts'),
    (Icons.nightlife_rounded, 'Dancing'),
    (Icons.theater_comedy_rounded, 'Acting'),
    (Icons.menu_book_rounded, 'Poetry'),
    (Icons.local_florist_rounded, 'Gardening'),
    (Icons.rss_feed_rounded, 'Blogging'),
    (Icons.article_rounded, 'Content creation'),
    (Icons.brush_rounded, 'Designing'),
    (Icons.draw_rounded, 'Doodling'),
  ],
  'Fun': [
    (Icons.movie_rounded, 'Movies'),
    (Icons.headphones_rounded, 'Music'),
    (Icons.card_travel_rounded, 'Travelling'),
    (Icons.menu_book_rounded, 'Reading'),
    (Icons.sports_basketball_rounded, 'Sports'),
    (Icons.public_rounded, 'Social media'),
    (Icons.sports_esports_rounded, 'Gaming'),
    (Icons.live_tv_rounded, 'Binge-watching'),
    (Icons.pedal_bike_rounded, 'Biking'),
    (Icons.celebration_rounded, 'Clubbing'),
    (Icons.shopping_bag_rounded, 'Shopping'),
    (Icons.theaters_rounded, 'Theater & Events'),
    (Icons.animation_rounded, 'Anime'),
    (Icons.emoji_people_rounded, 'Stand ups'),
  ],
  'Fitness': [
    (Icons.directions_run_rounded, 'Running'),
    (Icons.directions_bike_rounded, 'Cycling'),
    (Icons.self_improvement_rounded, 'Yoga & Meditation'),
    (Icons.directions_walk_rounded, 'Walking'),
    (Icons.fitness_center_rounded, 'Working out'),
    (Icons.terrain_rounded, 'Trekking'),
    (Icons.sports_gymnastics_rounded, 'Aerobics/Zumba'),
    (Icons.pool_rounded, 'Swimming'),
  ],
  'Other Interests': [
    (Icons.pets_rounded, 'Pets'),
    (Icons.restaurant_rounded, 'Foodie'),
    (Icons.eco_rounded, 'Vegan'),
    (Icons.newspaper_rounded, 'News & Politics'),
    (Icons.volunteer_activism_rounded, 'Social service'),
    (Icons.rocket_launch_rounded, 'Entrepreneurship'),
    (Icons.chair_rounded, 'Home decor'),
    (Icons.trending_up_rounded, 'Investments'),
    (Icons.checkroom_rounded, 'Fashion & beauty'),
  ],
};

class HobbiesScreen extends ConsumerWidget {
  /// True when opened on its own to edit hobbies later (e.g. from Home's
  /// "Complete your Profile" prompts) rather than as an onboarding step —
  /// saves and returns instead of continuing into the rest of the flow.
  final bool standalone;

  const HobbiesScreen({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(profileCreationControllerProvider.notifier);
    final draft = ref.watch(profileCreationControllerProvider).draft;
    final selected = draft.hobbies.toSet();
    final profileFor = draft.profileFor ?? ProfileFor.myself;

    void toggle(String hobby) {
      final updated = {...selected};
      if (updated.contains(hobby)) {
        updated.remove(hobby);
      } else if (updated.length < _maxSelectable) {
        updated.add(hobby);
      }
      controller.update((p) => p.copyWith(hobbies: updated.toList()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, size: 16, color: context.colors.accent),
            const SizedBox(width: 4),
            Text('Vivah', style: TextStyle(fontFamily: 'Georgia', color: context.colors.accent)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (!standalone)
            TextButton(
              onPressed: () => context.push(AppRoutes.familyDetails),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Now let's add ${profileFor.possessive}\nhobbies & interests",
                      style: context.textStyles.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Center(
                    child: Text('This will help find better Matches',
                        style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted)),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  for (final entry in _categories.entries) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: context.colors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: context.textStyles.titleMedium),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: entry.value.map((item) {
                              final isSelected = selected.contains(item.$2);
                              return ChoiceChip(
                                avatar: Icon(item.$1,
                                    size: 16,
                                    color: isSelected ? Colors.white : context.colors.accent),
                                label: Text(item.$2),
                                selected: isSelected,
                                onSelected: (_) => toggle(item.$2),
                                selectedColor: context.colors.accent,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : context.colors.ink,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                ),
                                side: BorderSide(
                                    color: isSelected ? context.colors.accent : context.colors.line),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xs),
            child: Text(
              selected.length < _minRequired
                  ? 'Pick at least $_minRequired to continue'
                  : 'Up to $_maxSelectable total',
              style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: PrimaryButton(
              // Tracks progress toward the actual ceiling once past the
              // minimum, rather than freezing at "/5" and reading like a
              // stuck counter the moment a 6th hobby gets picked.
              label: standalone
                  ? 'Save (${selected.length}/$_maxSelectable)'
                  : 'Save & continue (${selected.length}/$_maxSelectable)',
              onPressed: selected.length >= _minRequired
                  ? () async {
                      if (!standalone) {
                        context.push(AppRoutes.familyDetails);
                        return;
                      }
                      // Editing after onboarding — persist right away,
                      // since there's no later review step to submit for us.
                      final ok = await ref
                          .read(profileCreationControllerProvider.notifier)
                          .submit();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Hobbies updated.'
                            : 'Could not save. Please try again.'),
                      ));
                      if (ok) Navigator.of(context).pop();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
