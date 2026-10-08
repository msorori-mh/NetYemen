import 'package:flutter/services.dart';

/// Allows only digits (ASCII, Arabic-Indic or Persian) in a text field.
///
/// Unlike `FilteringTextInputFormatter.digitsOnly`, this keeps the digits an
/// Arabic keyboard produces instead of silently swallowing them.
class LocalizedDigitsInputFormatter extends TextInputFormatter {
  const LocalizedDigitsInputFormatter({this.maxLength});

  /// Optional maximum number of digits kept.
  final int? maxLength;

  static final RegExp _nonDigit = RegExp(r'[^0-9\u0660-\u0669\u06F0-\u06F9]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(_nonDigit, '');
    final limit = maxLength;
    if (limit != null && text.length > limit) {
      text = text.substring(0, limit);
    }
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
