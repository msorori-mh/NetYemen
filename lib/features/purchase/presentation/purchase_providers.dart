// lib/features/purchase/presentation/purchase_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../../packages/presentation/package_providers.dart';
import '../data/purchase_repository.dart';
import '../data/supabase_purchase_repository.dart';
import '../data/fake_purchase_repository.dart';
import '../domain/entities.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  // Per-user data: rebuild (and drop cached data) when the account changes.
  ref.watch(currentUserIdProvider);
  final config = ref.watch(appConfigProvider);
  if (config.usesDemoData) {
    return FakePurchaseRepository();
  }
  return SupabasePurchaseRepository(Supabase.instance.client);
});

final purchaseHistoryProvider = FutureProvider<List<PurchaseOrder>>((
  ref,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyPurchaseOrders();
});

final fulfillmentRecordsProvider = FutureProvider<List<FulfillmentRecord>>((
  ref,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return await repo.getMyFulfillmentRecords();
});

final purchaseDetailProvider = FutureProvider.family<PurchaseOrder?, String>((
  ref,
  purchaseId,
) async {
  final repo = ref.watch(purchaseRepositoryProvider);
  return repo.getMyPurchaseOrder(purchaseId);
});

class PurchaseIdempotencySession {
  final String key;
  final String fingerprint;

  const PurchaseIdempotencySession({
    required this.key,
    required this.fingerprint,
  });
}

class PurchaseSubmissionNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  PurchaseIdempotencySession? _pendingSession;
  Future<Map<String, dynamic>>? _inFlight;
  String? _inFlightFingerprint;

  /// The purchase (package + confirmed price) the current [state] describes.
  ///
  /// The notifier is shared by every confirmation screen, so a screen must
  /// only show a result or error that belongs to the purchase it presents.
  String? _stateSubject;

  @override
  Future<Map<String, dynamic>?> build() async {
    // Reset any result or error left by a previous account.
    ref.watch(currentUserIdProvider);
    _stateSubject = null;
    return null;
  }

  static String _subjectOf(String packageId, int expectedPrice) =>
      '$packageId:$expectedPrice';

  /// Whether the current [state] belongs to this package at this price.
  bool describes({required String packageId, required int expectedPrice}) =>
      _stateSubject == _subjectOf(packageId, expectedPrice);

  /// Whether a purchase request is being sent right now (for any package).
  bool get hasRequestInFlight => _inFlight != null;

  /// Drops a finished result or error so it cannot be shown on another
  /// purchase. The idempotency session is kept on purpose: retrying the same
  /// logical purchase later must still replay rather than debit twice.
  void reset() {
    if (_inFlight != null) return;
    _stateSubject = null;
    state = const AsyncValue.data(null);
  }

  /// Submits the purchase of [packageId] at [expectedPrice] — the whole-YER
  /// price shown on the confirmation screen.
  Future<Map<String, dynamic>> submit(
    String packageId, {
    required int expectedPrice,
  }) async {
    final userId = ref.read(currentUserProvider)?.id ?? '';
    final fingerprint = '$userId:$packageId:$expectedPrice';

    final activeRequest = _inFlight;
    if (activeRequest != null) {
      if (_inFlightFingerprint == fingerprint) return await activeRequest;
      throw StateError('PURCHASE_ALREADY_IN_PROGRESS');
    }

    final request = _submitOnce(
      packageId: packageId,
      expectedPrice: expectedPrice,
      fingerprint: fingerprint,
    );
    _inFlight = request;
    _inFlightFingerprint = fingerprint;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) {
        _inFlight = null;
        _inFlightFingerprint = null;
      }
    }
  }

  Future<Map<String, dynamic>> _submitOnce({
    required String packageId,
    required int expectedPrice,
    required String fingerprint,
  }) async {
    final subject = _subjectOf(packageId, expectedPrice);
    if (_stateSubject != subject) {
      // Never carry another purchase's result or error into this one.
      state = const AsyncValue.data(null);
    }
    _stateSubject = subject;
    state = const AsyncValue.loading();

    final session = _pendingSession;
    final idempotencyKey = session != null && session.fingerprint == fingerprint
        ? session.key
        : UuidGenerator.generateV4();
    _pendingSession = PurchaseIdempotencySession(
      key: idempotencyKey,
      fingerprint: fingerprint,
    );

    try {
      final repository = ref.read(purchaseRepositoryProvider);
      final result = await repository.purchasePackage(
        packageId: packageId,
        idempotencyKey: idempotencyKey,
        expectedPrice: expectedPrice,
      );
      _pendingSession = null;
      state = AsyncValue.data(result);
      return result;
    } catch (error, stackTrace) {
      if (isPriceChangedError(error)) {
        // The server refused before debiting. Close this session (the next
        // attempt is a new logical purchase at the new price) and reload the
        // package lists so the customer sees the current price.
        _pendingSession = null;
        ref.invalidate(publicPackagesProvider);
      } else if (error.toString().contains('IDEMPOTENCY_KEY_REUSED')) {
        // Refused before debiting because the key belongs to another
        // purchase: it must never be sent again.
        _pendingSession = null;
      }
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

/// True when the server refused a purchase because the package price is no
/// longer the one the customer confirmed.
bool isPriceChangedError(Object error) =>
    error.toString().contains('PRICE_CHANGED');

/// Customer-facing Arabic message for a failed purchase submission.
String purchaseErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('PIN_REQUIRED') || message.contains('PIN_NOT_SET')) {
    return 'انتهت مهلة التأكيد بالرمز السري. لم يُخصم أي مبلغ. اضغط «شراء» مجددًا وأدخل رمزك عند الطلب.';
  }
  if (message.contains('PRICE_CHANGED')) {
    return 'تغيّر سعر هذه الباقة. لم يُخصم أي مبلغ. ارجع إلى قائمة الباقات وراجع السعر الجديد قبل الشراء.';
  }
  if (message.contains('WALLET_FROZEN')) {
    return 'محفظتك موقوفة مؤقتًا ولا يمكن الشراء منها الآن. تواصل مع الدعم لمراجعة حالتها.';
  }
  if (message.contains('INSUFFICIENT_BALANCE')) {
    return 'رصيد المحفظة غير كافٍ لإتمام الشراء.';
  }
  if (message.contains('INACTIVE_PROFILE') ||
      message.contains('ACCOUNT_NOT_ACTIVE')) {
    return 'حسابك غير مفعّل حاليًا ولا يمكنه الشراء. تواصل مع الدعم.';
  }
  if (message.contains('IDEMPOTENCY_KEY_REUSED')) {
    return 'تعذر إتمام العملية ولم يُخصم أي مبلغ. ارجع إلى الباقات ثم حاول مجددًا.';
  }
  if (message.contains('OUT_OF_STOCK')) {
    return 'نفدت كروت هذه الباقة حاليًا. اختر باقة أخرى أو حاول لاحقًا.';
  }
  if (message.contains('PACKAGE_UNAVAILABLE') ||
      message.contains('NETWORK_UNAVAILABLE')) {
    return 'الباقة أو الشبكة غير متاحة حاليًا.';
  }
  if (message.contains('UNAUTHENTICATED')) {
    return 'انتهت جلسة الدخول. سجّل الدخول ثم حاول مجددًا.';
  }
  if (message.contains('PURCHASE_ALREADY_IN_PROGRESS')) {
    return 'هناك عملية شراء أخرى قيد التنفيذ. انتظر اكتمالها ثم حاول مجددًا.';
  }
  return 'تعذر تأكيد نتيجة العملية. أعد المحاولة بأمان؛ لن يتم الخصم مرتين.';
}

final purchaseSubmissionProvider =
    AsyncNotifierProvider<PurchaseSubmissionNotifier, Map<String, dynamic>?>(
  PurchaseSubmissionNotifier.new,
);
