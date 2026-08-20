import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../dashboard/presentation/widgets/recommended_list_tile.dart';
import 'search_by_profile_id_controller.dart';

class SearchByProfileIdScreen extends ConsumerStatefulWidget {
  const SearchByProfileIdScreen({super.key});

  @override
  ConsumerState<SearchByProfileIdScreen> createState() => _SearchByProfileIdScreenState();
}

class _SearchByProfileIdScreenState extends ConsumerState<SearchByProfileIdScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileIdSearchControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Search by Profile ID')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Every member has a unique Profile ID (e.g. VV482910) shown on their profile — enter it here to go straight to them.',
              style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Profile ID',
                hintText: 'VV482910',
              ),
              onSubmitted: (v) => ref.read(profileIdSearchControllerProvider.notifier).search(v),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Find',
              loading: state.loading,
              onPressed: () =>
                  ref.read(profileIdSearchControllerProvider.notifier).search(_controller.text),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (state.searched) _ResultArea(state: state),
          ],
        ),
      ),
    );
  }
}

class _ResultArea extends StatelessWidget {
  final ProfileIdSearchState state;
  const _ResultArea({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final result = state.result;
    if (result == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.accentSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            Icon(Icons.search_off_rounded, color: context.colors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('No member found with that Profile ID.',
                  style: context.textStyles.bodyMedium),
            ),
          ],
        ),
      );
    }
    return RecommendedListTile(
      profile: result,
      onTap: () => context.push(AppRoutes.profileDetailPath(result.id)),
    );
  }
}
