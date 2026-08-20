import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/feedback/empty_state.dart';
import '../../../../shared/widgets/feedback/error_state.dart';
import '../../../../shared/widgets/feedback/shimmer_box.dart';
import '../../../dashboard/presentation/widgets/match_card.dart';
import '../../../dashboard/presentation/widgets/recommended_list_tile.dart';
import '../controllers/saved_searches_controller.dart';
import '../controllers/search_results_controller.dart';
import '../widgets/sort_filter_sheet.dart';

enum _ResultLayout { grid, list }

class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  _ResultLayout _layout = _ResultLayout.list;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(searchResultsControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _saveSearch() async {
    final state = ref.read(searchResultsControllerProvider);
    final filters = state.appliedFilters;
    if (filters == null) return;
    final nameController = TextEditingController(text: 'My search ${DateTime.now().day}/${DateTime.now().month}');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save this search'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await ref
        .read(savedSearchActionsProvider)
        .save(name, filters, state.results.length);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "$name"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchResultsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.loading ? 'Searching…' : '${state.results.length} results'),
        actions: [
          IconButton(
            icon: Icon(_layout == _ResultLayout.list ? Icons.grid_view_rounded : Icons.view_list_rounded),
            tooltip: 'Toggle layout',
            onPressed: () => setState(() {
              _layout = _layout == _ResultLayout.list ? _ResultLayout.grid : _ResultLayout.list;
            }),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Save search',
            onPressed: state.appliedFilters == null ? null : _saveSearch,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Sort & filter',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const SortFilterSheet(),
            ),
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(SearchResultsState state) {
    if (!state.hasSearched) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Start a search',
        message: 'Set your filters on Basic or Advanced Search to see matches here.',
      );
    }
    if (state.loading) {
      return _layout == _ResultLayout.grid ? _gridShimmer() : _listShimmer();
    }
    if (state.failure != null && state.results.isEmpty) {
      return ErrorStateView(
        failure: state.failure!,
        onRetry: () => ref.read(searchResultsControllerProvider.notifier).retry(),
      );
    }
    if (state.results.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_rounded,
        title: 'No matches found',
        message: 'Try widening your age or height range, or clearing a few filters.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(searchResultsControllerProvider.notifier).retry(),
      child: _layout == _ResultLayout.grid ? _grid(state) : _list(state),
    );
  }

  Widget _grid(SearchResultsState state) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.68,
      ),
      itemCount: state.results.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= state.results.length) return const _LoadMoreIndicator();
        final profile = state.results[i];
        return MatchCard(
          profile: profile,
          onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
        );
      },
    );
  }

  Widget _list(SearchResultsState state) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: state.results.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        if (i >= state.results.length) return const _LoadMoreIndicator();
        final profile = state.results[i];
        return RecommendedListTile(
          profile: profile,
          onTap: () => context.push(AppRoutes.profileDetailPath(profile.id)),
        );
      },
    );
  }

  Widget _gridShimmer() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.68,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => ShimmerBox(
          width: double.infinity, height: double.infinity, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
    );
  }

  Widget _listShimmer() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, __) => ShimmerBox(
          width: double.infinity, height: 76, borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
    );
  }
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: context.colors.accent),
        ),
      ),
    );
  }
}
