import 'package:flutter/material.dart';
import '../../../core/exceptions/app_exception.dart';
import '../../../core/theme/app_theme.dart';

class ErrorStateView extends StatelessWidget {
  final AppFailure failure;
  final VoidCallback onRetry;

  const ErrorStateView({super.key, required this.failure, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: context.colors.danger),
            const SizedBox(height: 16),
            Text('Something went wrong', style: context.textStyles.headlineSmall),
            const SizedBox(height: 6),
            Text(
              failure.message,
              style: context.textStyles.bodyMedium?.copyWith(color: context.colors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
