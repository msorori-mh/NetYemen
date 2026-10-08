# واصل نت (WASEL NET / NetYemen)

منصة لبيع كروت الإنترنت لشبكات الواي فاي المحلية في اليمن: العميل يشحن محفظة
داخلية بتحويل بنكي تراجعه المالية، يشتري باقة من شبكة معتمدة، ويستلم رقم الكرت
داخل التطبيق. صاحب الشبكة يرفع كروته ويتابع مبيعاته وتسوياته، والإدارة تعتمد
الشبكات وتراجع الإيداعات وتُجري التسويات.

كل المبالغ بالريال اليمني **أعداداً صحيحة** (INTEGER). لا توجد كسور ولا ضرب أو
قسمة على 100 في أي مكان (التطبيقات، قاعدة البيانات، لوحة الإدارة).

المستودع خاص. هذا الملف يصف الوضع الفعلي للكود، لا الخطة.

## المكوّنات وحالتها

| المكوّن | المسار | الحالة الفعلية |
|---|---|---|
| تطبيق العميل (Flutter، Android) | `lib/main.dart` | يعمل مع Supabase عند تمرير `--dart-define`. بدونها يعمل بناء debug على **بيانات تجريبية مضمّنة** فقط، وبناء release يعرض شاشة «غير مهيّأ». |
| لوحة الإدارة — Flutter web | `lib/admin_main.dart` | تُبنى في CI. الدخول بالبريد وكلمة المرور. |
| لوحة الإدارة — صفحة ثابتة | `admin/` | `index.html` + `app.js` بلا خطوة بناء (Vercel). الدخول عبر Google. سمة SRI لمكتبة supabase-js لم تُضف بعد. |
| تطبيق المالك (Flutter، Android) | `owner_app/` | تطبيق مستقل، دخول Google + رمز PIN. انظر `owner_app/README.md`. |
| الخادم (Supabase) | `supabase/` | 39 ملف migration، 30 مجموعة اختبار SQL، 4 دوال Edge. كل العمليات الحساسة دوال RPC والصلاحيات تُفرض بـ RLS. |
| واصل ون (WASEL One) — RADIUS | `infra/radius/`، `supabase/functions/radius-control` | جسر FreeRADIUS لراوترات MikroTik Hotspot. في مرحلة تجربة محدودة (pilot)، غير مُطلق للعموم. |
| الصفحات القانونية | `legal/`، `admin/legal/`، `supabase/functions/public-legal` | سياسة الخصوصية وصفحة طلب حذف الحساب، تُولَّد بـ `scripts/configure_waselnet_public_legal_pages.mjs`. |

### نواقص معروفة (اقرأها قبل أي إطلاق)

- **تسجيل العملاء الذاتي** موجود فقط عبر مسار المختبِرين بالدعوة
  (`supabase/functions/test-onboarding`: رمز دعوة + قائمة أرقام مسموحة + مدة لا
  تتجاوز 14 يوماً). لا يوجد تحقق SMS حقيقي، فلا يصلح هذا المسار لإطلاق عام.
- **الإشعارات الفورية (Push)** غير موصولة من طرف إلى طرف: التطبيق يسجّل رمز الجهاز
  والخادم يكتب الأحداث في `notification_outbox`، ودالة
  `notification-transport-adapter` تستطيع الإرسال عبر FCM، لكن لا يوجد ما يسحب
  الصف من الـ outbox ويستدعي الإرسال. صندوق الإشعارات داخل التطبيق يقرأ من
  `notification_inbox` ولا يعتمد على Push.
- **لوحتا إدارة** موجودتان ويجب اعتماد واحدة. منح أدوار الموظفين
  (`platform_access_grants`) يُطبَّق فقط على حساب هويته الوحيدة Google، وهذا ما
  تستخدمه اللوحة الثابتة `admin/`؛ حساب بريد/كلمة مرور في لوحة Flutter لا يستقبل
  منحة دور.
- **المهام الدورية** (إتمام حذف الحسابات، إغلاق جلسات RADIUS المعلّقة) تُجدول
  تلقائياً فقط إذا كان `pg_cron` مفعّلاً وقت تطبيق الـ migration. **مطابقة المحافظ
  اليومية** (`finance_reconcile_wallets`) غير مجدولة إطلاقاً.
- **التسوية المالية**: «مدفوعة» حالة + مرجع دفع نصي؛ لا يوجد سجل مدفوعات ولا دالة
  تعديل. دفتر العميل قيد مفرد مع رصيد مخزَّن، وليس قيداً مزدوجاً.
- تثبيت GitHub Actions على SHA لم يُنفَّذ بعد (Dependabot مفعّل).

التفاصيل والإجراءات في `docs/OPERATIONS-RUNBOOK.md`.

## التشغيل

المتطلبات: Flutter 3.38.7 (القناة stable)، JDK 17، Node 20+، وللخادم المحلي Docker.

### تطبيق العميل

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

القيم تُقرأ في `lib/core/config/app_config.dart`:

| `--dart-define` | مطلوب؟ | ملاحظة |
|---|---|---|
| `SUPABASE_URL` | نعم | `https` فقط؛ `http` مقبول لـ `localhost` و `127.0.0.1` و `10.0.2.2` (المحاكي) فقط. |
| `SUPABASE_PUBLISHABLE_KEY` | نعم | المفتاح العام فقط. لا تضع مفتاح service-role في أي تطبيق أو صفحة. |
| `PRIVACY_POLICY_URL` | لبناء الإصدار | رابط `https` عام. |
| `ACCOUNT_DELETION_URL` | لبناء الإصدار | رابط `https` عام. |
| `ADMIN_PASSWORD_RECOVERY_REDIRECT_URL` | للوحة Flutter فقط | أصل لوحة الإدارة. |

