import 'notification_transport_adapter.dart';

/// Fallback FCM transport adapter used in local/source-only builds where the
/// Supabase Edge Function returns `credential_required`.
///
/// This adapter never embeds FCM service-account secrets and never contacts
/// Google. It records the dispatch outcome so the app can degrade gracefully
/// (e.g. rely on in-app notifications) until real credentials are configured
/// for the physical pilot.
class FakeFcmTransportAdapter implements NotificationTransportAdapter {
  const FakeFcmTransportAdapter();

  @override
  String get providerKey => 'fcm';

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
      status: 'credential_required',
      error:
          'FCM server credentials are not configured in this environment. '
          'Use the Supabase Edge Function for physical pilot builds.',
    );
  }
}
