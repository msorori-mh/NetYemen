const securityHeaders = {
  "content-type": "text/html; charset=utf-8",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "permissions-policy": "camera=(), microphone=(), geolocation=()",
};

Deno.serve((request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = new URL(request.url);
  const page = url.pathname.split("/").filter(Boolean).at(-1) || "privacy";
  const nonce = crypto.randomUUID().replaceAll("-", "");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const publicOrigin = (supabaseUrl || url.origin)
    .replace(/^http:/, "https:")
    .replace(/\/$/, "");
  const functionRoot = `${publicOrigin}/functions/v1/public-legal`;

  // No third-party script is loaded: the deletion form talks to Supabase Auth
  // and PostgREST with plain fetch(), so the only script that can run on this
  // page (which collects a phone number and a password) is the nonce'd inline
  // script below, and it may connect only to this project's own origin.
  const connectSource = safeOrigin(supabaseUrl) || "'none'";
  const headers = new Headers(securityHeaders);
  headers.set(
    "content-security-policy",
    `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src ${connectSource}; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
  );
  headers.set("cache-control", "no-store");

  const html = page === "delete-account"
    ? deletionPage({ nonce, supabaseUrl, publishableKey, functionRoot })
    : privacyPage({ nonce, functionRoot });

  return new Response(request.method === "HEAD" ? null : html, {
    status: 200,
    headers,
  });
});

function safeOrigin(value: string): string {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" || parsed.protocol === "http:" ? parsed.origin : "";
  } catch {
    return "";
  }
}

interface PageContext {
  nonce: string;
  functionRoot: string;
}

interface DeletionPageContext extends PageContext {
  supabaseUrl: string;
  publishableKey: string;
}

function shell(title: string, body: string, nonce: string): string {
  return `<!doctype html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title} | واصل نت</title>
  <style nonce="${nonce}">
    :root{color-scheme:light;font-family:Tahoma,Arial,sans-serif;background:#f3f7f9;color:#142b38}
    body{margin:0;padding:24px}.card{max-width:760px;margin:32px auto;background:#fff;border:1px solid #d9e3e8;border-radius:20px;padding:28px;box-shadow:0 10px 30px #163c4f12}
    h1,h2{color:#155574}p,li{line-height:1.9}a{color:#087faa}label{display:block;margin:14px 0 6px;font-weight:700}
    input,textarea{box-sizing:border-box;width:100%;padding:12px;border:1px solid #aebfc8;border-radius:10px;font:inherit}.check{width:auto}button{margin-top:18px;width:100%;padding:13px;border:0;border-radius:10px;background:#b42318;color:#fff;font:inherit;font-weight:700;cursor:pointer}button:disabled{opacity:.55;cursor:not-allowed}.note{background:#eef7fa;border-right:4px solid #1683a6;padding:12px}.error{color:#b42318}.success{color:#067647}.muted{color:#5e7079;font-size:.92rem}
  </style>
</head>
<body><main class="card">${body}</main></body>
</html>`;
}

function privacyPage({ nonce, functionRoot }: PageContext): string {
  return shell(
    "سياسة الخصوصية",
    `<h1>سياسة خصوصية واصل نت</h1>
<p class="muted">آخر تحديث: 22 أغسطس 2026</p>
<p>واصل نت منصة تدير اكتشاف شبكات الإنترنت المحلية وطلبات إضافتها وباقاتها وشراء الكروت والمحفظة والإشعارات والدعم.</p>
<h2>البيانات التي نعالجها</h2>
<ul><li>رقم الهاتف والاسم وبيانات الحساب.</li><li>المحافظة والمدينة والموقع الذي يختاره المستخدم عند التسجيل أو طلب إضافة شبكة.</li><li>اسم شبكة Wi-Fi الظاهر SSID عند بدء المستخدم للمسح يدويًا.</li><li>المعاملات وطلبات الإيداع والمشتريات والتسويات وسجلات الدعم.</li><li>رمز الإشعار الخاص بالجهاز عند تفعيل الإشعارات.</li></ul>
<p class="note">لا نخزّن BSSID أو عنوان MAC أو رقم الجهاز أو إحداثيات عملية مسح Wi-Fi.</p>
<h2>الاستخدام والحماية</h2>
<p>نستخدم البيانات لتقديم الخدمة والتحقق من الصلاحيات ومنع الاحتيال وتوفير الدعم. تُقيد الصلاحيات حسب الدور وتُسجل العمليات الحساسة في سجل تدقيق غير قابل للتعديل.</p>
<h2>الاحتفاظ والحذف</h2>
<p>عند طلب حذف الحساب يُغلق الوصول فورًا وتبدأ مهلة تسوية مدتها 30 يومًا. بعدها تُزال البيانات الشخصية. قد تبقى السجلات المالية والتدقيقية المطلوبة نظاميًا بعد فصلها عن البيانات التعريفية.</p>
<h2>حقوق المستخدم والتواصل</h2>
<p>يمكن طلب حذف الحساب من داخل التطبيق أو عبر <a href="${functionRoot}/delete-account">صفحة حذف الحساب</a>. وللاستفسارات الأخرى استخدم مركز الدعم داخل التطبيق أو <a href="https://systrac.lovable.app/">قنوات شركة سيستراك</a>.</p>`,
    nonce,
  );
}

function deletionPage({
  nonce,
  supabaseUrl,
  publishableKey,
  functionRoot,
}: DeletionPageContext): string {
  const configReady = Boolean(supabaseUrl && publishableKey);
  return shell(
    "حذف الحساب",
    `<h1>طلب حذف حساب واصل نت</h1>
<p>هذه الصفحة تتيح طلب حذف الحساب دون الحاجة إلى تثبيت التطبيق. سيُغلق الحساب فورًا وتبدأ مهلة تسوية مدتها 30 يومًا.</p>
<form id="deletion-form" autocomplete="off">
  <label for="phone">رقم الهاتف</label><input id="phone" name="phone" inputmode="tel" autocomplete="username" required placeholder="+9677XXXXXXXX">
  <label for="password">كلمة المرور</label><input id="password" name="password" type="password" autocomplete="current-password" required>
  <label for="reason">سبب الحذف (اختياري)</label><textarea id="reason" name="reason" maxlength="500" rows="3"></textarea>
  <label><input id="confirm" class="check" type="checkbox" required> أفهم أن الحساب سيُغلق فورًا</label>
  <button id="submit" type="submit" ${configReady ? "" : "disabled"}>طلب حذف الحساب</button>
</form>
<p id="result" role="status" aria-live="polite"></p>
<p class="muted"><a href="${functionRoot}/privacy">قراءة سياسة الخصوصية</a></p>
<script nonce="${nonce}">
(() => {
  const supabaseUrl = ${scriptJson(supabaseUrl.replace(/\/+$/, ""))};
  const publishableKey = ${scriptJson(publishableKey)};
  const form = document.getElementById("deletion-form");
  const button = document.getElementById("submit");
  const result = document.getElementById("result");
  const normalizePhone = (value) => {
    const digits = value.replace(/[^0-9]/g, "");
    if (digits.startsWith("967")) return "+" + digits;
    if (digits.startsWith("0")) return "+967" + digits.slice(1);
    if (digits.startsWith("7")) return "+967" + digits;
    return "+" + digits;
  };
  const request = (requestPath, options) => fetch(supabaseUrl + requestPath, {
    method: "POST",
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
    body: options.body,
    headers: Object.assign(
      { apikey: publishableKey, "content-type": "application/json" },
      options.headers || {},
    ),
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    button.disabled = true;
    result.className = "";
    result.textContent = "جارٍ تسجيل الطلب الآمن…";
    let accessToken = "";
    try {
      const authResponse = await request("/auth/v1/token?grant_type=password", {
        body: JSON.stringify({
          phone: normalizePhone(form.phone.value),
          password: form.password.value,
        }),
      });
      if (!authResponse.ok) throw new Error("authentication failed");
      const auth = await authResponse.json();
      accessToken = auth.access_token || "";
      if (!accessToken) throw new Error("missing access token");

      const reason = form.reason.value.trim() || null;
      const deletionResponse = await request("/rest/v1/rpc/request_my_account_deletion", {
        headers: { Authorization: "Bearer " + accessToken },
        body: JSON.stringify({ p_reason: reason }),
      });
      if (!deletionResponse.ok) throw new Error("deletion request failed");

      form.reset();
      result.className = "success";
      result.textContent = "تم استلام طلب الحذف وإغلاق الحساب. تبدأ الآن مهلة 30 يومًا.";
    } catch (_) {
      result.className = "error";
      result.textContent = "تعذر تسجيل الطلب. تحقق من رقم الهاتف وكلمة المرور ثم أعد المحاولة.";
    } finally {
      if (accessToken) {
        await request("/auth/v1/logout", {
          headers: { Authorization: "Bearer " + accessToken },
        }).catch(() => {});
      }
      form.password.value = "";
      button.disabled = false;
    }
  });
})();
</script>`,
    nonce,
  );
}

// JSON for embedding inside an inline <script>: JSON.stringify alone does not
// escape "<", so a value containing "</script>" could break out of the element.
function scriptJson(value: string): string {
  return JSON.stringify(value)
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}
