// lib/utils/constants.dart
// ⚠️ عدل هذه القيم ببيانات Supabase الخاصة بك

class AppConstants {
  // V1 uses environment variables (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY).
  // These legacy constants are kept empty so the app never defaults to a
  // remote project or hardcoded credentials.
  static const String supabaseUrl = '';
  static const String supabaseAnonKey = '';

  static const String appName = 'WASEL NET';
  static const String appNameAr = 'واصل نت';
  static const String appVersion = '1.0.0';

  // ALAWAEL SMS API (لاحقاً — يُملأ يدوياً عند الربط)
  static const String alawaelApiKey = '';
  static const String alawaelSenderId = 'WASELNET';
}
