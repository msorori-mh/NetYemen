# تقرير الفحص الشامل لتطبيق NetYemen (العميل)

**المستودع:** msorori-mh/NetYemen
**الفرع:** `claude/comprehensive-app-review-fbig0t` (مبني على `main` @ `482f259`)
**تاريخ الفحص:** 2026-10-01
**نطاق الفحص:** كود Flutter (`lib/`)، الاختبارات، CI، إعدادات Android، الاعتماديات، ومطابقة الكود مع العقود الموثقة في `docs/`.

> لم يتم أي اتصال بقاعدة بيانات Supabase الإنتاجية، ولم تُرسل رسائل OTP، ولم يُعدَّل أي كود في التطبيق. هذا التقرير توثيقي فقط.

---

## 1. الملخص التنفيذي

تحسّن المستودع كثيراً منذ تقرير `NY-AUDIT-004`: الكود يُترجم، و`flutter analyze` نظيف، والاختبارات تمر، ومجلد `android/` موجود، وCI يعمل.
**لكن التطبيق لا يعمل فعلياً عند تشغيله**، وفيه أخطاء منطقية ومالية خطيرة لم تكشفها الاختبارات الحالية لأنها لا تختبر الشاشات أو المزوّدات (providers) إطلاقاً.

| الفئة | العدد |
|---|---|
| 🔴 حرجة (تمنع التشغيل أو تسبب خسارة مالية) | 5 |
| 🟠 عالية | 7 |
| 🟡 متوسطة | 10 |
| ⚪ منخفضة / تحسينات | 10 |

**القرار: غير جاهز للإصدار (HOLD).** يجب إصلاح البنود الحرجة الخمسة قبل أي اختبار على جهاز حقيقي.

---

## 2. نتائج الأوامر الأساسية (Flutter 3.38.7 / Dart 3.10.7 — نفس إصدار CI)

| الأمر | النتيجة |
|---|---|
| `flutter pub get` | ✅ نجح (33 حزمة لها إصدارات أحدث غير متوافقة مع القيود) |
| `dart format --set-exit-if-changed lib test` | ✅ لا تغييرات |
| `flutter analyze` | ✅ No issues found |
| `flutter test` | ✅ 6/6 اختبارات ناجحة |
| اختبار تجريبي لإعداد `MaterialApp` الفعلي (locale عربي) | ❌ **انهيار: `No MaterialLocalizations found`** (انظر C-1) |

---

## 3. المشاكل الحرجة 🔴

### C-1: التطبيق ينهار على كل شاشة بسبب غياب حزمة التعريب العربي
**الموقع:** `lib/main.dart:34-38`، `pubspec.yaml`

يتم ضبط `locale: Locale('ar', 'YE')` دون إضافة `flutter_localizations` ولا `localizationsDelegates`. المندوب الافتراضي لـ `MaterialLocalizations` يدعم الإنجليزية فقط، فلا تتوفر `MaterialLocalizations` للعربية. تم التحقق عملياً باختبار widget يعيد إنتاج نفس الإعداد:

```
Warning: This application's locale, ar_YE, is not supported by all of its localization delegates.
• A MaterialLocalizations delegate that supports the ar_YE locale was not found.
No MaterialLocalizations found.
AppBar widgets require MaterialLocalizations ...
```

كل شاشة تستخدم `AppBar` أو `BottomNavigationBar` أو `TextField` أو `AlertDialog` ستنهار (شاشة حمراء في debug، وسلوك معطوب في release). حتى لو لم تنهر، فإن اتجاه الواجهة سيكون **LTR** وليس RTL.

**الإصلاح:**
```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```
```dart
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```
**لماذا لم يكتشفه CI؟** اختبار `test/widgets/app_construction_test.dart` يبني `MaterialApp` منفصلاً بدلاً من `NetYemenApp` الحقيقي.

---

### C-2: نسخة Release لا تملك صلاحية الإنترنت
**الموقع:** `android/app/src/main/AndroidManifest.xml`

صلاحية `android.permission.INTERNET` موجودة فقط في `src/debug` و`src/profile`. نسخة الإصدار (release APK/AAB) لن تستطيع الاتصال بـ Supabase نهائياً — لا تسجيل دخول، لا شبكات، لا شراء.

**الإصلاح:** إضافة `<uses-permission android:name="android.permission.INTERNET"/>` في `src/main/AndroidManifest.xml`.

---

