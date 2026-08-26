import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/network_discovery/presentation/network_discovery_providers.dart';
import 'package:netyemen/features/notifications/data/fake_notification_repository.dart';
import 'package:netyemen/features/notifications/domain/entities.dart';
import 'package:netyemen/features/notifications/presentation/notification_center_screen.dart';
import 'package:netyemen/features/notifications/presentation/notification_preferences_screen.dart';
import 'package:netyemen/features/notifications/presentation/notification_providers.dart';

void main() {
  testWidgets('notification center renders Arabic inbox items', (tester) async {
    final repo = FakeNotificationRepository()
      ..seedInbox(
        InboxNotification(
          id: 'i1',
          eventId: 'e1',
          titleAr: 'تم قبول طلب الشبكة',
          bodyAr: 'تم قبول طلبك',
          deepLink: 'request/r1',
          category: 'transactional',
          channelClass: 'request_status',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NotificationCenterScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.text('تم قبول طلب الشبكة'), findsOneWidget);
  });

  testWidgets('preferences screen shows mandatory transactional lock', (
    tester,
  ) async {
    final repo = FakeNotificationRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: NotificationPreferencesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إعدادات الإشعارات'), findsOneWidget);
    expect(find.text('حالة الطلبات والمعاملات'), findsOneWidget);
    expect(find.text('شبكات جديدة'), findsOneWidget);
  });
}
