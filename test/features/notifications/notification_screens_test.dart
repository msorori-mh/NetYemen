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

  testWidgets('notification load failure hides backend details and retries', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(
            _FailingInboxRepository(),
          ),
        ],
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل الإشعارات'), findsOneWidget);
    expect(find.text('تحقق من الاتصال ثم أعد المحاولة.'), findsOneWidget);
    expect(find.textContaining('DATABASE_SECRET_ERROR'), findsNothing);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('mark-read failure still opens the notification destination', (
    tester,
  ) async {
    final repo = _FailingMarkReadRepository()
      ..seedInbox(
        InboxNotification(
          id: 'i2',
          eventId: 'e2',
          titleAr: 'تم تحديث الطلب',
          bodyAr: 'راجع حالة طلبك',
          deepLink: 'request/r2',
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
        child: const MaterialApp(home: NotificationCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تم تحديث الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('طلباتي'), findsOneWidget);
    expect(find.textContaining('DATABASE_SECRET_ERROR'), findsNothing);
  });

  testWidgets('preference save failure shows a safe retry message', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(
            _FailingPreferenceRepository(),
          ),
        ],
        child: const MaterialApp(home: NotificationPreferencesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'شبكات جديدة'));
    await tester.pump();

    expect(
      find.text('تعذر حفظ التفضيلات. تحقق من الاتصال ثم أعد المحاولة.'),
      findsOneWidget,
    );
    expect(find.textContaining('DATABASE_SECRET_ERROR'), findsNothing);
  });
}

class _FailingInboxRepository extends FakeNotificationRepository {
  @override
  Future<List<InboxNotification>> listInbox({
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    throw StateError('DATABASE_SECRET_ERROR');
  }
}

class _FailingMarkReadRepository extends FakeNotificationRepository {
  @override
  Future<void> markRead(String inboxId) async {
    throw StateError('DATABASE_SECRET_ERROR');
  }
}

class _FailingPreferenceRepository extends FakeNotificationRepository {
  @override
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences prefs,
  ) async {
    throw StateError('DATABASE_SECRET_ERROR');
  }
}