### C-3: تسجيل الدخول يُصفّر رصيد المحفظة (أو يفشل تسجيل الدخول)
**الموقع:** `lib/services/supabase_service.dart:42-53`، `lib/screens/auth/otp_screen.dart:35`

بعد كل تحقق OTP ناجح، يُستدعى:
```dart
_client.from('users').upsert({ 'id': ..., 'phone': ..., 'full_name': null, 'wallet_balance': 0 });
```
`upsert` على صف موجود **يستبدل** القيم. أي أن العميل الذي لديه رصيد ثم سجّل خروجاً ودخولاً:
- إذا كانت سياسات RLS تسمح بالتحديث ← **يُصفَّر رصيده ويُمسح اسمه** (خسارة مالية مباشرة).
- إذا كانت RLS تمنعه ← يُرمى استثناء، فيظهر للمستخدم «رمز التحقق غير صحيح» رغم أن الجلسة أُنشئت فعلاً، ويبقى عالقاً.

كما أن السماح للعميل بكتابة `wallet_balance` مخالف صراحةً لـ **BR-AUTH-003** و**BR-WALLET-002**.

**الإصلاح:** حذف `createOrUpdateUser` من العميل وإنشاء الملف عبر trigger على `auth.users`، ومنع أي كتابة لـ `wallet_balance` من العميل عبر RLS / صلاحيات الأعمدة.

---

### C-4: حالة المستخدم لا تتحدث بعد تسجيل الدخول — التطبيق يعمل كأنه بلا مستخدم
**الموقع:** `lib/providers/app_providers.dart:19-21`

```dart
final currentUserProvider = Provider<User?>((ref) => Supabase.instance.client.auth.currentUser);
```
هذا `Provider` يُحسب **مرة واحدة** ويُخزَّن طوال عمر `ProviderScope`. شاشة البداية تقرأه قبل تسجيل الدخول فيُخزَّن `null`. بعد تسجيل الدخول:
- `userProfileProvider` ← `null` ← «لم يتم العثور على المستخدم» في صفحة حسابي.
- `walletBalanceProvider` ← `0` ← كل محاولة شراء تُرفض بـ «رصيد غير كافٍ».
- المشتريات والمعاملات ← قوائم فارغة.

ويحدث العكس عند تسجيل الخروج ثم الدخول بحساب آخر: تبقى بيانات المستخدم السابق معروضة (تسرب بيانات بين حسابات على نفس الجهاز).

**الإصلاح:** اشتقاق المستخدم من `authStateProvider`:
```dart
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser;
});
```
مع `invalidate` لكل المزوّدات المرتبطة بالمستخدم عند الخروج.

---

### C-5: الفئات والأسعار ثابتة في الواجهة ولا تأتي من قاعدة البيانات
**الموقع:** `lib/screens/home/network_detail_screen.dart:153`، `33`، `227`

- الفئات `[200, 500, 1000, 5000]` مكتوبة يدوياً لكل الشبكات، بينما `getNetworkPrices()` موجودة ولا تُستدعى أبداً. المستخدم قد يختار فئة غير موجودة لدى الشبكة.
- الزر يعرض «شراء بـ {الفئة} ر.ي» ويقارن الرصيد بـ **الفئة** وليس **سعر البيع** (`NetworkPrice.price`). إذا كان السعر مختلفاً عن الفئة سيرى المستخدم مبلغاً خاطئاً قبل الدفع.
- لا يوجد عرض للمخزون المتوفر، ولا بيانات الباقة (حجم/مدة/سرعة) المطلوبة في **BR-CARD-008**.

**الإصلاح:** مزوّد `networkPricesProvider.family(networkId)` وعرض الأسعار الفعلية فقط، والاعتماد على السعر الذي يعيده الخادم.

---

## 4. المشاكل عالية الخطورة 🟠

### H-1: `purchase_card` يستقبل `p_user_id` من العميل ولا يوجد مفتاح idempotency
**الموقع:** `lib/services/supabase_service.dart:99-115`
مخالف لـ **BR-PURCHASE-002** و**BR-PURCHASE-004**. إن لم تتجاهل الدالة في الخادم `p_user_id` وتستخدم `auth.uid()`، يمكن لأي مستخدم الشراء من محفظة غيره (IDOR). وغياب `idempotency_key` يعني أن انقطاع الشبكة بعد الخصم وقبل وصول الرد ثم إعادة المحاولة = خصم مزدوج (شائع جداً مع شبكات اليمن الضعيفة).

