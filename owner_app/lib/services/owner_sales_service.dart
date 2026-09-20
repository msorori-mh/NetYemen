// lib/services/owner_sales_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة المبيعات والتسويات لأصحاب الشبكات — F-OWN-06.
///
/// تستخدم `Supabase.instance.client` مباشرة (لا تعدّل `owner_supabase_service.dart`).
/// RPCs: `get_owner_commercial_summary`, `get_owner_settlements`.
class OwnerSalesService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==================== F-OWN-06: SALES ANALYTICS ====================

  /// ملخّص تجاري لشبكة (أو كل شبكات المالك إذا لم تُمرَّر).
  ///
  /// يُعيد `{gross_sales, pending_settlement, total_sold}`.
  /// كل القيم أعداد صحيحة — يُعامَل أيّ null كصفر (defensive).
  Future<Map<String, dynamic>> getCommercialSummary({String? networkId}) async {
    final response = await _client.rpc('get_owner_commercial_summary', params: {
      'p_network_id': networkId,
    });
    final data = Map<String, dynamic>.from(response as Map? ?? {});
    // Defensive null-safe defaults
    return {
      'gross_sales': data['gross_sales'] ?? 0,
      'pending_settlement': data['pending_settlement'] ?? 0,
      'total_sold': data['total_sold'] ?? 0,
    };
  }

  // ==================== F-OWN-06: SETTLEMENTS ====================

  /// قائمة التسويات لشبكة (أو كل شبكات المالك).
  ///
  /// كل عنصر يحتوي: id, period_start, period_end, network_id,
  /// gross_sales, total_commission, total_refunds, total_adjustments,
  /// net_settlement, status, reviewed_at, notes, created_at, lines[].
  /// يُعامَل أيّ حقل مفقود كـ null (defensive).
  Future<List<Map<String, dynamic>>> getSettlements({String? networkId}) async {
    final response = await _client.rpc('get_owner_settlements', params: {
      'p_network_id': networkId,
    });
    return List<Map<String, dynamic>>.from(response as List? ?? []);
  }
}