`flutter run` بلا تعريفات = وضع البيانات التجريبية (debug فقط). بناء حزمة Play:
`scripts/build_waselnet_play_bundle.ps1` و `docs/release/GOOGLE-PLAY-RELEASE-RUNBOOK.md`.

### لوحة الإدارة (Flutter web)

```bash
flutter run -d chrome --target lib/admin_main.dart \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key> \
  --dart-define=ADMIN_PASSWORD_RECOVERY_REDIRECT_URL=http://localhost:7357
```

انظر `docs/admin/ADMIN-WEB-CONSOLE-RUNBOOK.md`.

### لوحة الإدارة الثابتة

انسخ `admin/config.example.js` إلى `admin/config.js` (غير مُتتبَّع في git) واملأ
عنوان المشروع والمفتاح العام، ثم قدّم المجلد بأي خادم ملفات ثابتة. انظر
`admin/README.md` (الأدوار، العمولة، SRI، ترويسات الأمان).

### تطبيق المالك

```bash
cd owner_app
flutter pub get
flutter run
```

لا يحتاج `--dart-define`؛ الإعدادات في `owner_app/lib/utils/constants.dart`.

### واصل ون (RADIUS)

`infra/radius/README.md` و `docs/WASEL-ONE-PILOT-RUNBOOK.md`.

## قاعدة البيانات والاختبارات محلياً

```bash
npx supabase@2.109.1 start
npx supabase@2.109.1 db reset --no-seed

DB=postgresql://postgres:postgres@127.0.0.1:54322/postgres

# مفتاح تشفير الكروت للاختبار المحلي فقط (يُمسح مع كل db reset)
psql "$DB" -v ON_ERROR_STOP=1 -c \
  "select vault.create_secret('TEST_ONLY_LOCAL_CARD_KEY_DO_NOT_USE', 'card_master_key', 'local test key');"

# مجموعات SQL (30 ملفاً)
for f in supabase/tests/*.sql; do
  psql "$DB" -v ON_ERROR_STOP=1 -f "$f" || break
done

# سباقات التزامن على الشراء واعتماد الإيداع (Python القياسي + psql فقط)
DATABASE_URL="$DB" python3 scripts/test_commerce_concurrency.py
```

- `supabase/seed.sql` (حسابات تجريبية بصلاحيات) **لا يُطبَّق تلقائياً** ويرفض العمل
  إلا على قاعدة محلية وبتفعيل صريح؛ الطريق الوحيد:
  `pwsh scripts/reset_netyemen_local_pilot.ps1`.
- `supabase/config.toml` للمحلي و CI فقط (رموز OTP ثابتة، تأكيد البريد معطّل).
  لا تنفّذ `supabase config push` به أبداً.
- الفحص الكامل كما في CI (يعيد ضبط القاعدة المحلية): `pwsh scripts/verify_netyemen_v1_pilot.ps1`.

فحوص ثابتة لا تحتاج قاعدة بيانات:

```bash
pwsh scripts/verify_netyemen_core_foundation.ps1      # RLS و search_path و GRANT في كل الـ migrations
pwsh scripts/scan_netyemen_financial_invariants.ps1   # ثوابت الشراء والإيداع والتسوية
pwsh scripts/scan_netyemen_secrets.ps1                # أسرار مسرّبة
pwsh scripts/scan_netyemen_card_secrets.ps1           # منع تخزين أرقام الكروت نصاً
node scripts/test_admin_console_contract.mjs          # عقد اللوحة الثابتة مع الـ RPC
```

فحوص Flutter: `dart format lib test` ثم `flutter analyze lib test` ثم `flutter test`.

## CI

| سير العمل | متى | ماذا يفعل |
|---|---|---|
| `flutter-ci.yml` | push إلى `main` وطلبات الدمج إليه | lockfile، تنسيق، تحليل، اختبارات، فحص اللوحة الثابتة، APK تجريبي (بيانات تجريبية، باسم `WASEL-NET-DEMO-DEBUG-APK`)، حزمة release بمفتاح مؤقت، بناء لوحة Flutter web. |
| `supabase-core-ci.yml` | push إلى `main` وطلبات الدمج | فحص دوال Edge (Deno)، إعداد و E2E لـ FreeRADIUS، Supabase محلي، كل الـ migrations، مجموعات SQL، سباقات التزامن، ثم الفاحصات الثابتة. |
| `owner-app-ci.yml` | تغييرات `owner_app/` | تنسيق، تحليل، اختبارات، APK debug. |
| `admin-release-gate.yml` | يدوي | فحوص ما قبل إصدار لوحة الإدارة على المشروع الحقيقي (قراءة فقط) وبناء مرشح الإصدار. |

## التوثيق

- `docs/README.md` — فهرس كل الوثائق.
- `docs/OPERATIONS-RUNBOOK.md` — التشغيل: المهام الدورية، المطابقة، التسوية، مفتاح
  الكروت، أول مدير، إعدادات Auth الإلزامية.
- `docs/NETYEMEN-FINANCIAL-OPERATING-CONTRACT-01.md` — العقد المالي مع قسم «حالة التنفيذ».
- `docs/adr/` — قرارات المعمارية.
- `owner_app/README.md`، `admin/README.md`، `infra/radius/README.md` — لكل مكوّن.

## الترخيص

خاص — جميع الحقوق محفوظة.
