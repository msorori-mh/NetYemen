# لوحة إدارة واصل نت (Static admin console)

صفحة ثابتة (`index.html` + `app.js` + `styles.css`) تُنشر على Vercel وتتصل بـ Supabase
عبر دوال RPC المعرّفة في `supabase/migrations`. لا توجد خطوة بناء ولا اعتماديات.

- `config.js` (غير مُتتبَّع): انسخ `config.example.js` واملأ عنوان المشروع والمفتاح العام فقط.
- الصلاحيات يفرضها الخادم داخل كل RPC. إخفاء الأقسام حسب الدور في الواجهة تجربة استخدام لا أكثر.

## الأدوار المسموح لها بالدخول

| الدور | الأقسام الظاهرة |
| --- | --- |
| `platform_admin` | كل الأقسام |
| `finance_officer` | وجهات الدفع، طلبات الشحن، تصفية المستحقات، إعدادات العمولة (قراءة فقط) |
| `support_agent` | لوحة القيادة (المؤشرات التشغيلية فقط) |

## العمولة: نسبة مئوية في الواجهة، كسر في الخادم

الواجهة تعرض وتستقبل نسبة مئوية (0–100). الخادم (`get_platform_commission_config` و
`admin_update_default_commission_rate`) يتعامل بكسر بين 0 و 1 (`0.03` = 3%). التحويل محصور في
`commissionPercentToFraction` / `commissionFractionToPercentText` داخل `app.js`، ويغطيه اختبار العقد.

## اختبار العقد مع قاعدة البيانات

```sh
node scripts/test_admin_console_contract.mjs
```

يفحص أن كل RPC يستدعيها `app.js` موجودة في الـ migrations بأسماء معاملاتها، وأن حالات
التصفية والعمولة مطابقة للخادم. شغّله بعد أي تعديل على `app.js` أو على الـ migrations.

## Subresource Integrity لمكتبة supabase-js (TODO)

`index.html` يحمّل `@supabase/supabase-js@2.45.4` من jsDelivr بإصدار مثبّت و
`crossorigin="anonymous"`، لكن **بدون** سمة `integrity` بعد. احسب التجزئة من الملف الفعلي:

```sh
curl -s https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js | openssl dgst -sha384 -binary | openssl base64 -A
```

ثم ألصق الناتج في وسم السكربت داخل `admin/index.html` (مكان تعليق `TODO(SRI)`):

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js"
        integrity="sha384-<الناتج>" crossorigin="anonymous"></script>
```

عند ترقية الإصدار غيّر الرابط والتجزئة معاً. لا تضع تجزئة لم تحسبها من الملف نفسه:
تجزئة خاطئة تمنع تحميل المكتبة فتتعطل اللوحة كلها.

## ترويسات الأمان (`vercel.json`)

- `Content-Security-Policy` للّوحة: السكربتات من نفس الأصل ومن `cdn.jsdelivr.net` فقط، والاتصال
  بـ `https://*.supabase.co` و `wss://*.supabase.co` فقط. إن استُخدم نطاق Supabase مخصّص
  فأضفه إلى `connect-src` وإلا ستفشل كل الطلبات.
- `style-src 'unsafe-inline'` مطلوبة لأن `index.html` و `app.js` يستخدمان سمات `style` مضمّنة.
- ممنوع إضافة `<script>` مضمّن أو سمات أحداث مضمّنة (`onclick=` ...): الـ CSP ستحجبها. اربط
  الأحداث من `app.js`.
- مسار `/legal/*` له CSP أشد خاصة به، ومستثنى من CSP اللوحة حتى لا تُرسل ترويستان.