### H-2: مخطط قاعدة البيانات وسياسات RLS غير موجودة في المستودع
`sql/netyemen_schema_fixed.sql` المذكور في README غير موجود (نفس SEC-01 في التدقيق السابق ولم يُعالج). لا يمكن التحقق من أي ادعاء أمني: عزل المحافظ، حماية الكروت غير المباعة، منطق `purchase_card`. **هذا أهم بند أمني مفتوح.**

### H-3: الكود يفترض أن الكروت غير المباعة قابلة للقراءة من العميل
**الموقع:** `lib/services/supabase_service.dart:81-97`
`getAvailableCard()` تقرأ `card_number` لكروت حالتها `available` مباشرة من جدول `cards`. الدالة غير مستخدمة، لكن وجودها يدل على أن RLS قد تسمح بذلك — وهذا يعني أن أي مستخدم يستطيع سحب كل أرقام الكروت غير المباعة مجاناً (مخالف لـ **BR-CARD-004**). **يجب التحقق فوراً من RLS على جدول `cards`** وحذف هذه الدالة.

### H-4: نتيجة الشراء غير مُتحقَّق منها
**الموقع:** `network_detail_screen.dart:49-58`
أي `Map` غير `null` يُعتبر نجاحاً: `result['card_number'] ?? ''`. إذا أعادت الدالة `{success: false, error: ...}` (نمط شائع)، ستظهر للمستخدم شاشة «تم الشراء بنجاح!» برقم كرت فارغ.

### H-5: لا تحديث للرصيد أو المشتريات بعد الشراء أو الشحن
لا يوجد `ref.invalidate(...)` في أي مكان. بعد الشراء يبقى الرصيد القديم معروضاً، ولا يظهر الكرت في «مشترياتي» حتى إعادة تشغيل التطبيق. ولا يوجد سحب للتحديث (pull-to-refresh) في أي شاشة. README يذكر Realtime لكنه غير مستخدم.

### H-6: طلب الشحن لا يحتوي على أي إثبات دفع
**الموقع:** `lib/screens/wallet/deposit_screen.dart`
يُرسل المبلغ وطريقة الدفع فقط — لا رقم مرجع/حوالة، ولا صورة إيصال، ولا حساب البنك/المحفظة الذي يجب التحويل إليه. هذا يخالف **BR-WALLET-003** و**BR-WALLET-007**، ويجعل مراجعة الطلب من قسم المالية مستحيلة عملياً. لا يوجد حد أعلى للمبلغ، ولا تقييد للإدخال بالأرقام (`inputFormatters`)، ولا عرض لحالة الطلبات السابقة.

### H-7: تحقق رقم الهاتف وتدفق OTP ضعيفان
- `login_screen.dart:21` يتحقق من الطول فقط؛ لا يتحقق أن الإدخال أرقام ولا من البادئة (70/71/73/77/78) المطلوبة في **BR-AUTH-001**.
- زر «إعادة إرسال الرمز» لا يفعل شيئاً (`otp_screen.dart:117`)، ولا يوجد عدّاد 60 ثانية (**BR-AUTH-002**).
- أي خطأ في التحقق يظهر كـ «رمز التحقق غير صحيح» حتى لو كان السبب انقطاع الشبكة أو خطأ في قاعدة البيانات (C-3).

---

## 5. المشاكل المتوسطة 🟡

