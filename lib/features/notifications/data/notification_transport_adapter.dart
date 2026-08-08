/// Provider-neutral client transport boundary.
///
/// External push dispatch is intentionally unbound until OD-NOTIF-01 closes.
/// Flutter must never embed FCM/OneSignal service-account secrets.
abstract class NotificationTransportAdapter {
  String get providerKey;
  bool get isBound;

  Future<TransportDispatchResult> dispatch({
    required String deliveryId,
    required String deviceToken,
    required String titleAr,
    required String bodyAr,
    String? deepLink,
  });
}

class TransportDispatchResult {
  final bool accepted;
  final String status;
  final String? providerMessageId;
  final String? error;

  const TransportDispatchResult({
    required this.accepted,
    required this.status,
    this.providerMessageId,
    this.error,
  });
}

/// Default V1 adapter: records that provider binding is required.
class UnboundNotificationTransportAdapter implements NotificationTransportAdapter {
  const UnboundNotificationTransportAdapter();

  @override
  String get providerKey => 'unbound';

  @override
  bool get isBound => false;

  @override
  Future<TransportDispatchResult> dispatch({
    required String deliveryId,
    required String deviceToken,
    required String titleAr,
    required String bodyAr,
    String? deepLink,
  }) async {
    return const TransportDispatchResult(
      accepted: false,
      status: 'dispatch_blocked_unbound_provider',
      error: 'OD-NOTIF-01 OPEN: provider binding required before external push.',
    );
  }
}
