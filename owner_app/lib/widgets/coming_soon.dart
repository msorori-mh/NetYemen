// lib/widgets/coming_soon.dart
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// عنصر نائب موحّد لتبويبات لم تُبنَ بعد في هذه الموجة.
class ComingSoon extends StatelessWidget {
  final IconData icon;
  final String message;

  const ComingSoon({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
