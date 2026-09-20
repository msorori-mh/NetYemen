(() => {
  const supabaseUrl = {{SUPABASE_URL_JSON}};
  const publishableKey = {{SUPABASE_PUBLISHABLE_KEY_JSON}};
  const form = document.getElementById('deletion-form');
  const button = document.getElementById('submit');
  const result = document.getElementById('result');
  const normalizePhone = (value) => {
    const digits = value.replace(/\D/g, '');
    if (digits.startsWith('967')) return `+${digits}`;
    if (digits.startsWith('0')) return `+967${digits.slice(1)}`;
    if (digits.startsWith('7')) return `+967${digits}`;
    return `+${digits}`;
  };
  const request = async (requestPath, options = {}) => fetch(
    `${supabaseUrl}${requestPath}`,
    {
      ...options,
      headers: {
        apikey: publishableKey,
        'content-type': 'application/json',
        ...(options.headers || {}),
      },
    },
  );

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    button.disabled = true;
    result.className = '';
    result.textContent = 'جارٍ تسجيل الطلب الآمن…';
    let accessToken = '';
    try {
      const authResponse = await request('/auth/v1/token?grant_type=password', {
        method: 'POST',
        body: JSON.stringify({
          phone: normalizePhone(form.phone.value),
          password: form.password.value,
        }),
      });
      if (!authResponse.ok) throw new Error('authentication failed');
      const auth = await authResponse.json();
      accessToken = auth.access_token || '';
      if (!accessToken) throw new Error('missing access token');

      const reason = form.reason.value.trim() || null;
      const deletionResponse = await request(
        '/rest/v1/rpc/request_my_account_deletion',
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${accessToken}` },
          body: JSON.stringify({ p_reason: reason }),
        },
      );
      if (!deletionResponse.ok) throw new Error('deletion request failed');

      form.reset();
      result.className = 'success';
      result.textContent =
        'تم استلام طلب الحذف وإغلاق الحساب. تبدأ الآن مهلة 30 يومًا.';
    } catch (_) {
      result.className = 'error';
      result.textContent =
        'تعذر تسجيل الطلب. تحقق من رقم الهاتف وكلمة المرور ثم أعد المحاولة.';
    } finally {
      if (accessToken) {
        await request('/auth/v1/logout', {
          method: 'POST',
          headers: { Authorization: `Bearer ${accessToken}` },
        }).catch(() => {});
      }
      form.password.value = '';
      button.disabled = false;
    }
  });
})();