| # | المشكلة | الموقع |
|---|---|---|
| M-1 | البحث لا يعمل: النص يُخزن في `networksSearchQueryProvider` لكن القائمة لا تُفلتر به. وزر المسح يصفّر المزوّد دون مسح النص من الحقل (لا يوجد `TextEditingController`). رسالة commit «filter networks by governorate» لا يقابلها كود فعلي. | `home_screen.dart` |
| M-2 | `walletBalanceProvider` يعيد `0` أثناء التحميل أو الخطأ، فيظهر «رصيد غير كافٍ» بشكل مضلل. | `app_providers.dart:58-65` |
| M-3 | عرض رسائل الاستثناء الخام للمستخدم (`$e`) — يكشف تفاصيل داخلية وقد يحتوي بيانات حساسة. | `login_screen.dart:41`، `network_detail_screen.dart:62`، `supabase_service.dart:113` |
| M-4 | `setState` داخل `finally` بعد `if (!mounted) return;` ← استثناء «setState() called after dispose» إذا غادر المستخدم الشاشة أثناء الطلب. | login/otp/network_detail/deposit |
| M-5 | `TextEditingController` لا يتم التخلص منها (`dispose`) — تسرب ذاكرة. | login/otp/deposit |
| M-6 | معرّف التطبيق `com.example.netyemen` — Google Play يرفض `com.example`. والاسم الظاهر `netyemen` بحروف صغيرة، وأيقونة Flutter الافتراضية، ولا يوجد إعداد توقيع release. | `android/app/build.gradle.kts`، `AndroidManifest.xml` |
| M-7 | مفتاح ALAWAEL SMS موضوع كثابت في كود العميل. حتى لو كان قيمة مؤقتة الآن، مفاتيح مزود SMS **يجب ألا تكون في التطبيق أبداً** (أي APK يمكن تفكيكه) — مكانها Edge Function / Supabase Auth Hook. | `constants.dart:13` |
| M-8 | التحقق من الشبكات المعروضة على العميل يكتفي بـ `is_active`؛ **BR-NETWORK-005** يتطلب أيضاً `is_approved` وحالة المالك. يجب فرضه في RLS/view وليس في العميل. | `supabase_service.dart:57-65` |
| M-9 | شاشة البداية تنتظر ثانيتين ثابتتين، ولا تتحقق من صلاحية الجلسة أو إيقاف الحساب (`is_active`)؛ الحساب الموقوف يدخل التطبيق عادياً. | `splash_screen.dart` |
| M-10 | لا معالجة لانقطاع الإنترنت: لا timeout، لا زر «إعادة المحاولة» في حالات الخطأ (كلها نص «حدث خطأ» فقط). | جميع الشاشات |

---

## 6. منخفضة / تحسينات ⚪

1. التواريخ تُعرض بتوقيت UTC (`DateTime.parse` لقيمة `Z`) دون `toLocal()`، وفي المحفظة تُعرض كنص ISO خام (`2026-10-01T12:00:00.000Z`).
2. المبالغ بلا فواصل آلاف (`5000` بدلاً من `5,000`) — استخدم `intl`.
3. `profile_screen.dart:51`: `user.phone[0]` ينهار إذا كان الهاتف فارغاً.
4. أزرار بلا وظيفة: الإشعارات، تعديل الملف، الموقع، المساعدة، عن التطبيق. رقم الإصدار مكتوب يدوياً «1.0.0» بدلاً من `AppConstants.appVersion` أو `package_info_plus`.
5. كود غير مستخدم: `flutter_screenutil` (اعتماد كامل غير مستخدم)، `selectedDenominationProvider`، `getAvailableCard`، `CardModel`، `AppUser.toJson` (الذي يرسل `wallet_balance`).
6. `walletTransactionsProvider` يعيد `List<dynamic>` بدل نموذج مُعرّف؛ و`isCredit` يعتمد على قيم نصية (`deposit`/`refund`) غير موثقة.
7. شاشة نجاح الشراء: الكرت الكامل معروض بدون منع لقطات الشاشة (`FLAG_SECURE`) — قرار منتج، لكن يُنصح به على الأقل لعدم ظهوره في قائمة التطبيقات الحديثة.
8. لا وصف `tooltip`/`Semantics` لأزرار الأيقونات (نسخ، إشعارات، مسح) — ضعف في إمكانية الوصول. الخطوط بأحجام ثابتة ولا يوجد خط عربي مخصص.
9. الاعتماديات قديمة: `flutter_lints 3` (المتاح 6)، `flutter_riverpod 2` مع `StateProvider` (legacy في Riverpod 3)، `supabase_flutter 2.16` (المتاح 2.18).
10. README غير مطابق للواقع: يذكر `sql/` و`docs/PROJECT_CONTEXT.md` و`docs/PROMPT_TEMPLATE.md` وهي غير موجودة، ويقول إن الحالة «قيد التطوير» دون ذكر المعوقات.

---

## 7. الاختبارات و CI

**الوضع الحالي:** 6 اختبارات فقط — نموذجان (`Network.fromJson`، `maskedCardNumber`) واختبار widget لا يختبر التطبيق فعلياً.

**الفجوات:**
- لا اختبار لـ `NetYemenApp` نفسه (كان سيكشف C-1 فوراً).
- لا اختبارات للمزوّدات (كان سيكشف C-4).
- لا اختبارات للشاشات: تسجيل الدخول، الشراء، الشحن.
- `SupabaseService` غير قابل للحقن (`Supabase.instance.client` داخل الكلاس) مما يصعّب الاختبار — يُنصح بتمرير `SupabaseClient` في المُنشئ وتجاوز `supabaseServiceProvider` في الاختبارات.
- كتالوج الاختبارات `NETYEMEN-ACCEPTANCE-TEST-CATALOG-01.md` (516 سطراً) لا يقابله أي اختبار منفذ.

