import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/call_controller.dart';
import 'active_call_screen.dart';

/// Full-screen incoming-call UI, pushed by whatever's listening for
/// [CallStatus.ringing] (see app_shell.dart) so it can appear over any
/// screen the user happens to be on. Auto-dismisses after the same 30s
/// window the backend's ring timeout uses — see [CallController] for the
/// client-side safety-net timer that also covers this.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  Timer? _ringer;

  @override
  void initState() {
    super.initState();
    // No bundled ringtone asset exists in this project to loop a real
    // sound file — this repeats the platform system alert sound plus a
    // haptic buzz every 1.5s as an audible/felt "someone's calling"
    // signal without one. Swap in a real audio asset + audio player when
    // one is available.
    _ringer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    });
  }

  @override
  void dispose() {
    _ringer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callControllerProvider);

    ref.listen(callControllerProvider, (previous, next) {
      if (next.status == CallStatus.connected) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
        );
      } else if (next.status != CallStatus.ringing) {
        // Rejected locally, timed out, or the caller hung up before we
        // answered — either way there's nothing left to show here.
        Navigator.of(context).pop();
      }
    });

    return PopScope(
      // A back-gesture shouldn't silently dismiss an incoming call as if
      // nothing happened — make Reject the only way out.
      canPop: false,
      child: Scaffold(
        backgroundColor: context.colors.ink,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Text(call.isVideo ? 'Incoming video call' : 'Incoming voice call',
                    style: context.textStyles.bodyMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: AppSpacing.lg),
                ProfileAvatar(name: call.peerName, size: 120, photoUrl: call.peerPhotoUrl),
                const SizedBox(height: AppSpacing.lg),
                Text(call.peerName,
                    style: context.textStyles.headlineMedium?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center),
                const Spacer(flex: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      color: context.colors.danger,
                      label: 'Decline',
                      onTap: () => ref.read(callControllerProvider.notifier).rejectCall(),
                    ),
                    _CallActionButton(
                      icon: call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: context.colors.success,
                      label: 'Accept',
                      onTap: () => ref.read(callControllerProvider.notifier).acceptCall(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
