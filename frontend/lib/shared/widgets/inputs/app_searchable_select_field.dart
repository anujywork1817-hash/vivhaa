import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// One option in a searchable picker: what the member sees versus what gets
/// stored. Countries display as `🇮🇳  India` but store `India`; states
/// display by name but carry the ISO code the city lookup needs.
class SelectOption {
  final String value;
  final String label;

  const SelectOption(this.value, [String? label]) : label = label ?? value;
}

/// [AppSelectField]'s bigger sibling: same bottom-sheet pattern, but with a
/// search box and support for lists too long to scroll.
///
/// Needed once the pickers stopped being hardcoded ten-item constants — a
/// country list is 250 entries and a single Indian state can hold over a
/// thousand cities.
class AppSearchableSelectField extends StatelessWidget {
  final String label;
  final String? value;
  final String hint;
  final List<SelectOption> options;
  final ValueChanged<SelectOption> onSelected;

  /// Disables the field, for a step that depends on an earlier one — city
  /// before a state is chosen, sub-caste before a community.
  final bool enabled;

  /// Shown in place of the list when [options] is empty and no search is
  /// running, e.g. "Select a state first".
  final String emptyMessage;

  /// True while [options] is still being fetched.
  final bool isLoading;

  /// Set when the fetch failed, so the sheet can offer a retry rather than
  /// looking like an empty list.
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Server-side search. When null the sheet filters [options] locally,
  /// which is right for anything that arrives as one complete list. City
  /// lookups pass this because the API caps an unfiltered listing.
  final Future<List<SelectOption>> Function(String query)? onSearch;

  const AppSearchableSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.hint = 'Select',
    this.enabled = true,
    this.emptyMessage = 'Nothing to choose from',
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onSearch,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<SelectOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SearchableSheet(
        label: label,
        value: value,
        options: options,
        emptyMessage: emptyMessage,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: onRetry,
        onSearch: onSearch,
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    // A disabled field still renders, greyed — hiding it entirely would make
    // the form jump around as earlier steps get answered.
    final foreground = !enabled
        ? context.colors.muted.withValues(alpha: 0.5)
        : value == null
            ? context.colors.muted
            : context.colors.ink;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => _open(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, enabled: enabled),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.keyboard_arrow_down_rounded, color: foreground),
          ],
        ),
      ),
    );
  }
}

class _SearchableSheet extends StatefulWidget {
  final String label;
  final String? value;
  final List<SelectOption> options;
  final String emptyMessage;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Future<List<SelectOption>> Function(String query)? onSearch;

  const _SearchableSheet({
    required this.label,
    required this.value,
    required this.options,
    required this.emptyMessage,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.onSearch,
  });

  @override
  State<_SearchableSheet> createState() => _SearchableSheetState();
}

class _SearchableSheetState extends State<_SearchableSheet> {
  final _searchController = TextEditingController();

  Timer? _debounce;
  List<SelectOption> _results = const [];
  bool _isSearching = false;

  /// Guards against a slow early request overwriting the results of a later
  /// one — type "del", then "delhi", and the "del" response must not win.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _results = widget.options;
  }

  @override
  void didUpdateWidget(_SearchableSheet old) {
    super.didUpdateWidget(old);
    if (old.options != widget.options && _searchController.text.isEmpty) {
      _results = widget.options;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();

    final search = widget.onSearch;
    if (search == null) {
      // Local filter: no request, so no debounce needed.
      final lower = query.trim().toLowerCase();
      setState(() {
        _results = lower.isEmpty
            ? widget.options
            : widget.options
                .where((o) => o.label.toLowerCase().contains(lower))
                .toList(growable: false);
      });
      return;
    }

    if (query.trim().isEmpty) {
      setState(() {
        _results = widget.options;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final id = ++_requestId;
      final found = await search(query.trim());
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = found;
        _isSearching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Leaves room for the keyboard, which otherwise covers the list the
    // member is typing into.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.md),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(widget.label, style: context.textStyles.headlineSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.label.toLowerCase()}',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _onQueryChanged('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.errorMessage != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        text: widget.errorMessage!,
        action: widget.onRetry == null
            ? null
            : TextButton(
                onPressed: () {
                  widget.onRetry!();
                  Navigator.of(context).pop();
                },
                child: const Text('Retry'),
              ),
      );
    }

    if (widget.isLoading || _isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return _Message(
        icon: Icons.search_off_rounded,
        text: _searchController.text.isEmpty
            ? widget.emptyMessage
            : 'No match for "${_searchController.text}"',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final option = _results[i];
        final isSelected = option.value == widget.value;
        return ListTile(
          title: Text(option.label),
          trailing:
              isSelected ? Icon(Icons.check_circle, color: context.colors.accent) : null,
          onTap: () => Navigator.of(context).pop(option),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: context.colors.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
            ),
            if (action != null) ...[const SizedBox(height: AppSpacing.sm), action!],
          ],
        ),
      ),
    );
  }
}
