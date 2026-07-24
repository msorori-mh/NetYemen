# NetYemen 🇾🇪

> منصة بيع كروت الإنترنت للشبكات المحلية في اليمن

## الفكرة

NetYemen هي منصة رقمية وطنية تربط أصحاب الشبكات المحلية للإنترنت في اليمن بالمستخدمين النهائيين، لتسهيل:
- استكشاف الشبكات القريبة ومقارنة الأسعار
- شراء كروت الاشتراك إلكترونياً من محفظة داخلية
- استلام الكرت فوراً داخل التطبيق (رقم الكرت)

## التطبيقات

| التطبيق | الجمهور | التقنية | الحالة |
|---------|---------|---------|--------|
| **NetYemen Customer** | العملاء | Flutter 3.x | 🟡 قيد التطوير |
| **NetYemen Owner** | أصحاب الشبكات | Flutter 3.x | 🔴 لم يبدأ |
| **NetYemen Admin** | الإدارة | Lovable (Web) | 🔴 لم يبدأ |

## التقنيات

- **Flutter 3.x** + Dart
- **Riverpod** — State Management
- **Supabase** — Backend + Auth + Realtime + Storage
- **ALAWAEL SMS API** — OTP (لاحقاً)
- **Firebase Cloud Messaging** — Push Notifications (لاحقاً)

## نموذج الكرت في اليمن

> ⚠️ هذا مهم جداً للتصميم التقني

- الكرت = **رقم فريد فقط** (مثلاً: `1234567890`)
- لا يوجد "اسم مستخدم + كلمة مرور" منفصلان
- المستخدم يدخل الرقم في صفحة Hotspot

## هيكل المشروع

```
netyemen/
├── docs/
│   ├── PROJECT_CONTEXT.md      ← السياق الكامل
│   └── PROMPT_TEMPLATE.md      ← قالب الجلسات الجديدة
├── sql/
│   └── netyemen_schema_fixed.sql  ← قاعدة البيانات
├── lib/
│   ├── main.dart
│   ├── utils/
│   │   ├── constants.dart      ← Supabase Keys
│   │   └── app_theme.dart      ← الألوان والأنماط
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── network_model.dart
│   │   └── card_model.dart
│   ├── services/
│   │   └── supabase_service.dart
│   ├── providers/
│   │   └── app_providers.dart
│   └── screens/
│       ├── splash_screen.dart
│       ├── auth/
│       │   ├── login_screen.dart
│       │   └── otp_screen.dart
│       ├── main_screen.dart
│       ├── home/
│       │   ├── home_screen.dart
│       │   ├── network_detail_screen.dart
│       │   └── purchase_success_screen.dart
│       ├── wallet/
│       │   ├── wallet_screen.dart
│       │   └── deposit_screen.dart
│       ├── purchases/
│       │   └── purchases_screen.dart
│       └── profile/
│           └── profile_screen.dart
├── pubspec.yaml
└── README.md
```

## الألوان

| اللون | الكود | الاستخدام |
|-------|-------|-----------|
| Primary | `#1E3A5F` | الهوية البصرية |
| Accent | `#2ECC71` | أزرار الشراء والنجاح |
| Error | `#E74C3C` | الأخطاء |
| Warning | `#F39C12` | التنبيهات |

## التشغيل

```bash
# 1. تثبيت التبعيات
flutter pub get

# 2. تحديث Supabase URL و Anon Key في lib/utils/constants.dart

# 3. تشغيل
flutter run
```

## قاعدة البيانات

انظر `sql/netyemen_schema_fixed.sql` — يحتوي على:
- 11 جدول
- 4 دوال (شراء كرت ذري، معالجة شحن، إلخ)
- RLS Policies
- Realtime
- Seed Data

## المساهمة

هذا المشروع يُدار من قبل @msorori-mh

## الترخيص

Private — جميع الحقوق محفوظة
