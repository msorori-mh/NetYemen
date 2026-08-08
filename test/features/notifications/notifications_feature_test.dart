import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/notifications/deep_link/deep_link_parser.dart';
import 'package:netyemen/features/notifications/data/fake_notification_repository.dart';
import 'package:netyemen/features/notifications/data/notification_transport_adapter.dart';
import 'package:netyemen/features/notifications/domain/entities.dart';

void main() {
  group('DeepLinkParser', () {
    const parser = DeepLinkParser();

    test('parses network deep links', () {
      final target = parser.parse('netyemen://network/abc-123');
      expect(target.kind, DeepLinkKind.network);
      expect(target.id, 'abc-123');
    });

    test('parses package, request, notifications, profile', () {
      expect(parser.parse('package/p1').kind, DeepLinkKind.package);
      expect(parser.parse('request/r1').kind, DeepLinkKind.request);
      expect(parser.parse('notifications').kind, DeepLinkKind.notifications);
      expect(parser.parse('profile').kind, DeepLinkKind.profile);
    });
  });

  group('FakeNotificationRepository', () {
    test('rejects secret-like tokens', () async {
      final repo = FakeNotificationRepository();
      expect(
        () => repo.registerDeviceToken(
          platform: 'android',
          token: 'BEGIN PRIVATE KEY',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('keeps transactional preference conceptually locked via defaults',
        () async {
      final repo = FakeNotificationRepository();
      final updated = await repo.updatePreferences(
        NotificationPreferences.defaults().copyWith(networkAddedEnabled: false),
      );
      expect(updated.transactionalEnabled, isTrue);
      expect(updated.networkAddedEnabled, isFalse);
    });

    test('rejects secret announcement payloads', () async {
      final repo = FakeNotificationRepository();
      expect(
        () => repo.adminCompose(
          titleAr: 'password leak',
          bodyAr: 'secret pin',
          audienceType: 'all_active_customers',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('UnboundNotificationTransportAdapter', () {
    test('blocks external dispatch without provider binding', () async {
      const adapter = UnboundNotificationTransportAdapter();
      expect(adapter.isBound, isFalse);
      final result = await adapter.dispatch(
        deliveryId: 'd1',
        deviceToken: 't1',
        titleAr: 'عنوان',
        bodyAr: 'نص',
      );
      expect(result.accepted, isFalse);
      expect(result.status, 'dispatch_blocked_unbound_provider');
    });
  });
}
