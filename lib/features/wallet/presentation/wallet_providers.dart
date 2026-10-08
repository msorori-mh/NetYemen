// lib/features/wallet/presentation/wallet_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config_provider.dart';
import '../../../core/demo/demo_wallet_store.dart';
import '../../../core/utils/uuid_generator.dart';
import '../../../core/widgets/customer_load_error.dart';
import '../../auth/presentation/customer_session_providers.dart';
import '../data/wallet_repository.dart';
import '../data/supabase_wallet_repository.dart';
import '../data/fake_wallet_repository.dart';
import '../domain/entities.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  // Per-user data: rebuild (and drop cached data) when the account changes.
  ref.watch(currentUserIdProvider);
  final config = ref.watch(appConfigProvider);
  if (config.isDemoMode || !config.isConfigured) {
    return FakeWalletRepository(ref.watch(demoWalletStoreProvider));
  }
  return SupabaseWalletRepository(Supabase.instance.client);
});

final walletSummaryProvider = FutureProvider<WalletSummary>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getMyWalletSummary();
});

final depositHistoryProvider = FutureProvider<List<DepositRequest>>((
  ref,
) async {
  final repo = ref.watch(walletRepositoryProvider);
  return await repo.getMyDepositRequests();
});

class DepositIdempotencySession {
  final String key;
  final String fingerprint;

  const DepositIdempotencySession({
    required this.key,
    required this.fingerprint,
  });
}

class DepositSubmissionNotifier extends AsyncNotifier<String?> {
  DepositIdempotencySession? _pendingSession;
  Future<String>? _inFlight;
  String? _inFlightFingerprint;

  @override
  Future<String?> build() async {
    // Reset any result or error left by a previous account.
    ref.watch(currentUserIdProvider);
    return null;
  }

  /// Submits a deposit request. [amount] is whole YER; [referenceNumber] is
  /// required — a blank one is refused here exactly as the server refuses it.
  Future<String> submit({
    required int amount,
    required String paymentDestinationId,
    required String referenceNumber,
  }) async {
    final normalizedReference = referenceNumber.trim();
    if (amount <= 0) {
      throw StateError('INVALID_AMOUNT: Deposit amount must be positive.');
    }
    if (normalizedReference.isEmpty) {
      throw StateError('INVALID_REFERENCE: Reference number is required.');
    }
    final userId = ref.read(currentUserProvider)?.id ?? '';
    final fingerprint =
        '$userId|$amount|$paymentDestinationId|$normalizedReference';

    final activeRequest = _inFlight;
    if (activeRequest != null) {
      if (_inFlightFingerprint == fingerprint) return await activeRequest;
      throw StateError('DEPOSIT_ALREADY_IN_PROGRESS');
    }

    final request = _submitOnce(
      amount: amount,
      paymentDestinationId: paymentDestinationId,
      referenceNumber: normalizedReference,
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

  Future<String> _submitOnce({
    required int amount,
    required String paymentDestinationId,
    required String referenceNumber,
    required String fingerprint,
  }) async {
    state = const AsyncValue.loading();

    final session = _pendingSession;
    final idempotencyKey = session != null && session.fingerprint == fingerprint
        ? session.key
        : UuidGenerator.generateV4();
    _pendingSession = DepositIdempotencySession(
      key: idempotencyKey,
      fingerprint: fingerprint,
    );

    try {
      final repository = ref.read(walletRepositoryProvider);
      final requestId = await repository.createDepositRequest(
        amount: amount,
        idempotencyKey: idempotencyKey,
        paymentDestinationId: paymentDestinationId,
        referenceNumber: referenceNumber,
      );
      _pendingSession = null;
      state = AsyncValue.data(requestId);
      return requestId;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

final depositSubmissionProvider =
    AsyncNotifierProvider<DepositSubmissionNotifier, String?>(
  DepositSubmissionNotifier.new,
);

/// True when the server refused the chosen payment destination.
bool isDepositDestinationError(Object error) {
  final message = error.toString();
  return message.contains('INVALID_PAYMENT_DESTINATION') ||
      message.contains('PAYMENT_DESTINATION_REQUIRED') ||
      message.contains('INVALID_DESTINATION');
}

/// True when the server refused the transfer reference as missing.
bool isDepositReferenceError(Object error) =>
    error.toString().contains('INVALID_REFERENCE');

/// Customer-facing Arabic message for a failed deposit request.
///
/// Server refusals get a specific message; the connectivity message is kept
/// for real network failures only.
String depositErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('INVALID_REFERENCE')) {
    return 'رقم المرجع مطلوب. أدخل الرقم الظاهر في إيصال التحويل.';
  }
  if (message.contains('INVALID_AMOUNT')) {
    return 'المبلغ غير صحيح. أدخل مبلغاً أكبر من صفر بالريال اليمني.';
  }
  if (isDepositDestinationError(error)) {
    return 'وجهة الدفع المختارة لم تعد متاحة. اختر وجهة أخرى ثم أعد الإرسال.';
  }
  if (message.contains('DUPLICATE')) {
    return 'رقم المرجع هذا مستخدم في طلب إيداع سابق. راجع سجل الإيداعات أو تواصل مع الدعم.';
  }
  if (message.contains('IDEMPOTENCY_CONFLICT')) {
    return 'تغيّرت بيانات الطلب أثناء الإرسال. راجع سجل الإيداعات قبل إرسال طلب جديد.';
  }
  if (message.contains('UNAUTHENTICATED')) {
    return 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.';
  }
  if (message.contains('INACTIVE_PROFILE')) {
    return 'حسابك غير مفعّل حالياً ولا يمكنه طلب إيداع. تواصل مع الدعم.';
  }
  if (message.contains('DEPOSIT_ALREADY_IN_PROGRESS')) {
    return 'هناك طلب إيداع آخر قيد الإرسال. انتظر اكتماله ثم حاول مجدداً.';
  }
  final presentation = CustomerErrorPresentation.from(
    error,
    fallbackTitle: '',
  );
  if (presentation.isOffline) {
    return 'تعذر تأكيد إرسال الطلب. تحقق من الاتصال ثم أعد المحاولة؛ لن يتكرر الطلب.';
  }
  return 'تعذر إرسال الطلب بسبب عطل مؤقت. أعد المحاولة بعد قليل؛ لن يتكرر الطلب.';
}