**CI:** جيد كبداية (format + analyze + test + debug APK). يُنصح بإضافة `flutter build apk --release` (كان سيكشف أخطاء manifest/signing)، وقياس التغطية، واختبار SQL/RLS عند إضافة المخطط.

---

## 8. مطابقة الكود مع العقود الموثقة

| القاعدة | الحالة في الكود |
|---|---|
| BR-AUTH-001 تطبيع الهاتف | ⚠️ جزئي (البادئة فقط) |
| BR-AUTH-002 إعادة إرسال OTP / تهدئة | ❌ غير منفذ |
| BR-AUTH-003 إنشاء الملف عبر trigger | ❌ **مخالف** (upsert من العميل) |
| BR-CARD-004 سرية الكروت غير المباعة | ❓ غير قابل للتحقق + مؤشر خطر (H-3) |
| BR-CARD-008 بيانات الباقة | ❌ غير منفذ |
| BR-PURCHASE-002 idempotency | ❌ غير منفذ |
| BR-PURCHASE-003 سعر من الخادم | ⚠️ الواجهة تعرض الفئة لا السعر |
| BR-PURCHASE-004 هوية من `auth.uid()` | ❌ **مخالف** (يُرسل `p_user_id`) |
| BR-WALLET-002 دفتر قيود غير قابل للتعديل | ❌ **مخالف** (العميل يكتب `wallet_balance`) |
| BR-WALLET-003 إثبات الإيداع | ❌ غير منفذ |
| BR-NETWORK-005 شروط ظهور الشبكة | ⚠️ `is_active` فقط |

---

## 9. خطة الإصلاح المقترحة (بالترتيب)

**المرحلة 1 — تشغيل التطبيق (يوم واحد تقريباً):**
1. C-1 إضافة `flutter_localizations` والمندوبات + اختبار widget يبني `NetYemenApp` الحقيقي.
2. C-2 صلاحية INTERNET في manifest الرئيسي.
3. C-4 ربط `currentUserProvider` بحالة المصادقة وإبطال المزوّدات عند الخروج.
4. M-4 / M-5 إصلاح `setState` و`dispose`.

**المرحلة 2 — الأمان والمال (أولوية قصوى قبل أي مستخدم حقيقي):**
5. H-2 إضافة مخطط SQL وسياسات RLS إلى المستودع (`supabase/migrations/`).
6. C-3 حذف upsert من العميل → trigger، ومنع كتابة `wallet_balance`.
7. H-3 التحقق من RLS على `cards` وحذف `getAvailableCard`.
8. H-1 تعديل `purchase_card`: `auth.uid()`، `idempotency_key`، `FOR UPDATE SKIP LOCKED`، والسعر من `network_prices`.
9. H-4 التحقق من شكل نتيجة الشراء.
10. M-7 إخراج مفتاح SMS من العميل.

**المرحلة 3 — اكتمال الوظائف:**
11. C-5 الأسعار الديناميكية + المخزون + بيانات الباقة.
12. H-5 إبطال/تحديث البيانات بعد الشراء والشحن + pull-to-refresh.
13. H-6 إثبات الإيداع ودليل حسابات الدفع.
14. H-7 / M-1 تحقق الهاتف، إعادة إرسال OTP، البحث.

**المرحلة 4 — الجاهزية للنشر:**
15. M-6 معرّف التطبيق، الأيقونة، توقيع release، `flutter build apk --release` في CI.
16. البنود المنخفضة، تحديث README، وتوسيع الاختبارات وفق كتالوج القبول.

---

## 10. النقاط الإيجابية

- هيكل مجلدات واضح (models / services / providers / screens) وسهل التوسعة.
- استخدام RPC ذري للشراء بدلاً من منطق في العميل — الاتجاه الصحيح.
- إخفاء رقم الكرت في قائمة المشتريات مع إمكانية النسخ.
- استخدام مفتاح `publishable` (وليس `service_role`) في العميل.
- `.gitignore` سليم، CI يعمل، والتحليل الساكن نظيف.
- توثيق المنتج والعقود (`docs/`) شامل ومفصل بشكل ممتاز — المشكلة أن الكود لم يلحق به بعد.
