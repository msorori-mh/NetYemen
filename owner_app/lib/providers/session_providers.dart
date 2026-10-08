// lib/providers/session_providers.dart
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/pin_lock_policy.dart';
import 'inventory_providers.dart';
import 'networks_providers.dart';
import 'owner_providers.dart';
import 'sales_providers.dart';

/// يُبطل كل بيانات المالك المخزّنة في المزوّدات.
///
/// يُستدعى مركزياً من جذر التطبيق عند تغيّر المستخدم (دخول، خروج، تبديل
/// حساب) حتى لا تظهر بيانات حساب سابق — مزوّدات الـ family ليست مربوطة
/// بهوية المستخدم. أي مزوّد بيانات جديد يجب أن يُضاف هنا.
void invalidateOwnerData(WidgetRef ref) {
  // الهوية والحواجز
  ref.invalidate(hasNetworkOwnerRoleProvider);
  ref.invalidate(ownedNetworksProvider);
  ref.invalidate(hasAccountPinProvider);
  ref.invalidate(pinTrustedProvider);

  // الشبكات والباقات
  ref.invalidate(networkPackagesProvider);
  ref.invalidate(networkSsidAliasesProvider);

  // المخزون
  ref.invalidate(inventoryBalancesProvider);
  ref.invalidate(cardStateBreakdownProvider);
  ref.invalidate(cardVaultMetadataProvider);

  // المبيعات والتسويات
  ref.invalidate(commercialSummaryProvider);
  ref.invalidate(settlementsProvider);

  // حالة الواجهة المرتبطة بحساب بعينه
  ref.invalidate(selectedTabProvider);
  ref.invalidate(selectedInventoryNetworkProvider);
  ref.invalidate(selectedSalesNetworkProvider);
}

/// تسجيل الخروج الموحّد لكل الشاشات.
///
/// يمسح علامات ثقة رمز الدخول أولاً (فيُطلب الرمز دائماً بعد أي دخول جديد)
/// ثم ينهي الجلسة. جذر التطبيق يستجيب لتغيّر حالة المصادقة: يعود إلى أول
/// مسار ويُبطل البيانات — لا تدفع شاشة تسجيل الدخول يدوياً.
///
/// يعيد `false` إذا تعذّر إنهاء الجلسة (مثلاً بلا اتصال)؛ عندها يبقى
/// التطبيق مقفلاً برمز الدخول.
Future<bool> signOutOwner(WidgetRef ref) async {
  final service = ref.read(ownerServiceProvider);
  await PinLockStore.clear();
  try {
    await service.signOut();
    return true;
  } catch (error, stackTrace) {
    developer.log(
      'Sign-out failed',
      name: 'owner.session',
      error: error,
      stackTrace: stackTrace,
    );
    ref.invalidate(pinTrustedProvider);
    return false;
  }
}

/// نص يُعرض حين يفشل تسجيل الخروج.
const String signOutFailedText =
    'تعذّر تسجيل الخروج. تحقّق من اتصالك بالإنترنت وحاول مرة أخرى.';
