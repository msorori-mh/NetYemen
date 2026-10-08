// lib/services/owner_inventory_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/card_batch_validator.dart';

/// خدمة المخزون لأصحاب الشبكات — F-OWN-04 (رفع الكروت) و F-OWN-05 (التحكم بالمخزون).
///
/// تستخدم `Supabase.instance.client` مباشرة (لا تعدّل `owner_supabase_service.dart`).
/// RPCs: `admin_ingest_card_vault_batch`, `admin_list_card_vault_metadata`.
/// جدول: `package_inventory_balances` (SELECT مباشر عبر RLS).
class OwnerInventoryService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==================== F-OWN-04: CARD UPLOAD ====================

  /// رفع دُفعة كروت عبر `admin_ingest_card_vault_batch`.
  ///
  /// [pins] — القائمة النظيفة بعد التحقق (راجع `validateCardBatch`).
  /// [batchKey] — مفتاح عدم التكرار (UUID): إعادة الإرسال بنفس المفتاح تعيد
  /// نتيجة الرفع الأول مع `replayed: true` بدل إدخال الكروت مرتين.
  /// [expiresAt] — تاريخ انتهاء اختياري (ISO 8601 بتوقيت UTC).
  /// يُعيد `{batch_id, ingested_count, duplicates_skipped, replayed}`.
  Future<CardBatchUploadResult> uploadCardBatch({
    required String networkId,
    required String packageId,
    required List<String> pins,
    required String batchKey,
    String? expiresAt,
  }) async {
    final pCards = [
      for (final pin in pins) {'pin': pin, 'expires_at': expiresAt},
    ];

    final response = await _client.rpc(
      'admin_ingest_card_vault_batch',
      params: {
        'p_network_id': networkId,
        'p_package_id': packageId,
        'p_cards': pCards,
        'p_batch_key': batchKey,
      },
    );

    return CardBatchUploadResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  // ==================== F-OWN-05: INVENTORY ====================

  /// مخزون الباقات لشبكة معيّنة عبر `package_inventory_balances`.
  ///
  /// يُعيد قائمة بأعمدة: package_id, network_id, total_units,
  /// available_units, is_available, updated_at.
  Future<List<Map<String, dynamic>>> getInventoryBalances(String networkId) async {
    final response = await _client
        .from('package_inventory_balances')
        .select()
        .eq('network_id', networkId)
        .order('updated_at', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// بيانات بطاقات المخزون الوصفية عبر `admin_list_card_vault_metadata`.
  ///
  /// [state] — فلتر اختياري: available, reserved, sold, quarantined, invalidated.
  /// يُعيد قائمة بأعمدة: id, network_id, package_id, batch_id, state,
  /// created_at, expires_at, sold_at, purchase_id, reveal_count.
  Future<List<Map<String, dynamic>>> getCardVaultMetadata(
    String networkId, {
    String? state,
  }) async {
    final response = await _client.rpc('admin_list_card_vault_metadata', params: {
      'p_network_id': networkId,
      'p_state': state,
    });
    return List<Map<String, dynamic>>.from(response as List? ?? []);
  }

  /// إحصائيات المخزون مُجمَّعة حسب الحالة لشبكة واحدة.
  ///
  /// يُعيد خريطة `{state: count}`.
  Future<Map<String, int>> getCardStateBreakdown(String networkId) async {
    final cards = await getCardVaultMetadata(networkId);
    final breakdown = <String, int>{};
    for (final card in cards) {
      final state = (card['state'] ?? 'unknown') as String;
      breakdown[state] = (breakdown[state] ?? 0) + 1;
    }
    return breakdown;
  }
}
