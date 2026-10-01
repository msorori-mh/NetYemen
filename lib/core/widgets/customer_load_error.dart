import 'dart:async';

import 'package:flutter/material.dart';

import '../error/app_exceptions.dart';
import '../theme/app_theme.dart';

class CustomerErrorPresentation {
  final bool isOffline;
  final String title;
  final String message;
  final IconData icon;

  const CustomerErrorPresentation({
    required this.isOffline,
    required this.title,
    required this.message,
    required this.icon,
  });

  factory CustomerErrorPresentation.from(
    Object error, {
    required String fallbackTitle,
  }) {
    if (_looksOffline(error)) {
      return const CustomerErrorPresentation(
        isOffline: true,
        title: 'لا يوجد اتصال بالإنترنت',
        message: 'تحقق من الشبكة ثم أعد المحاولة.',
        icon: Icons.wifi_off_outlined,
      );
    }
    return CustomerErrorPresentation(
      isOffline: false,
      title: fallbackTitle,
      message: 'حدث عطل مؤقت. أعد المحاولة بعد قليل.',
      icon: Icons.sync_problem_outlined,
    );
  }

  static bool _looksOffline(Object error) {
    if (error is TimeoutException || error is NetworkException) return true;
    final type = error.runtimeType.toString().toLowerCase();
    final text = error.toString().toLowerCase();
    return type.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection timed out') ||
        text.contains('connection closed before full header');
  }
}

class CustomerLoadError extends StatelessWidget {
  final Object error;
  final String fallbackTitle;
  final VoidCallback onRetry;
  final bool compact;

  const CustomerLoadError({
    super.key,
    required this.error,
    required this.fallbackTitle,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final presentation = CustomerErrorPresentation.from(
      error,
      fallbackTitle: fallbackTitle,
    );
    late final String stateKey;
    late final Color stateColor;
    if (presentation.isOffline) {
      stateKey = 'customer-offline-state';
      stateColor = AppTheme.warning;
    } else {
      stateKey = 'customer-load-error-state';
      stateColor = AppTheme.error;
    }
    return Center(
      child: Padding(
        key: Key(stateKey),
        padding: EdgeInsets.all(compact ? 8 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              presentation.icon,
              size: compact ? 32 : 52,
              color: stateColor,
            ),
            SizedBox(height: compact ? 6 : 12),
            Text(
              presentation.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              presentation.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            SizedBox(height: compact ? 8 : 16),
            OutlinedButton.icon(
              key: const Key('customer-load-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
