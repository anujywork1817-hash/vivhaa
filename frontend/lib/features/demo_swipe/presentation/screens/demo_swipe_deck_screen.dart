import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/match_profile.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/demo_swipe_controller.dart';

/// The free "hook" swipe deck — the fixed 10 male + 10 female demo
/// profiles every user sees right after onboarding, before the ₹1 unlock
/// paywall. Modeled closely on
/// features/discover_matches/presentation/screens/discover_screen.dart's
/// card-swipe UI (drag left/right or the buttons); swipes are tracked
/// locally only, and once the deck is exhausted this hands off to the
/// unlock paywall automatically rather than home — there is no "skip the
/// paywall" path from here.
class DemoSwipeDeckScreen extends ConsumerWidget {
  const DemoSwipeDeckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoSwipeControllerProvider);

    if (!state.loading && state.isExhausted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.unlockPaywall);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meet a Few Members'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: state.loading || state.isExhausted
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Text(
                      '${state.index + 1} of ${state.queue.length}',
                      style: context.textStyles.bodySmall?.copyWith(color: context.colors.muted),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (state.next != null)
                            Transform.scale(scale: 0.95, child: _StaticCard(profile: state.next!)),
                          if (state.current != null)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOut,
                              transitionBuilder: (child, animation) => ScaleTransition(
                                scale: Tween(begin: 0.95, end: 1.0).animate(animation),
                                child: FadeTransition(opacity: animation, child: child),
                              ),
                              child: _SwipeCard(
                                key: ValueKey(state.current!.id),
                                profile: state.current!,
                                // Interested/rejected both just advance the
                                // local deck — there is no other real side
                                // to send an interest to for a demo
                                // profile (see internal/demo's doc comment).
                                onSwiped: (_) =>
                                    ref.read(demoSwipeControllerProvider.notifier).advance(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RoundButton(
                          icon: Icons.close_rounded,
                          color: context.colors.muted,
                          onTap: () => ref.read(demoSwipeControllerProvider.notifier).advance(),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        _RoundButton(
                          icon: Icons.favorite_rounded,
                          color: context.colors.accent,
                          large: true,
                          onTap: () => ref.read(demoSwipeControllerProvider.notifier).advance(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SwipeCard extends StatefulWidget {
  final MatchProfile profile;
  final ValueChanged<bool> onSwiped;
  const _SwipeCard({super.key, required this.profile, required this.onSwiped});

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard> {
  Offset _drag = Offset.zero;
  bool _dragging = false;

  void _onPanStart(DragStartDetails details) => setState(() => _dragging = true);
  void _onPanUpdate(DragUpdateDetails details) => setState(() => _drag += details.delta);

  void _onPanEnd(DragEndDetails details) {
    const threshold = 120.0;
    _dragging = false;
    if (_drag.dx.abs() > threshold) {
      final liked = _drag.dx > 0;
      setState(() => _drag = Offset(liked ? 600 : -600, _drag.dy));
      Future.delayed(const Duration(milliseconds: 180), () => widget.onSwiped(liked));
    } else {
      setState(() => _drag = Offset.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final angle = _drag.dx / 800;
    final likeOpacity = (_drag.dx / 120).clamp(0.0, 1.0);
    final nopeOpacity = (-_drag.dx / 120).clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(_drag.dx, _drag.dy, 0)..rotateZ(angle),
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            _StaticCard(profile: widget.profile),
            Positioned(
              top: 24,
              left: 24,
              child: Opacity(opacity: likeOpacity, child: const _StampLabel(label: 'INTERESTED', color: Colors.green)),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: Opacity(opacity: nopeOpacity, child: const _StampLabel(label: 'SKIP', color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticCard extends StatelessWidget {
  final MatchProfile profile;
  const _StaticCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProfileAvatar(
                name: profile.name, size: double.infinity, borderRadius: BorderRadius.zero, photoUrl: profile.photoSeed),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${profile.name}, ${profile.age}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${profile.profession} · ${profile.city}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StampLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _StampLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: color, width: 3), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20)),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool large;
  const _RoundButton({required this.icon, required this.color, required this.onTap, this.large = false});

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    return Material(
      color: context.colors.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, color: color, size: large ? 30 : 24)),
      ),
    );
  }
}
