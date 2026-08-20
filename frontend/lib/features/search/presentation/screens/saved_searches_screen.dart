import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/saved_search.dart';
import '../../../../shared/models/search_filters.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../controllers/saved_searches_controller.dart';
import '../controllers/search_filters_controller.dart';
import '../controllers/search_results_controller.dart';

class SavedSearchesScreen extends ConsumerWidget {
  const SavedSearchesScreen({super.key});

  String _summarize(SearchFilters f) {
    final parts = <String>[
      '${f.ageMin}-${f.ageMax} yrs',
      if (f.religions.isNotEmpty) f.religions.join(', '),
      if (f.city != null) f.city!,
      if (f.communities.isNotEmpty) f.communities.join(', '),
    ];
    return parts.join(' · ');
  }

  Future<void> _rerun(BuildContext context, WidgetRef ref, SavedSearch saved) async {
    ref.read(searchFiltersProvider.notifier).update((_) => saved.filters);
    await ref.read(searchResultsControllerProvider.notifier).runSearch(saved.filters);
    if (context.mounted) context.push(AppRoutes.searchResults);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedSearchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Searches')),
      body: async.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, __) => ShimmerBox(
              width: double.infinity, height: 84, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        ),
        error: (e, st) => ErrorStateView(
          failure: e is AppFailure ? e : AppFailure.unknown(e.toString()),
          onRetry: () => ref.invalidate(savedSearchesProvider),
        ),
        data: (searches) {
          if (searches.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'No saved searches',
              message: 'Save a search from your results to quickly run it again later.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: searches.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) {
              final saved = searches[i];
              return Dismissible(
                key: ValueKey(saved.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: context.colors.danger,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                ),
                onDismissed: (_) => ref.read(savedSearchActionsProvider).delete(saved.id),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  onTap: () => _rerun(context, ref, saved),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: context.colors.line),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.accentSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.bookmark_rounded, color: context.colors.accent, size: 20),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(saved.name,
                                  style: context.textStyles.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text(_summarize(saved.filters),
                                  style: context.textStyles.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text('${saved.resultCount} results',
                                  style: context.textStyles.bodySmall
                                      ?.copyWith(color: context.colors.accent),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.colors.muted),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
