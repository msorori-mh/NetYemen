import 'dart:async';
import 'dart:developer' as developer;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/owner_providers.dart';
import 'providers/session_providers.dart';
import 'screens/pin_entry_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/app_theme.dart';
import 'utils/constants.dart';
import 'utils/pin_lock_policy.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: NetYemenOwnerApp()));
}

class NetYemenOwnerApp extends ConsumerStatefulWidget {
  const NetYemenOwnerApp({super.key});

  @override
  ConsumerState<NetYemenOwnerApp> createState() => _NetYemenOwnerAppState();
}

class _NetYemenOwnerAppState extends ConsumerState<NetYemenOwnerApp>
    with WidgetsBindingObserver {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  /// هوية المستخدم الذي بُنيت له البيانات الحالية (null = لا جلسة).
  String? _sessionUserId;

  bool _inBackground = false;
  bool _lockOverlayShown = false;
  Future<void>? _backgroundWrite;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionUserId = Supabase.instance.client.auth.currentUser?.id;
    if (_sessionUserId == null) {
      // لا جلسة عند الإقلاع: أي دخول قادم جلسة جديدة ويجب أن يطلب الرمز.
      unawaited(PinLockStore.clear());
    }
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// نقطة مركزية واحدة تستجيب لتغيّر المستخدم (دخول، خروج، تبديل حساب):
  /// تُبطل كل بيانات المالك، وعند غياب الجلسة تمسح ثقة رمز الدخول وتعود إلى
  /// المسار الجذر — وهو [SplashScreen] الذي يعرض الشاشة المناسبة تلقائياً.
  void _onAuthChanged(
    AsyncValue<AuthState>? previous,
    AsyncValue<AuthState> next,
  ) {
    final authState = next.valueOrNull;
    if (authState == null) return;

    final userId = authState.session?.user.id;
    if (userId == _sessionUserId) return;
    _sessionUserId = userId;

    invalidateOwnerData(ref);
    if (userId == null) {
      unawaited(PinLockStore.clear());
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      unawaited(_lockIfIdle());
    } else if (!_inBackground) {
      // أول مغادرة للواجهة فقط: العودة تمرّ بـ inactive قبل resumed ولا يجوز
      // أن تجدّد وقت آخر نشاط.
      _inBackground = true;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      _backgroundWrite =
          userId == null ? null : PinLockStore.recordBackgrounded(userId);
    }
  }

  /// يقفل التطبيق برمز الدخول إذا مرّت مهلة الخمول منذ مغادرة الواجهة.
  Future<void> _lockIfIdle() async {
    final pendingWrite = _backgroundWrite;
    _backgroundWrite = null;
    if (pendingWrite != null) await pendingWrite;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _lockOverlayShown) return;

    final locked = await PinLockStore.lockIfIdle(userId);
    if (!locked || !mounted || _lockOverlayShown) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      // لا يمكن عرض شاشة القفل فوق المحتوى: أعد تقييم الحاجز الجذر (مقفل).
      ref.invalidate(pinTrustedProvider);
      return;
    }

    _lockOverlayShown = true;
    final route = MaterialPageRoute<void>(
      builder: (_) => const PinEntryScreen(isAutoLock: true),
    );
    unawaited(
      navigator.push(route).whenComplete(() => _lockOverlayShown = false),
    );
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleLink(initialUri);
      }
    } catch (e) {
      // Ignore
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    }, onError: (err) {
      // Ignore
    });
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.queryParameters.containsKey('code')) {
      if (Supabase.instance.client.auth.currentSession == null) {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(uri);
        } on AuthException catch (e, stackTrace) {
          final message = e.message.toLowerCase();
          if (message.contains('code already used') ||
              message.contains('invalid') ||
              message.contains('pkce') ||
              message.contains('verifier')) {
            // Quietly ignore: supabase's internal listener might have won the race.
          } else {
            developer.log(
              'OAuth callback failed',
              name: 'owner.auth',
              error: e,
              stackTrace: stackTrace,
            );
            scaffoldMessengerKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('تعذّر إكمال تسجيل الدخول. حاول مرة أخرى.'),
              ),
            );
          }
        } catch (e) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('حدث خطأ أثناء معالجة الرابط')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthState>>(authStateProvider, _onAuthChanged);

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      locale: const Locale('ar', 'YE'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'YE'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.themeData,
      home: const SplashScreen(),
    );
  }
}
