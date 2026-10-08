// lib/utils/card_batch_validator.dart
//
// منطق نقي (بدون واجهات) لتحليل دُفعة الكروت قبل رفعها. يطابق قواعد الخادم
// في `admin_ingest_card_vault_batch`: الرقم غير فارغ، لا يتجاوز 64 خانة،
// بلا مسافات أو محارف تحكّم، والدفعة لا تتجاوز 5000 كرت.

/// أقصى طول لرقم الكرت الواحد.
const int maxCardPinLength = 64;

/// أقصى عدد كروت في الدفعة الواحدة.
const int maxCardBatchSize = 5000;

// مسافات، محارف تحكّم (C0/C1)، ومحارف غير مرئية شائعة عند اللصق
// (zero-width و علامات الاتجاه و BOM).
final RegExp _forbiddenPinChars = RegExp(
  r'[\s\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202E\u2060\uFEFF]',
);

/// نتيجة تحليل نص الدفعة.
///
/// لا تحتوي أرقام الكروت المرفوضة أو المكررة نفسها — فقط أعدادها وأرقام
/// أسطرها (تبدأ من 1) حتى لا تُعرض الأرقام السرية على الشاشة.
class CardBatchValidation {
  /// الأرقام الصالحة بعد القص وحذف المكرر، بترتيب ورودها.
  final List<String> validPins;

  /// أرقام الأسطر التي كررت رقماً سبق وروده في نفس الدفعة.
  final List<int> duplicateLines;

  /// أرقام الأسطر المرفوضة (أطول من المسموح أو فيها مسافات/محارف تحكّم).
  final List<int> invalidLines;

  /// عدد الأسطر الفارغة التي تم تجاهلها.
  final int emptyLines;

  const CardBatchValidation({
    required this.validPins,
    required this.duplicateLines,
    required this.invalidLines,
    required this.emptyLines,
  });

  int get validCount => validPins.length;
  int get duplicateCount => duplicateLines.length;
  int get invalidCount => invalidLines.length;

  /// هل تجاوزت الدفعة الحد الأقصى؟
  bool get exceedsLimit => validPins.length > maxCardBatchSize;

  /// تُرفع الدفعة فقط إذا لم يكن فيها سطر مرفوض ولم تتجاوز الحد وفيها كرت
  /// واحد على الأقل. المكررات تُحذف بصمت (تُحتسب ولا تُرفع).
  bool get canUpload =>
      validPins.isNotEmpty && invalidLines.isEmpty && !exceedsLimit;
}

/// هل [pin] (بعد القص) رقم كرت مقبول؟
bool isValidCardPin(String pin) {
  if (pin.isEmpty) return false;
  if (pin.runes.length > maxCardPinLength) return false;
  return !_forbiddenPinChars.hasMatch(pin);
}

/// يحلّل النص الخام: رقم واحد في كل سطر.
CardBatchValidation validateCardBatch(String rawText) {
  final lines = rawText.split(RegExp(r'\r\n|\r|\n'));
  final seen = <String>{};
  final validPins = <String>[];
  final duplicateLines = <int>[];
  final invalidLines = <int>[];
  var emptyLines = 0;

  for (var i = 0; i < lines.length; i++) {
    final lineNumber = i + 1;
    final pin = lines[i].trim();
    if (pin.isEmpty) {
      emptyLines++;
      continue;
    }
    if (!isValidCardPin(pin)) {
      invalidLines.add(lineNumber);
      continue;
    }
    if (!seen.add(pin)) {
      duplicateLines.add(lineNumber);
      continue;
    }
    validPins.add(pin);
  }

  return CardBatchValidation(
    validPins: List<String>.unmodifiable(validPins),
    duplicateLines: List<int>.unmodifiable(duplicateLines),
    invalidLines: List<int>.unmodifiable(invalidLines),
    emptyLines: emptyLines,
  );
}

/// يعرض أرقام الأسطر بشكل مختصر: `3، 7، 9` أو `1، 2، 3 … (+12)`.
String formatLineNumbers(List<int> lines, {int max = 10}) {
  if (lines.length <= max) return lines.join('، ');
  final shown = lines.take(max).join('، ');
  return '$shown … (+${lines.length - max})';
}

/// نهاية اليوم المختار بتوقيت الجهاز، محوَّلة إلى UTC بصيغة ISO 8601.
///
/// الكرت يبقى صالحاً حتى آخر ثانية من اليوم الذي اختاره المالك، والقيمة
/// المرسلة تحمل `Z` فلا يفسّرها الخادم في منطقة زمنية أخرى.
String cardExpiryIsoUtc(DateTime day) {
  final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
  return endOfDay.toUtc().toIso8601String();
}

/// توقيع محتوى الدفعة: يتغيّر متى تغيّر أي شيء يُرسَل للخادم.
String cardBatchSignature({
  required String networkId,
  required String packageId,
  required String? expiresAt,
  required List<String> pins,
}) {
  return [networkId, packageId, expiresAt ?? '', ...pins].join('\n');
}

/// يحتفظ بمفتاح عدم التكرار (`p_batch_key`) للدفعة الجاري تحريرها.
///
/// نفس المحتوى ⇒ نفس المفتاح (حتى تكون إعادة المحاولة بعد خطأ أو انقطاع
/// آمنة). يُولَّد مفتاح جديد فقط عند تغيّر المحتوى أو بعد نجاح مؤكَّد.
class CardBatchKeyTracker {
  CardBatchKeyTracker(this._generate);

  final String Function() _generate;
  String? _key;
  String? _signature;

  String keyFor(String signature) {
    final current = _key;
    if (current != null && _signature == signature) return current;
    final fresh = _generate();
    _key = fresh;
    _signature = signature;
    return fresh;
  }

  /// يُستدعى بعد رد ناجح من الخادم.
  void confirmSuccess() {
    _key = null;
    _signature = null;
  }
}

/// نتيجة `admin_ingest_card_vault_batch`.
class CardBatchUploadResult {
  final String batchId;
  final int ingestedCount;
  final int duplicatesSkipped;
  final bool replayed;

  const CardBatchUploadResult({
    required this.batchId,
    required this.ingestedCount,
    required this.duplicatesSkipped,
    required this.replayed,
  });

  factory CardBatchUploadResult.fromJson(Map<String, dynamic> json) {
    return CardBatchUploadResult(
      batchId: json['batch_id']?.toString() ?? '',
      ingestedCount: _asInt(json['ingested_count']),
      duplicatesSkipped: _asInt(json['duplicates_skipped']),
      replayed: json['replayed'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
