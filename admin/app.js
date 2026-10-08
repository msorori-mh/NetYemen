(function () {
  'use strict';

  if (!window.NETYEMEN_CONFIG) {
    document.body.innerHTML =
      '<div style="padding:40px;font-family:sans-serif">' +
      '<h2>الإعداد ناقص</h2><p>انسخ <code>config.example.js</code> إلى <code>config.js</code> واملأ عنوان المشروع والمفتاح العام.</p></div>';
    return;
  }

  var cfg = window.NETYEMEN_CONFIG;
  var db = window.supabase.createClient(cfg.url, cfg.anonKey, {
    auth: {
      flowType: 'pkce',
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: 'netyemen-admin-auth'
    }
  });

  // ---------- أدوات UI ----------

  var toastContainer = document.getElementById('toast-container');
  function toast(message, isError) {
    var t = document.createElement('div');
    t.className = 'toast' + (isError ? ' err' : '');
    t.innerHTML = (isError ? '⚠️' : '✅') + ' <span>' + esc(message) + '</span>';
    toastContainer.appendChild(t);
    setTimeout(function() {
      t.classList.add('closing');
      setTimeout(function() { t.remove(); }, 300);
    }, 5000);
  }

  var modalOverlay = document.getElementById('modal-overlay');
  var modalTitle = document.getElementById('modal-title');
  var modalBody = document.getElementById('modal-body');
  var modalFooter = document.getElementById('modal-footer');
  var modalClose = document.getElementById('modal-close');

  function openModal(title, bodyContent, footerHtml) {
    return new Promise(function(resolve) {
      modalTitle.textContent = title;
      if (typeof bodyContent === 'string') {
        modalBody.innerHTML = bodyContent;
      } else {
        modalBody.innerHTML = '';
        modalBody.appendChild(bodyContent);
      }
      modalFooter.innerHTML = footerHtml;
      modalOverlay.classList.add('on');

      var cleanup = function(value) {
        modalOverlay.classList.remove('on');
        modalClose.onclick = null;
        resolve(value);
      };

      modalClose.onclick = function() { cleanup(null); };

      var actions = modalFooter.querySelectorAll('[data-action]');
      for (var i = 0; i < actions.length; i++) {
        actions[i].onclick = function(e) {
          cleanup(e.currentTarget.dataset.action);
        };
      }

      // التركيز على أول حقل إدخال (أو زر الإغلاق) لتسهيل استخدام لوحة المفاتيح
      var firstField = modalBody.querySelector('input, select, textarea');
      try { (firstField || modalClose).focus(); } catch (e) {}
    });
  }

  // إغلاق النافذة بمفتاح Escape (يعادل زر الإغلاق = إلغاء)
  document.addEventListener('keydown', function (e) {
    if ((e.key === 'Escape' || e.key === 'Esc') && modalOverlay.classList.contains('on') && modalClose.onclick) {
      e.preventDefault();
      modalClose.onclick();
    }
  });

  function asyncConfirm(message) {
    return openModal('تأكيد', '<p>' + esc(message) + '</p>',
      '<button class="btn btn-ghost" data-action="false">إلغاء</button>' +
      '<button class="btn btn-primary" data-action="true">موافق</button>'
    ).then(function(res) { return res === 'true'; });
  }

  function asyncPrompt(message, type) {
    var div = document.createElement('div');
    div.innerHTML = '<p>' + esc(message) + '</p><input type="' + (type || 'text') + '" id="prompt-input" class="w-full mt-2">';
    return openModal('إدخال', div,
      '<button class="btn btn-ghost" data-action="cancel">إلغاء</button>' +
      '<button class="btn btn-primary" data-action="ok">حفظ</button>'
    ).then(function(res) {
      if (res === 'ok') {
        return document.getElementById('prompt-input').value.trim();
      }
      return null;
    });
  }

  var GENERIC_ERROR = 'حدث خطأ غير متوقع، حاول لاحقاً';

  // يحدّد إن كانت الرسالة تقنية (JavaScript / شبكة / SQL) فلا نعرضها للمستخدم
  function isTechnicalError(raw) {
    if (!raw) return true;
    if (/is not a function|undefined|null|cannot read|typeerror|referenceerror|syntaxerror|\.map|stack|network ?error|fetch|json|<[a-z]/i.test(raw)) return true;
    // رسالة بلا أي أحرف عربية غالباً تقنية (رسائل النظام الموجّهة للمستخدم عربية)
    if (!/[؀-ۿ]/.test(raw)) return true;
    return false;
  }

  function errText(e) {
    var raw = (e && (e.message || e.error_description)) || String(e);
    // الرموز الأكثر تحديداً أولاً (المطابقة بالاحتواء، وأول تطابق يفوز)
    var known = {
      UNAUTHENTICATED: 'انتهت الجلسة، سجّل الدخول من جديد',
      FORBIDDEN_SELF_APPROVAL: 'لا يمكنك الموافقة على دفعة أنشأتها أنت — يجب أن يوافق موظف آخر',
      SELF_REVIEW_FORBIDDEN: 'لا يمكنك مراجعة طلب شحن قدّمته أنت',
      SELF_LOCKOUT_BLOCKED: 'لا يمكنك سحب صلاحيتك أو إيقاف حسابك بنفسك',
      LAST_ADMIN_BLOCKED: 'لا يمكن إزالة آخر مدير منصة نشط',
      DUPLICATE_REFERENCE: 'رقم المرجع هذا سبق اعتماده لطلب آخر على نفس الوجهة',
      REJECTION_REASON_REQUIRED: 'سبب الرفض مطلوب',
      WALLET_ACCOUNT_MISSING: 'لا توجد محفظة لهذا العميل',
      INVALID_STATUS_FILTER: 'فلتر الحالة غير صالح',
      INVALID_STATE_FILTER: 'فلتر الحالة غير صالح',
      INVALID_PERIOD: 'الفترة غير صحيحة: تاريخ البداية يجب أن يسبق تاريخ النهاية',
      INVALID_RATE: 'نسبة العمولة يجب أن تكون بين 0% و 100%',
      INVALID_ROLE: 'هذا الدور لا يمكن منحه من هنا',
      INVALID_PROVIDER_TYPE: 'نوع وجهة الدفع غير صالح',
      INVALID_CARD: 'أحد الكروت غير صالح (فارغ، أطول من 64 خانة، أو يحتوي مسافات)',
      TOO_MANY_CARDS: 'عدد الكروت يتجاوز الحد الأقصى (5000) في الدفعة الواحدة',
      INACTIVE_PROFILE: 'حسابك غير نشط',
      RATE_LIMITED: 'تجاوزت الحد اليومي، حاول لاحقاً',
      FORBIDDEN: 'لا تملك صلاحية لهذا الإجراء',
      NOT_FOUND: 'العنصر غير موجود',
      INVALID_STATE: 'الحالة الحالية لا تسمح بهذا الإجراء',
      INVALID_PIN: 'الرمز يجب أن يكون 6 أرقام',
      PIN_ALREADY_SET: 'الرمز مضبوط مسبقاً',
      PIN_NOT_SET: 'لم يتم ضبط رمز بعد'
    };
    for (var key in known) {
      if (raw.indexOf(key) !== -1) return known[key];
    }
    if (isTechnicalError(raw)) return GENERIC_ERROR;
    return raw;
  }

  // رسالة خطأ ودّية للمستخدم + تسجيل التفاصيل التقنية في الـ console
  function reportError(e, friendly) {
    console.error(friendly || 'NetYemen admin error:', e);
    return friendly || errText(e);
  }

  // مؤشر تحميل (spinner) دائري
  function spinnerHtml(label) {
    return '<div class="loading-wrap"><div class="spinner" role="status" aria-label="جارٍ التحميل"></div>' +
      (label ? '<p class="loading-label">' + esc(label) + '</p>' : '') + '</div>';
  }

  function esc(v) {
    return String(v === null || v === undefined ? '' : v)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // حالة خطأ ظاهرة داخل القسم: فشل التحميل لا يُعرض أبداً كجدول فارغ «لا توجد بيانات»
  function errorBox(e, label) {
    return '<div class="load-error" role="alert"><strong>' + esc(label || 'تعذّر تحميل البيانات') + '</strong>' +
      '<span>' + esc(errText(e)) + '</span></div>';
  }

  // يحوّل الوعد إلى { ok, data } أو { ok: false, error } حتى يعرض كل قسم خطأه بنفسه
  function settle(promise) {
    return Promise.resolve(promise).then(
      function (data) { return { ok: true, data: data }; },
      function (e) { console.error('NetYemen admin: load failed', e); return { ok: false, error: e }; }
    );
  }

  // استعلام جدول مباشر (PostgREST) كوعد يرمي الخطأ بدل إرجاعه داخل النتيجة
  function query(builder) {
    return builder.then(function (r) {
      if (r.error) throw r.error;
      return r.data || [];
    });
  }

  function money(n) { return (Number(n) || 0).toLocaleString('en-US'); }
  function when(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    return d.getFullYear() + '/' + (d.getMonth() + 1) + '/' + d.getDate();
  }
  function whenFull(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    function p2(n) { return (n < 10 ? '0' : '') + n; }
    return when(iso) + ' ' + p2(d.getHours()) + ':' + p2(d.getMinutes());
  }
  function badge(text, kind) { return '<span class="badge b-' + kind + '">' + esc(text) + '</span>'; }

  var STATUS_STYLE = {
    active: ['نشطة', 'ok'], verified: ['موثّقة', 'ok'], approved: ['مقبول', 'ok'], completed: ['مكتمل', 'ok'], paid: ['مدفوع', 'ok'],
    pending: ['قيد الانتظار', 'warn'], under_review: ['قيد المراجعة', 'warn'], ready_for_review: ['جاهزة للمراجعة', 'warn'],
    pending_verification: ['بانتظار التحقق', 'warn'],
    unverified: ['غير موثّقة', 'warn'], draft: ['مسودة', 'mute'], inactive: ['معطّلة', 'mute'], archived: ['مؤرشفة', 'mute'],
    cancelled: ['ملغى', 'mute'], corrected: ['مصحّحة', 'mute'], anonymized: ['مجهّل', 'mute'], suspended: ['موقوفة', 'err'], rejected: ['مرفوض', 'err'], failed: ['فشل', 'err'], refunded: ['مسترد', 'warn']
  };
  function statusBadge(status) {
    var s = STATUS_STYLE[status] || [status, 'mute'];
    return badge(s[0], s[1]);
  }

  var PROVIDER_LABELS = {
    bank_account: 'حساب بنكي',
    mobile_wallet: 'محفظة إلكترونية',
    manual_transfer: 'حوالة / صرافة',
    other: 'أخرى'
  };
  function providerLabel(t) { return PROVIDER_LABELS[t] || t; }

  var GOVERNORATES = [
    'أمانة العاصمة', 'صنعاء', 'عدن', 'تعز', 'الحديدة', 'إب', 'ذمار', 'حجة', 'صعدة',
    'عمران', 'لحج', 'أبين', 'شبوة', 'حضرموت', 'المهرة', 'الجوف', 'مأرب', 'البيضاء',
    'الضالع', 'ريمة', 'المحويت', 'سقطرى'
  ];

  function rpc(name, params) {
    return db.rpc(name, params || {}).then(function (r) {
      if (r.error) throw r.error;
      return r.data;
    });
  }

  function table(headers, rows) {
    if (!rows || !rows.length) return '<div class="empty"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg><p>لا توجد بيانات</p></div>';
    return '<div class="table-wrapper"><table><thead><tr>' +
      headers.map(function (h) { return '<th>' + esc(h) + '</th>'; }).join('') +
      '</tr></thead><tbody>' + rows.join('') + '</tbody></table></div>';
  }

  // ---------- المصادقة ----------

  var loginEl = document.getElementById('login');
  var shellEl = document.getElementById('shell');
  document.getElementById('google-signin').onclick = function () {
    this.disabled = true;
    db.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin }
    })
      .then(function (r) { if (r.error) throw r.error; })
      .catch(function (e) {
        toast(errText(e), true);
        document.getElementById('google-signin').disabled = false;
      });
  };

  // يمسح علامة «جهاز موثوق» لرمز الحماية حتى يُطلب الرمز من جديد بعد تسجيل الخروج
  function clearPinTrust() {
    try {
      var doomed = [];
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && k.indexOf('pin_trusted_') === 0) doomed.push(k);
      }
      doomed.forEach(function (k) { localStorage.removeItem(k); });
    } catch (e) {}
  }

  document.getElementById('logout').onclick = function () {
    clearPinTrust();
    var reload = function () { location.reload(); };
    db.auth.signOut().then(reload, reload);
  };

  // ---------- الأدوار ----------
  // الخادم هو من يفرض الصلاحيات في كل RPC؛ ما هنا تجربة استخدام فقط (إخفاء ما لا يُسمح به).
  var STAFF_ROLES = ['platform_admin', 'finance_officer', 'support_agent'];
  var STAFF_ROLE_LABELS = { platform_admin: 'مدير المنصة', finance_officer: 'موظف مالية', support_agent: 'دعم فني' };
  // الأقسام المسموحة لكل دور، مشتقّة من فحوص الأدوار داخل دوال الخادم:
  //  - finance_officer: كل دوال هذه الأقسام تتحقق من is_finance_or_admin (والعمولة للقراءة فقط).
  //  - support_agent: الدالة الوحيدة التي تسمح له هنا هي admin_dashboard_kpis.
  var ROLE_VIEWS = {
    finance_officer: ['destinations', 'deposits', 'settlements', 'commission'],
    support_agent: ['dashboard']
  };
  var currentRoles = {};
  var currentUserId = null;

  function hasRole(role) { return currentRoles[role] === true; }
  function isPlatformAdmin() { return hasRole('platform_admin'); }
  function canView(name) {
    if (isPlatformAdmin()) return true;
    for (var i = 0; i < STAFF_ROLES.length; i++) {
      var allowed = ROLE_VIEWS[STAFF_ROLES[i]];
      if (allowed && hasRole(STAFF_ROLES[i]) && allowed.indexOf(name) !== -1) return true;
    }
    return false;
  }

  function applyRoleNav() {
    var nav = document.querySelector('.sidebar-nav');
    if (!nav) return;
    var group = null;
    var groupHasVisible = false;
    Array.prototype.forEach.call(nav.children, function (el) {
      if (el.classList.contains('nav-group')) {
        if (group) group.hidden = !groupHasVisible;
        group = el;
        groupHasVisible = false;
        return;
      }
      var name = el.getAttribute('data-view');
      if (!name) return;
      var ok = canView(name);
      el.hidden = !ok;
      if (ok) groupHasVisible = true;
    });
    if (group) group.hidden = !groupHasVisible;
  }

  function onSignedIn() {
    return Promise.all(STAFF_ROLES.map(function (role) {
      return rpc('has_platform_role', { p_role: role });
    })).then(function (flags) {
      currentRoles = {};
      var anyRole = false;
      var allExplicitlyFalse = true;
      STAFF_ROLES.forEach(function (role, i) {
        if (flags[i] === true) { currentRoles[role] = true; anyRole = true; }
        if (flags[i] !== false) allExplicitlyFalse = false;
      });
      // نسجّل الخروج فقط عندما يُرجع الخادم false صراحةً لكل الأدوار
      if (allExplicitlyFalse) {
        toast('هذا الحساب لا يملك صلاحية إدارة أو مالية أو دعم', true);
        clearPinTrust();
        return db.auth.signOut().then(function () {
          shellEl.classList.remove('on');
          loginEl.style.display = '';
        });
      }
      if (!anyRole) throw new Error('has_platform_role returned an unexpected value');
      applyRoleNav();
      return db.auth.getUser().then(function (r) {
        var user = r.data.user;
        currentUserId = (user && user.id) || null;
        var roleNames = STAFF_ROLES.filter(hasRole).map(function (role) { return STAFF_ROLE_LABELS[role]; }).join('، ');
        document.getElementById('whoami').textContent = ((user && (user.email || user.phone)) || '') + (roleNames ? ' — ' + roleNames : '');
        loginEl.style.display = 'none';
        return runPinGate(user && user.id).catch(function (e) {
          console.error('NetYemen admin: PIN gate failed', e);
          toast(errText(e), true);
          pinGateEl.classList.remove('on');
          loginEl.style.display = '';
        });
      });
    }).catch(function(e) {
      // خطأ عابر (شبكة/انقطاع) — لا نسجّل الخروج حتى لا يبدو المستخدم مطروداً عند كل تحديث
      console.error('NetYemen admin: has_platform_role check failed (transient), keeping session', e);
      toast('تعذّر التحقق من الصلاحية، تحقّق من الاتصال وحاول مجدداً', true);
    });
  }

  // ---------- قفل الرمز (PIN) ----------
  // البوابة تُشغَّل بعد تأكيد أحد أدوار الطاقم (STAFF_ROLES) وقبل عرض الواجهة. لا قفل خمول
  // هنا (خاص بتطبيق المالك/المشغّل فقط) — فقط اكتشاف جهاز جديد + نسيت الرمز.

  var pinGateEl = document.getElementById('pin-gate');
  var pinSetupStep = document.getElementById('pin-setup-step');
  var pinEntryStep = document.getElementById('pin-entry-step');
  var pinGateTitle = document.getElementById('pin-gate-title');
  var pinGateSub = document.getElementById('pin-gate-sub');

  function pinTrustedKey(userId) { return 'pin_trusted_' + userId; }
  function isDeviceTrusted(userId) {
    try { return localStorage.getItem(pinTrustedKey(userId)) === '1'; } catch (e) { return false; }
  }
  function trustDevice(userId) {
    try { localStorage.setItem(pinTrustedKey(userId), '1'); } catch (e) {}
  }

  function enterShellAfterPin() {
    pinGateEl.classList.remove('on');
    shellEl.classList.add('on');
    route();
  }

  function runPinGate(userId) {
    return rpc('has_account_pin').then(function (has) {
      if (!has) return showPinSetup(userId);
      if (isDeviceTrusted(userId)) return enterShellAfterPin();
      return showPinEntry(userId);
    });
  }

  function showPinSetup(userId) {
    pinGateEl.classList.add('on');
    pinEntryStep.style.display = 'none';
    pinSetupStep.style.display = '';
    pinGateTitle.textContent = 'إنشاء رمز الحماية';
    pinGateSub.textContent = 'رمز من 6 أرقام يُطلب منك عند الدخول من جهاز جديد';

    var p1 = document.getElementById('pin-setup-1');
    var p2 = document.getElementById('pin-setup-2');
    var err = document.getElementById('pin-setup-err');
    p1.value = ''; p2.value = ''; err.style.display = 'none';

    var btn = document.getElementById('pin-setup-submit');
    btn.disabled = false;
    btn.onclick = function () {
      var pin1 = p1.value.trim();
      var pin2 = p2.value.trim();
      err.style.display = 'none';
      if (!/^[0-9]{6}$/.test(pin1)) { err.textContent = 'الرمز يجب أن يكون 6 أرقام'; err.style.display = ''; return; }
      if (pin1 !== pin2) { err.textContent = 'الرمزان غير متطابقين'; err.style.display = ''; p2.value = ''; return; }
      btn.disabled = true;
      rpc('set_account_pin', { p_pin: pin1 }).then(function () {
        trustDevice(userId);
        enterShellAfterPin();
      }).catch(function (e) {
        err.textContent = errText(e); err.style.display = '';
      }).finally(function () { btn.disabled = false; });
    };
  }

  function showPinEntry(userId) {
    pinGateEl.classList.add('on');
    pinSetupStep.style.display = 'none';
    pinEntryStep.style.display = '';
    pinGateTitle.textContent = 'أدخل رمز الحماية';
    pinGateSub.textContent = 'جهاز جديد — أدخل الرمز المكوّن من 6 أرقام';

    var input = document.getElementById('pin-entry-code');
    var err = document.getElementById('pin-entry-err');
    input.value = ''; err.style.display = 'none';

    var btn = document.getElementById('pin-entry-submit');
    btn.disabled = false;
    btn.onclick = function () {
      var pin = input.value.trim();
      err.style.display = 'none';
      if (!/^[0-9]{6}$/.test(pin)) { err.textContent = 'أدخل رمزاً من 6 أرقام'; err.style.display = ''; return; }
      btn.disabled = true;
      rpc('verify_account_pin', { p_pin: pin }).then(function (ok) {
        if (ok) { trustDevice(userId); enterShellAfterPin(); return; }
        err.textContent = 'رمز غير صحيح'; err.style.display = ''; input.value = '';
      }).catch(function (e) {
        var msg = (e && e.message) || String(e);
        err.textContent = msg.indexOf('PIN_LOCKED') !== -1 ? 'محاولات كثيرة — حاول بعد 15 دقيقة' : errText(e);
        err.style.display = '';
      }).finally(function () { btn.disabled = false; });
    };

    document.getElementById('pin-forgot').onclick = function () {
      var b = this; b.disabled = true;
      rpc('request_pin_reset').then(function () {
        toast('أُرسل طلب إعادة التعيين إلى المدير');
      }).catch(function (e) { toast(errText(e), true); }).finally(function () { b.disabled = false; });
    };
  }

  // ---------- التوجيه ----------

  var viewEl = document.getElementById('view');
  var views = {};

  var menuToggle = document.getElementById('menu-toggle');
  var sidebar = document.querySelector('.sidebar');
  if(menuToggle && sidebar) {
    menuToggle.onclick = function() { sidebar.classList.toggle('open'); };
  }

  // hasOwnProperty حتى لا تُحلّ مسارات مثل '#constructor' أو '#toString' إلى خصائص موروثة
  function hasView(name) {
    return Object.prototype.hasOwnProperty.call(views, name) && typeof views[name] === 'function';
  }

  function defaultView() {
    var order = ['dashboard', 'deposits'];
    for (var i = 0; i < order.length; i++) {
      if (hasView(order[i]) && canView(order[i])) return order[i];
    }
    return null;
  }

  function route() {
    var name = (location.hash || '').slice(1);
    if (!hasView(name) || !canView(name)) name = defaultView();
    if (!name) {
      viewEl.innerHTML = '<div class="card"><h2>لا توجد أقسام متاحة</h2>' +
        '<p class="text-muted">دورك الحالي لا يملك أقساماً في هذه اللوحة.</p></div>';
      return;
    }
    Array.prototype.forEach.call(document.querySelectorAll('.sidebar-nav a'), function (a) {
      a.classList.toggle('active', a.dataset.view === name);
      if (a.dataset.view === name) document.getElementById('page-title').textContent = a.textContent;
    });
    if(sidebar) sidebar.classList.remove('open');
    viewEl.innerHTML = spinnerHtml('جارٍ التحميل…');

    Promise.resolve()
      .then(function () { return views[name](); })
      .catch(function (e) {
        console.error('NetYemen admin: view "' + name + '" failed to load', e);
        viewEl.innerHTML = '<div class="card"><h2>تعذّر التحميل</h2>' +
          '<p class="text-muted">' + esc(errText(e)) + '</p>' +
          '<button class="btn btn-ghost mt-2" id="view-retry">إعادة المحاولة</button></div>';
        var retry = document.getElementById('view-retry');
        if (retry) retry.onclick = function () { route(); };
      });
  }

  window.addEventListener('hashchange', route);

  function bindActionAsync(attr, run, successText) {
    Array.prototype.forEach.call(viewEl.querySelectorAll('[data-' + attr + ']'), function (btn) {
      btn.onclick = function () {
        var p = run(btn.getAttribute('data-' + attr));
        if (!p || !p.then) return;
        btn.disabled = true;
        p.then(function (res) {
          if (res === false) { btn.disabled = false; return; } // user cancelled modal
          toast(typeof successText === 'function' ? successText(res) : successText); 
          route(); 
        }).catch(function (e) { console.error('NetYemen admin action failed:', e); toast(errText(e), true); btn.disabled = false; });
      };
    });
  }

  // --- VIEWS ---
  
  views.dashboard = function () {
    // admin_dashboard_kpis: platform_admin أو support_agent. get_commerce_admin_summary: platform_admin فقط.
    var showCommerce = isPlatformAdmin();
    return Promise.all([
      settle(rpc('admin_dashboard_kpis')),
      showCommerce ? settle(rpc('get_commerce_admin_summary')) : Promise.resolve(null)
    ]).then(function (res) {
      var KPI_LABELS = {
        active_networks: 'شبكات نشطة', pending_requests: 'طلبات معلّقة', approved_requests: 'طلبات مقبولة',
        rejected_requests: 'طلبات مرفوضة', active_packages: 'باقات نشطة', out_of_stock_packages: 'باقات نفد مخزونها',
        network_owners: 'ملاك شبكات', network_operators: 'مشغّلون'
      };

      // المفاتيح كما يُرجعها get_commerce_admin_summary (كلها بالريال اليمني عدا عدد العمليات)
      var COMM_LABELS = {
        total_gross_sales: 'إجمالي المبيعات المكتملة (ر.ي)',
        total_completed_purchases: 'عمليات شراء مكتملة',
        total_pending_deposits: 'طلبات شحن بانتظار المراجعة (ر.ي)',
        total_customer_liability: 'أرصدة محافظ العملاء (ر.ي)'
      };

      function kpiSection(result, labels) {
        if (!result.ok) return errorBox(result.error, 'تعذّر تحميل المؤشرات');
        var data = result.data || {};
        var cards = Object.keys(labels).map(function (k) {
          if (data[k] === undefined || data[k] === null) return '';
          return '<div class="kpi"><div class="n">' + money(data[k]) + '</div><div class="l">' + esc(labels[k]) + '</div></div>';
        }).join('');
        if (!cards) return errorBox(new Error('empty'), 'لم يُرجع الخادم أي مؤشرات');
        return '<div class="kpis">' + cards + '</div>';
      }

      viewEl.innerHTML =
        '<div class="mb-4"><h3>المؤشرات التشغيلية</h3></div><div class="mb-6">' + kpiSection(res[0], KPI_LABELS) + '</div>' +
        (res[1] ? '<div class="mb-4 mt-6"><h3>المؤشرات المالية (Commerce)</h3></div>' + kpiSection(res[1], COMM_LABELS) : '');
    });
  };

  // ---------- الشبكات ----------
  views.networks = function () {
    return db.from('networks').select('*').order('created_at', { ascending: false }).then(function (r) {
      if (r.error) throw r.error;
      var rows = r.data.map(function (n) {
        var actions = '';
        if (n.status !== 'active') actions += '<button class="btn btn-sm btn-accent" data-approve="' + esc(n.id) + '">موافقة</button>';
        if (n.status === 'active') actions += '<button class="btn btn-sm btn-danger" data-suspend="' + esc(n.id) + '">إيقاف</button>';
        return '<tr><td>' + esc(n.commercial_name) + '</td><td>' + esc([n.governorate, n.city, n.district].filter(Boolean).join(' - ')) + '</td><td>' + statusBadge(n.status) + '</td><td>' + statusBadge(n.verification_status) + '</td><td>' + when(n.created_at) + '</td><td class="actions">' + actions + '</td></tr>';
      });
      viewEl.innerHTML = '<div class="card">' +
        '<div class="flex gap-4 mb-4" style="justify-content:space-between; align-items:center;">' +
        '<h3 style="margin:0">الشبكات</h3><button class="btn btn-primary" id="n-add">إنشاء شبكة جديدة</button></div>' +
        table(['الاسم', 'الموقع', 'الحالة', 'التوثيق', 'أُنشئت', 'إجراء'], rows) + '</div>';

      var btnAdd = document.getElementById('n-add');
      if (btnAdd) {
        btnAdd.onclick = function() {
          var div = document.createElement('div');
          div.innerHTML = '<div class="grid grid-1 mb-4" style="gap:10px">' +
            '<div><label>الاسم التجاري <span class="text-error">*</span></label><input id="cn-name"></div>' +
            '<div><label>الوصف</label><input id="cn-desc"></div>' +
            '<div><label>المحافظة</label><select id="cn-gov"><option value="">اختر المحافظة</option>' +
              GOVERNORATES.map(function (g) { return '<option value="' + esc(g) + '">' + esc(g) + '</option>'; }).join('') +
            '</select></div>' +
            '<div><label>المدينة</label><input id="cn-city"></div>' +
            '<div><label>الحي</label><input id="cn-dist"></div>' +
          '</div>';
          openModal('إنشاء شبكة جديدة', div, '<button class="btn btn-ghost" data-action="cancel">إلغاء</button><button class="btn btn-primary" data-action="ok">حفظ</button>')
            .then(function(res) {
              if (res === 'ok') {
                var name = document.getElementById('cn-name').value.trim();
                if (!name) { toast('الاسم التجاري مطلوب', true); return; }
                var params = {
                  p_commercial_name: name,
                  p_description: document.getElementById('cn-desc').value.trim() || null,
                  p_governorate: document.getElementById('cn-gov').value.trim() || null,
                  p_city: document.getElementById('cn-city').value.trim() || null,
                  p_district: document.getElementById('cn-dist').value.trim() || null
                };
                rpc('create_network_draft', params)
                  .then(function() { toast('تم إنشاء الشبكة بنجاح'); route(); })
                  .catch(function(e) { toast(errText(e), true); });
              }
            });
        };
      }
      
      bindActionAsync('approve', function (id) {
        return asyncConfirm('تأكيد الموافقة على الشبكة وتفعيلها؟').then(function(ok) {
          if(!ok) return false;
          return rpc('admin_approve_network', { p_network_id: id, p_resolution_note: 'موافقة من لوحة الإدارة' });
        });
      }, 'تمت الموافقة');
      bindActionAsync('suspend', function (id) {
        return asyncPrompt('الرجاء إدخال سبب الإيقاف:').then(function(reason) {
          if(!reason) return false;
          return rpc('admin_suspend_network', { p_network_id: id, p_reason: reason });
        });
      }, 'تم إيقاف الشبكة');
    });
  };

  // ---------- SSID توثيق ----------
  views.ssid = function () {
    return db.from('network_ssid_aliases').select('id, ssid_display, status, created_at, networks(commercial_name)').eq('status', 'pending_verification').order('created_at', { ascending: false }).then(function (r) {
      if (r.error) throw r.error;
      var rows = r.data.map(function (a) {
        var actions = '<button class="btn btn-sm btn-accent" data-verify-ssid="' + esc(a.id) + '">توثيق</button>' +
                      '<button class="btn btn-sm btn-danger" data-reject-ssid="' + esc(a.id) + '">رفض</button>';
        return '<tr><td dir="ltr">' + esc(a.ssid_display) + '</td><td>' + esc(a.networks && a.networks.commercial_name) + '</td><td>' + when(a.created_at) + '</td><td class="actions">' + actions + '</td></tr>';
      });
      viewEl.innerHTML = '<div class="note">قائمة المعرفات (SSID) التي أضافها ملاك الشبكات وتنتظر التوثيق لتظهر للعملاء.</div>' +
                         '<div class="card">' + table(['المعرف (SSID)', 'الشبكة', 'تاريخ الإضافة', 'إجراء'], rows) + '</div>';

      bindActionAsync('verify-ssid', function(id) {
        return asyncConfirm('هل أنت متأكد من توثيق هذا المعرف؟').then(function(ok){
          if(!ok) return false;
          return rpc('admin_verify_ssid_alias', { p_alias_id: id });
        });
      }, 'تم توثيق المعرف');
      bindActionAsync('reject-ssid', function(id) {
        return asyncPrompt('سبب الرفض:').then(function(reason) {
          if(!reason) return false;
          return rpc('admin_reject_ssid_alias', { p_alias_id: id, p_reason: reason });
        });
      }, 'تم رفض المعرف');
    });
  };

  // ---------- الباقات ----------
  // القيم المسموحة في قيد الجدول: package_type IN ('time','volume','unlimited')
  var PACKAGE_TYPES = [['time', 'زمنية'], ['volume', 'حجم بيانات'], ['unlimited', 'غير محدودة']];
  var PACKAGE_TYPE_LABELS = { time: 'زمنية', volume: 'حجم بيانات', unlimited: 'غير محدودة' };
  // duration_unit IN ('hour','day','week','month')
  var DURATION_UNIT_LABELS = { hour: 'ساعة', day: 'يوم', week: 'أسبوع', month: 'شهر' };
  views.packages = function () {
    return Promise.all([
      db.from('networks').select('id, commercial_name').order('commercial_name'),
      db.from('network_packages').select('*, networks(commercial_name)').order('created_at', { ascending: false })
    ]).then(function (res) {
      if (res[0].error) throw res[0].error;
      if (res[1].error) throw res[1].error;
      var networks = res[0].data;
      var packages = res[1].data;

      var options = networks.map(function (n) { return '<option value="' + esc(n.id) + '">' + esc(n.commercial_name) + '</option>'; }).join('');
      var rows = packages.map(function (p) {
        var actions = '';
        if (p.status === 'draft' || p.status === 'inactive') actions += '<button class="btn btn-sm btn-accent" data-publish="' + esc(p.id) + '">نشر</button>';
        if (p.status === 'active') actions += '<button class="btn btn-sm btn-ghost" data-deactivate="' + esc(p.id) + '">تعطيل</button>';
        return '<tr><td>' + esc(p.name) + '</td><td>' + esc(p.networks ? p.networks.commercial_name : '') + '</td><td>' + money(p.price) + ' ' + esc(p.currency) + '</td><td>' + esc(PACKAGE_TYPE_LABELS[p.package_type] || p.package_type) + '</td><td>' + esc(p.duration_value ? p.duration_value + ' ' + (DURATION_UNIT_LABELS[p.duration_unit] || p.duration_unit || '') : '') + '</td><td>' + statusBadge(p.status) + '</td><td>' + (p.is_public ? badge('معروضة', 'ok') : badge('مخفية', 'mute')) + '</td><td class="actions">' + actions + '</td></tr>';
      });

      var noNet = !networks.length;
      var dis = noNet ? ' disabled' : '';
      viewEl.innerHTML = (noNet ? '<div class="note">أضف شبكة أولاً — الباقة تتبع شبكة. لن تتمكن من إضافة باقة قبل إنشاء شبكة واحدة على الأقل.</div>' : '') +
        '<div class="card"><div class="card-header"><h3>إضافة باقة</h3></div>' +
          '<div class="grid grid-3 mb-4">' +
            '<div><label>الشبكة</label><select id="p-network"' + dis + '>' + options + '</select></div>' +
            '<div><label>الاسم</label><input id="p-name" placeholder="باقة شهرية"' + dis + '></div>' +
            '<div><label>السعر (ر.ي)</label><input id="p-price" type="number" min="1" dir="ltr"' + dis + '></div>' +
            '<div><label>النوع</label><select id="p-type"' + dis + '>' +
              PACKAGE_TYPES.map(function (t) { return '<option value="' + esc(t[0]) + '">' + esc(t[1]) + '</option>'; }).join('') + '</select></div>' +
            '<div><label>مدة الصلاحية</label><input id="p-dur" type="number" min="1" dir="ltr"' + dis + '></div>' +
            '<div><label>وحدة المدة</label><select id="p-unit"' + dis + '><option value="day">يوم</option><option value="hour">ساعة</option><option value="week">أسبوع</option><option value="month">شهر</option></select></div>' +
            '<div><label>السرعة (ميجابت/ث)</label><input id="p-speed" type="number" min="1" dir="ltr"' + dis + '></div>' +
          '</div>' +
          '<label>الوصف</label><textarea id="p-desc" rows="2" class="mb-4"' + dis + '></textarea>' +
          '<button class="btn btn-primary" id="p-create"' + dis + '>إنشاء</button>' +
        '</div>' +
        '<div class="card"><div class="card-header"><h3>الباقات الحالية</h3></div>' + table(['الباقة', 'الشبكة', 'السعر', 'النوع', 'المدة', 'الحالة', 'العرض', ''], rows) + '</div>';

      var btnCreate = document.getElementById('p-create');
      if (btnCreate) btnCreate.onclick = function () {
        var name = document.getElementById('p-name').value.trim();
        var price = parseInt(document.getElementById('p-price').value, 10);
        if (!name) return toast('أدخل اسم الباقة', true);
        if (!price || price < 1) return toast('أدخل سعراً صحيحاً', true);
        var dur = parseInt(document.getElementById('p-dur').value, 10);
        var speed = parseInt(document.getElementById('p-speed').value, 10);
        if (!isNaN(dur) && dur < 1) return toast('مدة الصلاحية يجب أن تكون 1 أو أكثر', true);
        if (!isNaN(speed) && speed < 0) return toast('السرعة لا يمكن أن تكون سالبة', true);
        this.disabled = true;
        rpc('create_network_package', {
          p_network_id: document.getElementById('p-network').value,
          p_name: name, p_description: document.getElementById('p-desc').value.trim() || null,
          p_price: price, p_currency: 'YER',
          p_duration_value: isNaN(dur) ? null : dur, p_duration_unit: isNaN(dur) ? null : document.getElementById('p-unit').value,
          p_speed_mbps: isNaN(speed) ? null : speed, p_package_type: document.getElementById('p-type').value
        }).then(function () { toast('تم إنشاء الباقة'); route(); }).catch(function (e) { toast(errText(e), true); }).finally(function () { if(btnCreate) btnCreate.disabled = false; });
      };

      bindActionAsync('publish', function (id) { return rpc('publish_network_package', { p_package_id: id }); }, 'تم نشر الباقة');
      bindActionAsync('deactivate', function (id) { return rpc('deactivate_network_package', { p_package_id: id }); }, 'تم تعطيل الباقة');
    });
  };

  // ---------- المستخدمون والأدوار ----------
  var ROLE_LABELS = { customer: 'عميل', network_owner: 'مالك شبكة', network_operator: 'مشغّل', platform_admin: 'مدير المنصة', finance_officer: 'موظف مالية', support_agent: 'دعم فني', system_auditor: 'مدقّق النظام' };
  // الأدوار التي تقبلها admin_set_user_platform_role (v_allowed_roles في الخادم)
  var ASSIGNABLE_PLATFORM_ROLES = ['finance_officer', 'support_agent', 'system_auditor', 'platform_admin'];
  var ADMIN_GRANT_WARNING = 'مدير المنصة يملك صلاحية كاملة: الأموال، العمولة، الأدوار وإيقاف الحسابات.';
  views.users = function () {
    return Promise.all([
      settle(query(db.from('profiles').select('*').order('created_at', { ascending: false }))),
      // قراءة فقط: أي تغيير للأدوار يمر حصراً عبر admin_set_user_platform_role
      settle(query(db.from('user_roles').select('user_id, role'))),
      settle(rpc('admin_list_access_grants')),
      settle(rpc('admin_list_pin_reset_requests'))
    ]).then(function (res) {
      var profilesRes = res[0];
      var rolesRes = res[1];
      var grantsRes = res[2];
      var pinRes = res[3];
      var profiles = profilesRes.ok ? (profilesRes.data || []) : [];
      var grants = grantsRes.ok ? (grantsRes.data || []) : [];
      var pinRequests = pinRes.ok ? (pinRes.data || []) : [];
      var rolesByUser = {};
      var nameById = {};
      if (rolesRes.ok) (rolesRes.data || []).forEach(function (r) { (rolesByUser[r.user_id] = rolesByUser[r.user_id] || []).push(r.role); });
      profiles.forEach(function (p) { nameById[p.id] = p.full_name || ''; });

      var rows = profiles.map(function (p) {
        var roles = !rolesRes.ok ? badge('تعذّر التحميل', 'err') : (rolesByUser[p.id] || []).map(function (r) { return badge(ROLE_LABELS[r] || r, r === 'platform_admin' ? 'ok' : 'mute'); }).join(' ');
        var toggle = p.account_status === 'active'
          ? '<button class="btn btn-sm btn-danger" data-suspend-user="' + esc(p.id) + '">إيقاف</button>'
          : '<button class="btn btn-sm btn-accent" data-activate-user="' + esc(p.id) + '">تفعيل</button>';
        var shortId = String(p.id || '').slice(0, 8);
        var idCell = '<span class="text-sm text-muted" dir="ltr">' + esc(shortId) + '…</span>' +
          '<button class="btn btn-icon btn-sm" data-copy-id="' + esc(p.id) + '" title="نسخ المعرّف" aria-label="نسخ المعرّف">⧉</button>';
        var searchText = [p.full_name, p.id].filter(Boolean).join(' ').toLowerCase();
        return '<tr data-search="' + esc(searchText) + '"><td>' + esc(p.full_name || '—') + '</td><td class="id-cell">' + idCell + '</td><td>' + roles + '</td><td>' + statusBadge(p.account_status) + '</td><td>' + when(p.created_at) + '</td><td class="actions">' + toggle + '<button class="btn btn-sm btn-ghost" data-role-user="' + esc(p.id) + '">الأدوار</button></td></tr>';
      });

      var GRANTABLE = [
        ['network_owner', 'مالك شبكة'], ['network_operator', 'مشغّل شبكة'],
        ['finance_officer', 'موظف مالية'], ['support_agent', 'دعم'], ['platform_admin', 'مدير منصة']
      ];
      var roleChecks = GRANTABLE.map(function (g) {
        return '<label class="chk"><input type="checkbox" class="inv-role" value="' + g[0] + '"> ' + esc(g[1]) + '</label>';
      }).join(' ');
      var grantRows = (grants || []).map(function (g) {
        var st = g.applied_at ? badge('مُفعّلة', 'ok') : badge('بانتظار الدخول', 'warn');
        var rolesTxt = (g.roles || []).map(function (r) { return ROLE_LABELS[r] || r; }).join('، ');
        var act = g.applied_at ? '' : '<button class="btn btn-sm btn-danger" data-revoke-grant="' + esc(g.id) + '">إلغاء</button>';
        return '<tr><td dir="ltr">' + esc(g.email) + '</td><td>' + esc(rolesTxt) + '</td><td>' + st + '</td><td>' + when(g.created_at) + '</td><td class="actions">' + act + '</td></tr>';
      });

      var pinReqRows = pinRequests.map(function (p) {
        var actions = '';
        if (p.status === 'pending') {
          actions = '<button class="btn btn-sm btn-accent" data-approve-pin="' + esc(p.id) + '">قبول</button>' +
                    '<button class="btn btn-sm btn-danger" data-reject-pin="' + esc(p.id) + '">رفض</button>';
        }
        return '<tr><td dir="ltr">' + esc(p.email) + '</td><td>' + esc(p.full_name || '—') + '</td><td>' + statusBadge(p.status) + '</td><td>' + when(p.requested_at) + '</td><td class="actions">' + actions + '</td></tr>';
      });

      viewEl.innerHTML =
        '<div class="card"><div class="card-header"><h3>إضافة مستخدم (دعوة بالبريد)</h3></div>' +
          '<div class="note">أدخل بريد الشخص واختر دوره. عند تسجيله الدخول عبر Google بنفس البريد يُمنح الدور تلقائياً — وإن كان مسجّلاً بالفعل يُطبّق فوراً.</div>' +
          '<div class="grid grid-2 mb-4">' +
            '<div><label>البريد الإلكتروني</label><input id="inv-email" type="email" placeholder="name@gmail.com" dir="ltr"></div>' +
            '<div><label>ملاحظة (اختياري)</label><input id="inv-note" type="text" placeholder="مثال: مالك شبكة النور"></div>' +
          '</div>' +
          '<div class="mb-4"><label>الأدوار</label><div class="flex gap-4 flex-wrap">' + roleChecks + '</div></div>' +
          '<button class="btn btn-primary" id="inv-submit">إرسال الدعوة</button>' +
          (!grantsRes.ok ? '<div class="mt-4">' + errorBox(grantsRes.error, 'تعذّر تحميل الدعوات') + '</div>' :
            (grantRows.length ? '<div class="mt-4">' + table(['البريد', 'الأدوار', 'الحالة', 'أُنشئت', 'إجراء'], grantRows) + '</div>' : '')) +
        '</div>' +
        '<div class="card"><div class="card-header"><h3>المستخدمون</h3></div>' +
          '<div class="mb-4"><input type="search" id="user-search" placeholder="ابحث بالاسم أو المعرّف…"></div>' +
          (!rolesRes.ok ? errorBox(rolesRes.error, 'تعذّر تحميل أدوار المستخدمين') : '') +
          '<div id="users-table">' + (profilesRes.ok ? table(['الاسم', 'المعرّف', 'الأدوار', 'الحالة', 'انضم', 'إجراء'], rows) : errorBox(profilesRes.error, 'تعذّر تحميل المستخدمين')) + '</div>' +
        '</div>' +
        '<div class="card"><div class="card-header"><h3>طلبات إعادة تعيين رمز الحماية</h3></div>' +
          '<div class="note">الموافقة تحذف رمز المستخدم الحالي؛ يُطلب منه إنشاء رمز جديد عند الدخول التالي.</div>' +
          (pinRes.ok ? table(['البريد', 'الاسم', 'الحالة', 'تاريخ الطلب', 'إجراء'], pinReqRows) : errorBox(pinRes.error, 'تعذّر تحميل طلبات إعادة التعيين')) +
        '</div>';

      // بحث فوري في جدول المستخدمين (اسم/هاتف/بريد)
      var searchBox = document.getElementById('user-search');
      if (searchBox) searchBox.oninput = function () {
        var q = this.value.trim().toLowerCase();
        Array.prototype.forEach.call(viewEl.querySelectorAll('#users-table tbody tr'), function (tr) {
          var hay = tr.getAttribute('data-search') || '';
          tr.style.display = (!q || hay.indexOf(q) !== -1) ? '' : 'none';
        });
      };

      // نسخ المعرّف الكامل إلى الحافظة
      Array.prototype.forEach.call(viewEl.querySelectorAll('[data-copy-id]'), function (btn) {
        btn.onclick = function () {
          var id = btn.dataset.copyId;
          var done = function () { toast('تم نسخ المعرّف'); };
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(id).then(done).catch(function (e) { console.error('clipboard failed', e); toast('تعذّر النسخ', true); });
          } else {
            try {
              var ta = document.createElement('textarea');
              ta.value = id; document.body.appendChild(ta); ta.select();
              document.execCommand('copy'); document.body.removeChild(ta); done();
            } catch (e) { console.error('clipboard fallback failed', e); toast('تعذّر النسخ', true); }
          }
        };
      });

      document.getElementById('inv-submit').onclick = function () {
        var email = document.getElementById('inv-email').value.trim();
        var note = document.getElementById('inv-note').value.trim();
        var roles = Array.prototype.map.call(document.querySelectorAll('.inv-role:checked'), function (c) { return c.value; });
        if (!email) return toast('أدخل البريد الإلكتروني', true);
        if (!roles.length) return toast('اختر دوراً واحداً على الأقل', true);
        var btn = this; btn.disabled = true;
        var confirmed = roles.indexOf('platform_admin') === -1
          ? Promise.resolve(true)
          : asyncConfirm('ستُمنح صلاحية «مدير المنصة» للبريد ' + email + ' عند أول دخول. ' + ADMIN_GRANT_WARNING + ' هل تريد المتابعة؟');
        confirmed.then(function (ok) {
          if (!ok) { btn.disabled = false; return; }
          return rpc('admin_create_access_grant', { p_email: email, p_roles: roles, p_note: note || null })
            .then(function () { toast('تمت إضافة الدعوة'); route(); });
        }).catch(function (e) { toast(errText(e), true); btn.disabled = false; });
      };
      bindActionAsync('revoke-grant', function (id) {
        return rpc('admin_revoke_access_grant', { p_id: id });
      }, 'أُلغيت الدعوة');

      bindActionAsync('suspend-user', function (id) {
        var div = document.createElement('div');
        div.innerHTML = '<p class="text-error" style="font-weight:600">إجراء حسّاس: سيتم إيقاف حساب هذا المستخدم ومنعه من الدخول.</p>' +
          '<label for="suspend-reason">سبب الإيقاف <span class="text-error">*</span></label>' +
          '<textarea id="suspend-reason" rows="3" placeholder="اذكر سبب الإيقاف"></textarea>';
        return openModal('تأكيد إيقاف الحساب', div,
          '<button class="btn btn-ghost" data-action="cancel">إلغاء</button>' +
          '<button class="btn btn-danger" data-action="ok">إيقاف الحساب</button>'
        ).then(function (res) {
          if (res !== 'ok') return false;
          var reason = document.getElementById('suspend-reason').value.trim();
          if (!reason) { toast('سبب الإيقاف مطلوب', true); return false; }
          return rpc('admin_set_user_account_status', { p_user_id: id, p_status: 'suspended', p_reason: reason });
        });
      }, 'تم إيقاف الحساب');
      bindActionAsync('activate-user', function (id) {
        return rpc('admin_set_user_account_status', { p_user_id: id, p_status: 'active', p_reason: 'إعادة تفعيل' });
      }, 'تم تفعيل الحساب');
      bindActionAsync('role-user', function (id) {
        var div = document.createElement('div');
        var who = nameById[id] || String(id).slice(0, 8);
        div.innerHTML = '<p>اختر الدور الذي ترغب في إدارته للمستخدم «' + esc(who) + '»:</p>' +
          '<select id="role-select" class="mb-4">' +
            ASSIGNABLE_PLATFORM_ROLES.map(function (r) { return '<option value="' + esc(r) + '">' + esc(ROLE_LABELS[r] || r) + '</option>'; }).join('') +
          '</select>' +
          '<div class="flex gap-4"><label><input type="radio" name="role-act" value="grant" checked> منح الدور</label><label><input type="radio" name="role-act" value="revoke"> سحب الدور</label></div>';
        return openModal('إدارة الأدوار', div, '<button class="btn btn-ghost" data-action="cancel">إلغاء</button><button class="btn btn-primary" data-action="ok">حفظ</button>').then(function(res) {
          if(res === 'ok') {
            var role = document.getElementById('role-select').value;
            var enable = document.querySelector('input[name="role-act"]:checked').value === 'grant';
            if (ASSIGNABLE_PLATFORM_ROLES.indexOf(role) === -1) { toast(errText(new Error('INVALID_ROLE')), true); return false; }
            // تأكيد إضافي صريح قبل منح مدير المنصة
            var confirmed = (role === 'platform_admin' && enable)
              ? asyncConfirm('سيُمنح المستخدم «' + who + '» صلاحية «مدير المنصة». ' + ADMIN_GRANT_WARNING + ' هل تريد المتابعة؟')
              : Promise.resolve(true);
            return confirmed.then(function (ok) {
              if (!ok) return false;
              return rpc('admin_set_user_platform_role', { p_user_id: id, p_role: role, p_enabled: enable });
            });
          }
          return false;
        });
      }, function (res) {
        return res && res.changed === false ? 'لا تغيير — الدور على حاله مسبقاً' : 'تم تحديث الأدوار';
      });

      bindActionAsync('approve-pin', function (id) {
        return asyncConfirm('تأكيد قبول الطلب؟ سيُطلب من المستخدم إنشاء رمز جديد عند الدخول التالي.').then(function (ok) {
          if (!ok) return false;
          return rpc('admin_resolve_pin_reset', { p_request_id: id, p_approve: true });
        });
      }, 'تم قبول الطلب');
      bindActionAsync('reject-pin', function (id) {
        return asyncConfirm('تأكيد رفض الطلب؟').then(function (ok) {
          if (!ok) return false;
          return rpc('admin_resolve_pin_reset', { p_request_id: id, p_approve: false });
        });
      }, 'تم رفض الطلب');
    });
  };

  // ---------- وجهات الدفع ----------
  views.destinations = function () {
    return rpc('admin_get_payment_destinations').then(function (list) {
      var rows = (list || []).map(function (d) {
        var toggle = d.is_active
          ? '<button class="btn btn-sm btn-ghost" data-deact="' + esc(d.id) + '">تعطيل</button>'
          : '<button class="btn btn-sm btn-accent" data-act="' + esc(d.id) + '">تفعيل</button>';
        return '<tr><td>' + esc(d.display_name) + '</td><td>' + esc(providerLabel(d.provider_type)) + '</td><td>' + esc(d.account_holder_name) + '</td><td dir="ltr" class="text-center">' + esc(d.account_identifier) + '</td><td>' + (d.is_active ? badge('مُفعّلة', 'ok') : badge('معطّلة', 'mute')) + '</td><td class="actions">' + toggle + '</td></tr>';
      });

      viewEl.innerHTML = '<div class="note">هذه الوجهات تظهر للعميل في شاشة شحن المحفظة.</div>' +
        '<div class="card"><div class="card-header"><h3>إضافة وجهة دفع جديدة</h3></div>' +
          '<div class="grid grid-2 mb-4">' +
            '<div><label>النوع</label><select id="d-type"><option value="bank_account">حساب بنكي</option><option value="mobile_wallet">محفظة إلكترونية</option><option value="manual_transfer">حوالة / صرافة</option><option value="other">أخرى</option></select></div>' +
            '<div><label>الاسم المعروض</label><input id="d-name" placeholder="بنك الكريمي"></div>' +
            '<div><label>اسم صاحب الحساب</label><input id="d-holder"></div>' +
            '<div><label>رقم الحساب</label><input id="d-acct" dir="ltr"></div>' +
          '</div>' +
          '<label>تعليمات إضافية للعميل</label><textarea id="d-inst" rows="2" class="mb-4"></textarea>' +
          '<button class="btn btn-primary" id="d-create">إضافة الوجهة</button>' +
        '</div>' +
        '<div class="card"><div class="card-header"><h3>وجهات الدفع الحالية</h3></div>' + table(['الاسم', 'النوع', 'صاحب الحساب', 'رقم الحساب', 'الحالة', 'إجراء'], rows) + '</div>';

      var btnCreate = document.getElementById('d-create');
      if (btnCreate) btnCreate.onclick = function () {
        var name = document.getElementById('d-name').value.trim();
        if (!name) return toast('أدخل الاسم المعروض', true);
        this.disabled = true;
        rpc('admin_create_payment_destination', {
          p_provider_type: document.getElementById('d-type').value,
          p_display_name: name,
          p_account_holder_name: document.getElementById('d-holder').value.trim() || null,
          p_account_identifier: document.getElementById('d-acct').value.trim() || null,
          p_instructions: document.getElementById('d-inst').value.trim() || null,
          p_currency: 'YER', p_sort_order: 0
        }).then(function () { toast('تمت الإضافة'); route(); }).catch(function (e) { toast(errText(e), true); }).finally(function () { if(btnCreate) btnCreate.disabled = false; });
      };

      bindActionAsync('act', function (id) { return rpc('admin_set_payment_destination_active', { p_id: id, p_active: true }); }, 'تم التفعيل');
      bindActionAsync('deact', function (id) { return rpc('admin_set_payment_destination_active', { p_id: id, p_active: false }); }, 'تم التعطيل');
    });
  };

  // ---------- طلبات الشحن ----------
  var DEPOSIT_STATUSES = ['pending', 'under_review', 'approved', 'rejected', 'cancelled'];
  var DEPOSIT_DUAL_APPROVAL_FALLBACK = 50000; // deposit_dual_approval_threshold() في الخادم
  views.deposits = function () {
    var status = sessionStorage.getItem('depositFilter');
    if (DEPOSIT_STATUSES.indexOf(status) === -1) status = 'pending';

    return Promise.all([
      settle(rpc('get_finance_deposit_queue', { p_status: status })),
      settle(rpc('deposit_dual_approval_threshold'))
    ]).then(function (first) {
      var queueRes = first[0];
      var list = queueRes.ok ? (queueRes.data || []) : [];
      var threshold = first[1].ok ? Number(first[1].data) : NaN;
      if (!(threshold > 0)) threshold = DEPOSIT_DUAL_APPROVAL_FALLBACK;

      // قائمة المراجعة لا تُرجع لقطة وجهة الدفع ولا الموافق الأول، فنقرؤها من الجدول
      // مباشرةً (سياسة SELECT تسمح لموظف المالية ومدير المنصة). قراءة فقط.
      var ids = list.map(function (d) { return d.id; });
      var detailsPromise = ids.length
        ? settle(query(db.from('wallet_deposit_requests')
            .select('id, destination_snapshot, first_approved_by, first_approved_at, reviewed_at, rejection_reason')
            .in('id', ids)))
        : Promise.resolve({ ok: true, data: [] });

      return detailsPromise.then(function (detailsRes) {
        var detailById = {};
        (detailsRes.ok ? detailsRes.data : []).forEach(function (r) { detailById[r.id] = r; });

        var approverIds = [];
        Object.keys(detailById).forEach(function (k) {
          var a = detailById[k].first_approved_by;
          if (a && a !== currentUserId && approverIds.indexOf(a) === -1) approverIds.push(a);
        });
        // أسماء الموافقين الأوائل: الملفات الشخصية مقروءة لمدير المنصة فقط؛ عند التعذّر نعرض المعرّف المختصر
        var namesPromise = approverIds.length
          ? settle(query(db.from('profiles').select('id, full_name').in('id', approverIds)))
          : Promise.resolve({ ok: true, data: [] });

        return namesPromise.then(function (namesRes) {
          var approverName = {};
          (namesRes.ok ? namesRes.data : []).forEach(function (p) { approverName[p.id] = p.full_name; });
          renderDeposits(status, queueRes, list, threshold, detailsRes, detailById, approverName);
        });
      });
    });
  };

  function renderDeposits(status, queueRes, list, threshold, detailsRes, detailById, approverName) {
    var byId = {};
    function line(label, value, ltr) {
      if (value === null || value === undefined || value === '') return '';
      return '<div class="kv"><span class="k">' + esc(label) + '</span> <span' + (ltr ? ' dir="ltr"' : '') + '>' + esc(value) + '</span></div>';
    }
    function approverLabel(uid) {
      if (!uid) return '';
      if (uid === currentUserId) return 'أنت';
      return approverName[uid] || ('موظف ' + String(uid).slice(0, 8) + '…');
    }

    var rows = list.map(function (d) {
      var det = detailById[d.id] || null;
      var snap = (det && det.destination_snapshot && typeof det.destination_snapshot === 'object') ? det.destination_snapshot : {};
      var reviewable = d.status === 'pending' || d.status === 'under_review';
      var needsDual = Number(d.amount) >= threshold;
      var firstBy = det ? det.first_approved_by : null;
      var firstIsMe = !!firstBy && firstBy === currentUserId;
      byId[d.id] = { d: d, snap: snap, needsDual: needsDual, firstBy: firstBy };

      var customer = '<div>' + esc(d.customer_name || '—') + '</div>' +
        '<div class="text-sm text-muted" dir="ltr">' + esc(String(d.user_id || '').slice(0, 8)) + '…</div>';

      var destination;
      if (!detailsRes.ok) {
        destination = '<span class="text-error">تعذّر التحميل</span>';
      } else if (!snap.display_name && !snap.account_identifier) {
        destination = '<span class="text-error">لا توجد لقطة وجهة محفوظة لهذا الطلب</span>';
      } else {
        destination = line('الوجهة:', snap.display_name) +
          line('النوع:', snap.provider_type ? providerLabel(snap.provider_type) : '') +
          line('صاحب الحساب:', snap.account_holder_name) +
          line('رقم الحساب:', snap.account_identifier, true);
      }

      var state = statusBadge(d.status);
      if (reviewable && needsDual) {
        if (firstBy) {
          state += '<div class="dual-note">تمت الموافقة الأولى بواسطة ' + esc(approverLabel(firstBy)) +
            (det.first_approved_at ? ' (' + esc(whenFull(det.first_approved_at)) + ')' : '') +
            ' — يحتاج موافقة مراجع ثانٍ مختلف قبل إضافة الرصيد.</div>';
        } else {
          state += '<div class="dual-note">مبلغ ' + esc(money(threshold)) + ' ر.ي فأكثر: يحتاج موافقتين من مراجعَين مختلفَين.</div>';
        }
      }
      if (det && d.status === 'rejected' && det.rejection_reason) state += line('سبب الرفض:', det.rejection_reason);
      if (det && det.reviewed_at) state += line('روجع في:', whenFull(det.reviewed_at), true);

      var actions = '';
      if (reviewable) {
        if (!detailsRes.ok) {
          actions += '<span class="text-sm text-error">القبول معطّل حتى تُحمّل التفاصيل</span>';
        } else if (firstIsMe) {
          actions += '<span class="text-sm text-muted">سجّلت موافقتك — بانتظار مراجع آخر</span>';
        } else {
          actions += '<button class="btn btn-sm btn-accent" data-approve-dep="' + esc(d.id) + '">' +
            (needsDual ? (firstBy ? 'موافقة ثانية وإضافة الرصيد' : 'موافقة أولى') : 'قبول') + '</button>';
        }
        actions += '<button class="btn btn-sm btn-danger" data-reject-dep="' + esc(d.id) + '">رفض</button>';
      }

      return '<tr><td>' + customer + '</td>' +
        '<td><strong>' + esc(money(d.amount)) + '</strong> ' + esc(d.currency || 'YER') + '</td>' +
        '<td>' + destination + '</td>' +
        '<td dir="ltr" class="text-center">' + esc(d.reference_number) + (d.proof_storage_path ? '<div class="text-sm text-muted" dir="rtl">مرفق إثبات</div>' : '') + '</td>' +
        '<td dir="ltr">' + esc(whenFull(d.created_at)) + '</td>' +
        '<td>' + state + '</td>' +
        '<td class="actions">' + actions + '</td></tr>';
    });

    var filters = DEPOSIT_STATUSES.map(function (s) {
      var label = (STATUS_STYLE[s] || [s])[0];
      return '<button class="btn btn-sm ' + (s === status ? 'btn-primary' : 'btn-ghost') + '" data-filter="' + esc(s) + '">' + esc(label) + '</button>';
    }).join('');

    viewEl.innerHTML = '<div class="note">الطلبات بمبلغ ' + esc(money(threshold)) + ' ر.ي فأكثر تحتاج موافقتين من مراجعَين مختلفَين: الموافقة الأولى تنقل الطلب إلى «قيد المراجعة» دون إضافة رصيد، والثانية (من موظف آخر) تضيف الرصيد.</div>' +
      '<div class="card"><div class="flex gap-2 flex-wrap">' + filters + '</div></div>' +
      '<div class="card">' +
        (queueRes.ok && !detailsRes.ok ? errorBox(detailsRes.error, 'تعذّر تحميل تفاصيل وجهة الدفع والموافقة الأولى — القبول معطّل، أعد تحميل الصفحة') : '') +
        (queueRes.ok
          ? table(['العميل', 'المبلغ', 'وجهة الدفع', 'رقم الحوالة/المرجع', 'وقت الطلب', 'الحالة', 'إجراء'], rows)
          : errorBox(queueRes.error, 'تعذّر تحميل طلبات الشحن')) +
      '</div>';

    Array.prototype.forEach.call(viewEl.querySelectorAll('[data-filter]'), function (btn) {
      btn.onclick = function () { sessionStorage.setItem('depositFilter', btn.dataset.filter); route(); };
    });

    bindActionAsync('approve-dep', function (id) {
      var item = byId[id];
      if (!item) return Promise.resolve(false);
      var d = item.d;
      var summary = 'المبلغ: ' + money(d.amount) + ' ر.ي — العميل: ' + (d.customer_name || '—') +
        ' — المرجع: ' + d.reference_number +
        ' — الوجهة: ' + (item.snap.display_name || '—') + (item.snap.account_identifier ? ' (' + item.snap.account_identifier + ')' : '') + '. ';
      var consequence = !item.needsDual
        ? 'سيُضاف المبلغ إلى محفظة العميل فوراً. تأكيد القبول؟'
        : (item.firstBy
          ? 'هذه الموافقة الثانية: سيُضاف المبلغ إلى محفظة العميل فوراً. تأكيد؟'
          : 'هذه الموافقة الأولى: لن يُضاف الرصيد الآن، وسينتقل الطلب إلى «قيد المراجعة» بانتظار مراجع ثانٍ مختلف. تأكيد؟');
      return asyncConfirm(summary + consequence).then(function (ok) {
        if (!ok) return false;
        return rpc('review_wallet_deposit_request', { p_deposit_id: id, p_action: 'approve', p_rejection_reason: null });
      });
    }, function (res) {
      // المبالغ الكبيرة: الموافقة الأولى تُرجع status = under_review و requires_second_approval = true دون إضافة رصيد
      if (res && (res.requires_second_approval || res.status === 'under_review')) {
        return res.replayed
          ? 'موافقتك مسجّلة مسبقاً — الطلب ما زال يحتاج مراجعاً ثانياً مختلفاً، ولم يُضف أي رصيد'
          : 'سُجّلت موافقتك الأولى ونُقل الطلب إلى «قيد المراجعة» — يحتاج مراجعاً ثانياً مختلفاً قبل إضافة الرصيد';
      }
      if (res && res.status === 'rejected') return 'الطلب مرفوض مسبقاً — لم يُضف أي رصيد';
      if (res && res.replayed) return 'الطلب معتمد مسبقاً — لم يُضف الرصيد مرة ثانية';
      return 'تم قبول الطلب وإضافة الرصيد';
    });

    bindActionAsync('reject-dep', function (id) {
      return asyncPrompt('سبب الرفض (مطلوب، 500 حرف كحد أقصى):').then(function (reason) {
        if (reason === null) return false;
        if (!reason) { toast('سبب الرفض مطلوب', true); return false; }
        if (reason.length > 500) { toast('سبب الرفض أطول من 500 حرف', true); return false; }
        return rpc('review_wallet_deposit_request', { p_deposit_id: id, p_action: 'reject', p_rejection_reason: reason });
      });
    }, function (res) {
      return res && res.status === 'approved' ? 'الطلب معتمد مسبقاً ولا يمكن رفضه' : 'تم رفض الطلب';
    });
  }

  // ---------- تصفية المستحقات ----------
  // الحالات كما يقبلها get_finance_settlement_batches (أي قيمة أخرى ترفع INVALID_STATUS_FILTER)
  var SETTLEMENT_STATUSES = ['draft', 'ready_for_review', 'approved', 'paid', 'cancelled', 'corrected'];
  views.settlements = function () {
    var status = sessionStorage.getItem('settlementFilter');
    // 'all' => p_status = null (كل الحالات)
    if (status !== 'all' && SETTLEMENT_STATUSES.indexOf(status) === -1) status = 'draft';

    return Promise.all([
      settle(query(db.from('networks').select('id, commercial_name').order('commercial_name'))),
      settle(rpc('get_finance_settlement_batches', { p_status: status === 'all' ? null : status }))
    ]).then(function (res) {
      var networksRes = res[0];
      var batchesRes = res[1];
      var networks = networksRes.ok ? networksRes.data : [];
      var list = batchesRes.ok ? (batchesRes.data || []) : [];
      var byId = {};

      var rows = list.map(function (b) {
        byId[b.id] = b;
        var actions = '';
        // الخادم يوافق من draft أو ready_for_review فقط، ويرفض موافقة منشئ الدفعة نفسه
        if (b.status === 'draft' || b.status === 'ready_for_review') {
          if (b.created_by && b.created_by === currentUserId) {
            actions += '<span class="text-sm text-muted">أنشأتها أنت — تحتاج موافقة موظف آخر</span>';
          } else {
            actions += '<button class="btn btn-sm btn-accent" data-approve-set="' + esc(b.id) + '">موافقة</button>';
          }
        }
        if (b.status === 'approved') actions += '<button class="btn btn-sm btn-primary" data-pay-set="' + esc(b.id) + '">تسجيل السداد</button>';

        return '<tr><td><div>' + esc(b.network_name || '—') + '</div><div class="text-sm text-muted">' + esc(b.owner_name || '') + '</div></td>' +
          '<td dir="ltr">' + esc(when(b.period_start)) + ' - ' + esc(when(b.period_end)) + '</td>' +
          '<td>' + esc(money(b.gross_sales)) + '</td>' +
          '<td>' + esc(money(b.total_commission)) + '</td>' +
          '<td>' + esc(money(b.total_refunds)) + '</td>' +
          '<td>' + esc(money(b.total_adjustments)) + '</td>' +
          '<td><strong>' + esc(money(b.net_settlement)) + '</strong></td>' +
          '<td>' + statusBadge(b.status) + (b.notes ? '<div class="text-sm text-muted">' + esc(b.notes) + '</div>' : '') + '</td>' +
          '<td class="actions">' + actions + '</td></tr>';
      });

      var filters = ['all'].concat(SETTLEMENT_STATUSES).map(function (s) {
        var label = s === 'all' ? 'الكل' : (STATUS_STYLE[s] || [s])[0];
        return '<button class="btn btn-sm ' + (s === status ? 'btn-primary' : 'btn-ghost') + '" data-filter="' + esc(s) + '">' + esc(label) + '</button>';
      }).join('');

      var options = '<option value="">كل الشبكات</option>' + networks.map(function (n) { return '<option value="' + esc(n.id) + '">' + esc(n.commercial_name) + '</option>'; }).join('');

      viewEl.innerHTML = '<div class="card"><div class="card-header"><h3>إنشاء دفعة تصفية</h3></div>' +
        '<p class="mb-4 text-muted">تُنشأ دفعة «مسودة» لكل شبكة/مالك لديه مبيعات مكتملة غير مسوّاة في الفترة. من أنشأ الدفعة لا يستطيع الموافقة عليها.</p>' +
        (networksRes.ok ? '' : errorBox(networksRes.error, 'تعذّر تحميل قائمة الشبكات — يمكن الإنشاء لكل الشبكات فقط')) +
        '<div class="grid grid-3 mb-4">' +
          '<div><label>من تاريخ</label><input type="date" id="s-start" dir="ltr"></div>' +
          '<div><label>إلى تاريخ</label><input type="date" id="s-end" dir="ltr"></div>' +
          '<div><label>الشبكة (اختياري)</label><select id="s-network">' + options + '</select></div>' +
        '</div>' +
        '<button class="btn btn-primary" id="s-create">إنشاء الدفعة</button></div>' +
        '<div class="card"><div class="flex gap-2 flex-wrap">' + filters + '</div></div>' +
        '<div class="card"><div class="card-header"><h3>دفعات التصفية</h3></div>' +
          (batchesRes.ok
            ? table(['الشبكة / المالك', 'الفترة', 'إجمالي المبيعات', 'العمولة', 'المستردات', 'التسويات', 'الصافي المستحق', 'الحالة', 'إجراء'], rows)
            : errorBox(batchesRes.error, 'تعذّر تحميل دفعات التصفية')) +
        '</div>';

      Array.prototype.forEach.call(viewEl.querySelectorAll('[data-filter]'), function (btn) {
        btn.onclick = function () { sessionStorage.setItem('settlementFilter', btn.dataset.filter); route(); };
      });

      var btnCreate = document.getElementById('s-create');
      if (btnCreate) btnCreate.onclick = function () {
        var start = document.getElementById('s-start').value;
        var end = document.getElementById('s-end').value;
        var nid = document.getElementById('s-network').value || null;
        if (!start || !end) return toast('حدد تاريخ البداية والنهاية', true);
        if (start > end) return toast(errText(new Error('INVALID_PERIOD')), true);
        this.disabled = true;
        rpc('finance_create_settlement_batch', { p_period_start: start, p_period_end: end, p_network_id: nid })
          .then(function (r) {
            var n = (r && Number(r.batches_created)) || 0;
            if (!n) { toast('لم تُنشأ أي دفعة: لا توجد مبيعات مؤهلة للتسوية في هذه الفترة', true); return; }
            toast('تم إنشاء ' + n + ' دفعة — إجمالي المبيعات ' + money(r.total_gross_sales) + ' ر.ي، المستردات ' + money(r.total_refunds) + ' ر.ي');
            sessionStorage.setItem('settlementFilter', 'draft');
            route();
          }).catch(function (e) { console.error('NetYemen admin action failed:', e); toast(errText(e), true); }).finally(function () { if(btnCreate) btnCreate.disabled = false; });
      };

      function batchSummary(b) {
        return 'الشبكة: ' + (b.network_name || '—') + ' — الفترة: ' + when(b.period_start) + ' - ' + when(b.period_end) +
          ' — الصافي المستحق: ' + money(b.net_settlement) + ' ر.ي. ';
      }

      bindActionAsync('approve-set', function (id) {
        var b = byId[id];
        if (!b) return Promise.resolve(false);
        return asyncConfirm(batchSummary(b) + 'تأكيد الموافقة على الدفعة؟').then(function(ok) {
          if(!ok) return false;
          return rpc('finance_approve_settlement_batch', { p_batch_id: id });
        });
      }, 'تمت الموافقة');

      bindActionAsync('pay-set', function (id) {
        var b = byId[id];
        if (!b) return Promise.resolve(false);
        var div = document.createElement('div');
        div.innerHTML = '<p>' + esc(batchSummary(b)) + '</p>' +
          '<p class="text-error" style="font-weight:600">تسجيل السداد نهائي: تأكد أن التحويل للمالك تم فعلاً.</p>' +
          '<label for="pay-notes">مرجع/ملاحظات السداد <span class="text-error">*</span></label>' +
          '<textarea id="pay-notes" rows="3" placeholder="مثال: رقم الحوالة، الجهة، التاريخ"></textarea>';
        return openModal('تسجيل سداد الدفعة', div,
          '<button class="btn btn-ghost" data-action="cancel">إلغاء</button>' +
          '<button class="btn btn-primary" data-action="ok">تأكيد السداد</button>'
        ).then(function (res) {
          if (res !== 'ok') return false;
          // المعامل الثاني للدالة هو p_notes (نص) — نشترطه غير فارغ ليبقى أثر للسداد
          var notes = document.getElementById('pay-notes').value.trim();
          if (!notes) { toast('مرجع/ملاحظات السداد مطلوبة', true); return false; }
          return rpc('finance_mark_settlement_paid', { p_batch_id: id, p_notes: notes });
        });
      }, 'تم تسجيل السداد');
    });
  };

  // ---------- الإشعارات ----------
  views.notifications = function () {
    // get_notification_transport_status تُرجع كائناً واحداً:
    // { provider_key, binding_status, adapter_interface, notes, od_notif_01, external_push_dispatch_enabled }
    return settle(rpc('get_notification_transport_status')).then(function (statusRes) {
      var transportHtml;
      var st = statusRes.ok ? statusRes.data : null;
      if (!statusRes.ok) {
        transportHtml = errorBox(statusRes.error, 'تعذّر تحميل حالة ناقل الإشعارات');
      } else if (!st || typeof st !== 'object' || Array.isArray(st)) {
        transportHtml = errorBox(new Error('unexpected shape'), 'أرجع الخادم حالة ناقل بصيغة غير متوقعة');
      } else {
        var enabled = st.external_push_dispatch_enabled === true;
        transportHtml = table(['المزوّد', 'حالة الربط', 'الإرسال الخارجي (Push)', 'الواجهة', 'ملاحظات'], [
          '<tr><td dir="ltr">' + esc(st.provider_key || '—') + '</td>' +
          '<td dir="ltr">' + esc(st.binding_status || '—') + '</td>' +
          '<td>' + (enabled ? badge('مفعّل', 'ok') : badge('غير مفعّل', 'err')) + '</td>' +
          '<td dir="ltr">' + esc(st.adapter_interface || '—') + '</td>' +
          '<td>' + esc(st.notes || '') + '</td></tr>'
        ]) + (enabled ? '' : '<p class="text-sm text-muted mt-2">الإرسال الخارجي للأجهزة (Push) غير مربوط حالياً.</p>');
      }

      viewEl.innerHTML = '<div class="card"><div class="card-header"><h3>إرسال إشعار جديد</h3></div>' +
        '<div class="grid grid-2 mb-4">' +
          '<div><label>العنوان</label><input id="n-title" placeholder="عرض جديد!"></div>' +
          '<div><label>نوع الجمهور</label><select id="n-audience"><option value="all_active_customers">كل العملاء</option><option value="network_owner_operator">ملاك ومشغّلو الشبكات</option><option value="governorate">حسب المحافظة</option></select></div>' +
          '<div><label>نوع الإعلان</label><select id="n-channel"><option value="announcement">إعلان</option><option value="platform_update">تحديث المنصة</option><option value="offer">عرض</option></select></div>' +
          '<div id="n-gov-wrap" style="display:none"><label>المحافظة</label><select id="n-gov">' + GOVERNORATES.map(function (g) { return '<option value="' + esc(g) + '">' + esc(g) + '</option>'; }).join('') + '</select></div>' +
          '<div><label>رابط عميق (Deep Link)</label><input id="n-link" placeholder="notifications"></div>' +
        '</div>' +
        '<label>النص</label><textarea id="n-body" rows="3" class="mb-4"></textarea>' +
        '<div class="flex items-center gap-2 mb-4"><input type="checkbox" id="n-imm" checked> <label style="margin:0">إرسال فوراً</label></div>' +
        '<button class="btn btn-primary" id="n-send">إرسال الإشعار</button></div>' +
        '<div class="card"><div class="card-header"><h3>حالة ناقل الإشعارات</h3></div>' + transportHtml + '</div>';

      var audSel = document.getElementById('n-audience');
      var govWrap = document.getElementById('n-gov-wrap');
      if (audSel && govWrap) {
        audSel.onchange = function () { govWrap.style.display = this.value === 'governorate' ? '' : 'none'; };
      }

      var btnSend = document.getElementById('n-send');
      if (btnSend) btnSend.onclick = function() {
        var title = document.getElementById('n-title').value.trim();
        var body = document.getElementById('n-body').value.trim();
        if(!title || !body) return toast('أدخل العنوان والنص', true);
        var audience = document.getElementById('n-audience').value;
        var payload = audience === 'governorate'
          ? { governorate: document.getElementById('n-gov').value }
          : {};
        this.disabled = true;
        rpc('admin_compose_notification', {
          p_title_ar: title, p_body_ar: body,
          p_audience_type: audience,
          p_audience_payload: payload,
          p_channel_class: document.getElementById('n-channel').value,
          p_deep_link: document.getElementById('n-link').value.trim() || null,
          p_scheduled_for: null, p_idempotency_key: null,
          p_process_immediately: document.getElementById('n-imm').checked
        }).then(function() { toast('تمت جدولة الإشعار'); route(); }).catch(function(e) { toast(errText(e), true); }).finally(function() { if(btnSend) btnSend.disabled = false; });
      };
    });
  };

  // ---------- إعدادات العمولة ----------
  // COMMISSION CONTRACT: الواجهة تعرض وتستقبل نسبة مئوية (0–100)، والخادم يخزّن ويستقبل
  // كسراً بين 0 و 1 (0.03 = 3%). التحويل يتم في هاتين الدالتين فقط.
  // تُرجع الكسر (0..1) أو null إن كان الإدخال غير صالح. لا تُرجع أبداً قيمة أكبر من 1.
  function commissionPercentToFraction(percentText) {
    var text = String(percentText === null || percentText === undefined ? '' : percentText).trim();
    // أرقام عشرية بسيطة فقط، بخانة عشرية واحدة كحد أقصى (step = 0.1)
    if (!/^[0-9]{1,3}(\.[0-9])?$/.test(text)) return null;
    var percent = Number(text);
    if (!isFinite(percent) || percent < 0 || percent > 100) return null;
    var fraction = Number((percent / 100).toFixed(4));
    if (!(fraction >= 0 && fraction <= 1)) return null;
    return fraction;
  }
  function commissionFractionToPercentText(fraction) {
    return String(Number((Number(fraction) * 100).toFixed(4)));
  }

  views.commission = function () {
    var canEdit = isPlatformAdmin(); // admin_update_default_commission_rate: platform_admin فقط
    return settle(rpc('get_platform_commission_config')).then(function (cfgRes) {
      var conf = cfgRes.ok ? cfgRes.data : null;
      var currentFraction = conf ? Number(conf.default_rate) : NaN;
      var loaded = cfgRes.ok && !!conf && conf.default_rate !== null && conf.default_rate !== undefined &&
        isFinite(currentFraction) && currentFraction >= 0 && currentFraction <= 1;
      var currentText = loaded ? commissionFractionToPercentText(currentFraction) : '';
      // بدون القيمة الحالية لا نسمح بالحفظ: لا يمكن تأكيد «من X% إلى Y%» على عمى
      var dis = (loaded && canEdit) ? '' : ' disabled';

      var currentHtml;
      if (!cfgRes.ok) {
        currentHtml = errorBox(cfgRes.error, 'تعذّر تحميل العمولة الحالية — الحفظ معطّل');
      } else if (!loaded) {
        currentHtml = errorBox(new Error('unexpected shape'), 'أرجع الخادم قيمة عمولة غير متوقعة — الحفظ معطّل');
      } else {
        currentHtml = '<div class="kpis mb-4"><div class="kpi"><div class="n" dir="ltr">' + esc(currentText) + '%</div><div class="l">العمولة الافتراضية الحالية</div></div></div>' +
          '<p class="text-sm text-muted mb-4">سارية منذ: <span dir="ltr">' + esc(whenFull(conf.effective_from) || '—') + '</span> — آخر تحديث: <span dir="ltr">' + esc(whenFull(conf.updated_at) || '—') + '</span></p>';
      }

      viewEl.innerHTML = '<div class="card"><div class="card-header"><h3>العمولة الافتراضية</h3></div>' +
        '<p class="mb-4 text-muted">تُخصم هذه العمولة من مبيعات الشبكات تلقائياً (كنسبة مئوية).</p>' +
        currentHtml +
        (canEdit
          ? '<div style="max-width:300px"><label for="c-rate">النسبة الجديدة (%) — من 0 إلى 100</label>' +
            '<input type="number" id="c-rate" step="0.1" min="0" max="100" inputmode="decimal" class="mb-4" dir="ltr" value="' + esc(currentText) + '"' + dis + '></div>' +
            '<button class="btn btn-primary" id="c-save"' + dis + '>تحديث العمولة</button>'
          : '<div class="note">تعديل العمولة متاح لمدير المنصة فقط.</div>') +
        '</div>';

      var btnSave = document.getElementById('c-save');
      if (btnSave && loaded && canEdit) btnSave.onclick = function () {
        var fraction = commissionPercentToFraction(document.getElementById('c-rate').value);
        if (fraction === null) return toast('أدخل نسبة مئوية بين 0 و 100 بخانة عشرية واحدة كحد أقصى (مثال: 3.5)', true);
        var nextText = commissionFractionToPercentText(fraction);
        if (fraction === currentFraction) return toast('النسبة المدخلة تساوي العمولة الحالية — لا تغيير', true);
        btnSave.disabled = true;
        asyncConfirm('سيتم تغيير العمولة من ' + currentText + '% إلى ' + nextText + '%. هل تريد المتابعة؟').then(function (ok) {
          if (!ok) return;
          return rpc('admin_update_default_commission_rate', { p_rate: fraction }).then(function () {
            toast('تم تحديث العمولة إلى ' + nextText + '%');
            route(); // يعيد تحميل القيمة المعروضة من الخادم
          });
        }).catch(function (e) {
          console.error('NetYemen admin action failed:', e);
          toast(errText(e), true);
        }).finally(function () { btnSave.disabled = false; });
      };
    });
  };

  // ---------- خزنة الكروت ----------
  function newUuid() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
    var b = new Uint8Array(16);
    window.crypto.getRandomValues(b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    var h = Array.prototype.map.call(b, function (x) { return (x < 16 ? '0' : '') + x.toString(16); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  var CARD_STATE_LABELS = { available: 'متاح', reserved: 'محجوز', sold: 'مباع', quarantined: 'محجور', invalidated: 'ملغى' };
  var lastBatchSignature = null;
  var lastBatchKey = null;
  views.cards = function () {
    return Promise.all([
      db.from('networks').select('id, commercial_name').order('commercial_name'),
      db.from('network_packages').select('id, network_id, name').order('name')
    ]).then(function (res) {
      if (res[0].error) throw res[0].error;
      if (res[1].error) throw res[1].error;
      var networks = res[0].data;
      var packages = res[1].data;

      var options = networks.map(function (n) { return '<option value="' + esc(n.id) + '">' + esc(n.commercial_name) + '</option>'; }).join('');
      viewEl.innerHTML = '<div class="card"><div class="card-header"><h3>رفع دفعة كروت</h3></div>' +
        '<div class="grid grid-2 mb-4">' +
          '<div><label>الشبكة</label><select id="c-up-network">' + options + '</select></div>' +
          '<div><label>الباقة</label><select id="c-up-package"></select></div>' +
        '</div>' +
        '<label>تاريخ الانتهاء (اختياري)</label><input type="date" id="c-up-expires" class="mb-4" dir="ltr">' +
        '<label>أرقام الكروت (PINs) — رقم في كل سطر</label><textarea id="c-up-pins" rows="5" class="mb-4" dir="ltr" style="text-align:left"></textarea>' +
        '<button class="btn btn-primary" id="c-upload">رفع الكروت</button></div>' +
        '<div class="card"><div class="card-header"><h3>الكروت الحالية (البيانات الوصفية)</h3></div>' +
        '<div class="flex gap-4 mb-4"><div style="flex:1"><label style="margin:0">الشبكة</label><select id="c-network">' + options + '</select></div>' +
        '<button class="btn btn-ghost" id="c-load" style="margin-top:20px">عرض</button></div>' +
        '<div id="c-result"></div></div>';

      var packagesByNetwork = {};
      packages.forEach(function(p) { (packagesByNetwork[p.network_id] = packagesByNetwork[p.network_id] || []).push(p); });

      var netSelect = document.getElementById('c-up-network');
      var pkgSelect = document.getElementById('c-up-package');
      function filterPackages() {
        var nid = netSelect.value;
        pkgSelect.innerHTML = (packagesByNetwork[nid] || []).map(function(p) { return '<option value="' + esc(p.id) + '">' + esc(p.name) + '</option>'; }).join('');
      }
      if (netSelect) { netSelect.onchange = filterPackages; filterPackages(); }

      var btnUpload = document.getElementById('c-upload');
      if (btnUpload) btnUpload.onclick = function () {
        var nid = netSelect.value;
        var pid = pkgSelect.value;
        var expires = document.getElementById('c-up-expires').value;
        if (!nid || !pid) return toast('اختر الشبكة والباقة', true);
        var pins = document.getElementById('c-up-pins').value.split('\n').map(function(s) { return s.trim(); }).filter(Boolean);
        if (!pins.length) return toast('أدخل كرت واحد على الأقل', true);
        // نفس قواعد الخادم (INVALID_CARD / TOO_MANY_CARDS) لرسالة أوضح قبل الإرسال
        if (pins.length > 5000) return toast(errText(new Error('TOO_MANY_CARDS')), true);
        for (var i = 0; i < pins.length; i++) {
          if (pins[i].length > 64 || /[\s\u0000-\u001f\u007f]/.test(pins[i])) {
            return toast('السطر ' + (i + 1) + ': رقم الكرت أطول من 64 خانة أو يحتوي مسافات', true);
          }
        }
        var p_cards = pins.map(function(pin) { return { pin: pin, expires_at: expires || null }; });

        // مفتاح الدفعة (idempotency): يبقى نفسه عند إعادة محاولة نفس المحتوى حتى لا تُرفع الدفعة مرتين
        var signature = [nid, pid, expires, pins.join('\n')].join('|');
        if (signature !== lastBatchSignature) { lastBatchSignature = signature; lastBatchKey = newUuid(); }

        btnUpload.disabled = true;
        rpc('admin_ingest_card_vault_batch', { p_network_id: nid, p_package_id: pid, p_cards: p_cards, p_batch_key: lastBatchKey })
          .then(function (r) {
            r = r || {};
            var msg = (r.replayed ? 'هذه الدفعة رُفعت مسبقاً — النتيجة السابقة: ' : '') + 'تم رفع ' + (Number(r.ingested_count) || 0) + ' كرت';
            if (Number(r.duplicates_skipped) > 0) msg += '، وتخطّي ' + Number(r.duplicates_skipped) + ' كرت مكرر';
            toast(msg);
            lastBatchSignature = null; lastBatchKey = null;
            document.getElementById('c-up-pins').value = '';
          }).catch(function (e) { console.error('NetYemen admin action failed:', e); toast(errText(e), true); }).finally(function () { btnUpload.disabled = false; });
      };

      var btnLoad = document.getElementById('c-load');
      if (btnLoad) btnLoad.onclick = function () {
        var nid = document.getElementById('c-network').value;
        if (!nid) return;
        btnLoad.disabled = true;
        rpc('admin_list_card_vault_metadata', { p_network_id: nid, p_state: null })
          .then(function (list) {
            var rows = (list || []).map(function (c) {
              return '<tr><td dir="ltr" class="text-sm">' + esc(c.batch_id) + '</td><td>' + esc(CARD_STATE_LABELS[c.state] || c.state) + '</td><td>' + when(c.created_at) + '</td><td>' + when(c.expires_at) + '</td></tr>';
            });
            document.getElementById('c-result').innerHTML = table(['الدفعة', 'الحالة', 'أُضيف', 'ينتهي'], rows);
          }).catch(function (e) {
            console.error('NetYemen admin: load failed', e);
            document.getElementById('c-result').innerHTML = errorBox(e, 'تعذّر تحميل بيانات الكروت');
          }).finally(function () { btnLoad.disabled = false; });
      };
    });
  };

  // الإقلاع
  db.auth.getSession().then(function (r) {
    if (r.data.session) return onSignedIn();
  }).catch(function (e) {
    console.error('NetYemen admin: session bootstrap failed', e);
    toast('تعذّر استعادة الجلسة، سجّل الدخول من جديد', true);
  });
})();
