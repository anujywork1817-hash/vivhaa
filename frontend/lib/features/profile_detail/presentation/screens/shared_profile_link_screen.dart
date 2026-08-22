import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../search/data/api_search_repository.dart';

/// Where an incoming shared-profile deep link (/p/:code — see
/// core/config/deep_link_config.dart) lands: resolves the human-readable
/// code to the profile's real ID via the same lookup "Search by Profile
/// ID" already uses, then hands off to the normal profile detail screen.
/// A dead/expired code shows a plain error rather than a blank screen.
class SharedProfileLinkScreen extends ConsumerStatefulWidget {
  final String code;
  const SharedProfileLinkScreen({super.key, required this.code});

  @override
  ConsumerState<SharedProfileLinkScreen> createState() => _SharedProfileLinkScreenState();
}

class _SharedProfileLinkScreenState extends ConsumerState<SharedProfileLinkScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final result = await ref.read(searchRepositoryProvider).findByProfileId(widget.code);
    if (!mounted) return;
    result.when(
      success: (profile) {
        if (profile == null) {
          setState(() => _error = 'This profile link is no longer valid.');
          return;
        }
        context.replace(AppRoutes.profileDetailPath(profile.id));
      },
      failure: (f) => setState(() => _error = f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, size: 40),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _resolve();
                  },
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
