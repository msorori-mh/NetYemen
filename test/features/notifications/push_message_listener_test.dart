import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/config/app_config.dart';
import 'package:netyemen/features/notifications/data/fake_notification_repository.dart';
import 'package:netyemen/features/notifications/data/push_message_source.dart';
import 'package:netyemen/features/notifications/presentation/notification_providers.dart';
import 'package:netyemen/features/notifications/presentation/notification_center_screen.dart';
import 'package:netyemen/features/notifications/presentation/push_message_listener.dart';
import 'package:netyemen/providers/app_providers.dart';

void main() {
  test('uses a stable fallback key when an FCM message ID is absent', () {
    const first = PushMessage(
      title: 'عنوان',
      body: 'نص',
      deepLink: 'request/r1',
    );
    const second = PushMessage(
      title: 'عنوان',
      body: 'نص',
      deepLink: 'request/r1',
    );

    expect(first.deduplicationKey, second.deduplicationKey);
  });

  testWidgets('foreground push refreshes inbox and shows an Arabic action', (
    tester,
  ) async {
    final source = _FakePushMessageSource();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          pushMessageSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const PushMessageListener(
                child: Scaffold(body: Text('الرئيسية')),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    source.addForeground(
      const PushMessage(
        messageId: 'foreground-1',
        title: 'تمت إضافة شبكة',
        body: 'تتوفر شبكة جديدة بالقرب منك',
        deepLink: 'notifications',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('foreground-push-message')), findsOneWidget);
    expect(find.text('تمت إضافة شبكة'), findsOneWidget);
    expect(find.text('تتوفر شبكة جديدة بالقرب منك'), findsOneWidget);
    expect(find.text('فتح'), findsOneWidget);
    expect(
      container.read(foregroundBannerProvider)?.deepLink,
      'notifications',
    );

    await source.close();
  });

  testWidgets('initial and opened copies navigate only once', (tester) async {
    const message = PushMessage(
      messageId: 'opened-1',
      title: 'تحديث الطلب',
      body: 'تم تحديث حالة طلبك',
      deepLink: 'request/r1',
    );
    final source = _FakePushMessageSource(initialMessage: message);
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          pushMessageSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const PushMessageListener(
            child: Scaffold(body: Text('الرئيسية')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طلباتي'), findsOneWidget);
    final pushesAfterInitialMessage = observer.pushCount;

    source.addOpened(message);
    await tester.pumpAndSettle();

    expect(observer.pushCount, pushesAfterInitialMessage);
    await source.close();
  });

  testWidgets('notification-center push opens the operational inbox', (
    tester,
  ) async {
    final source = _FakePushMessageSource(
      initialMessage: const PushMessage(
        messageId: 'opened-notifications',
        title: 'إشعار جديد',
        body: 'راجع مركز الإشعارات',
        deepLink: 'notifications',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.demo),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          pushMessageSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(
          home: PushMessageListener(
            child: Scaffold(body: Text('الرئيسية')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NotificationCenterScreen), findsOneWidget);
    expect(find.text('الإشعارات'), findsOneWidget);
    await source.close();
  });
}

class _FakePushMessageSource implements PushMessageSource {
  final PushMessage? initialMessage;
  final _foreground = StreamController<PushMessage>.broadcast(sync: true);
  final _opened = StreamController<PushMessage>.broadcast(sync: true);

  _FakePushMessageSource({this.initialMessage});

  @override
  Stream<PushMessage> get foregroundMessages => _foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => _opened.stream;

  @override
  Future<PushMessage?> getInitialMessage() async => initialMessage;

  void addForeground(PushMessage message) => _foreground.add(message);

  void addOpened(PushMessage message) => _opened.add(message);

  Future<void> close() async {
    await _foreground.close();
    await _opened.close();
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}
