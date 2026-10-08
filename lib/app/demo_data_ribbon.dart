import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config_provider.dart';

/// Marks every screen with a small corner ribbon while the app serves
/// built-in demo data, so demo balances, cards and purchases can never be
/// mistaken for real ones.
///
/// It follows the single demo predicate, `AppConfig.usesDemoData` — the same
/// one that selects the fake repositories — and renders nothing extra for a
/// build bound to a real backend.
class DemoDataRibbon extends ConsumerWidget {
  const DemoDataRibbon({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usesDemoData = ref.watch(
      appConfigProvider.select((config) => config.usesDemoData),
    );
    if (!usesDemoData) return child;

    return Banner(
      key: const Key('demo-data-ribbon'),
      message: 'تجريبي',
      location: BannerLocation.topStart,
      textDirection: TextDirection.rtl,
      layoutDirection: TextDirection.rtl,
      color: const Color(0xFFB45309),
      child: child,
    );
  }
}
