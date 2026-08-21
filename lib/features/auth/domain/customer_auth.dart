enum RequestedAccountType { customer, networkOwner }

extension RequestedAccountTypeWire on RequestedAccountType {
  String get wireValue => switch (this) {
    RequestedAccountType.customer => 'customer',
    RequestedAccountType.networkOwner => 'network_owner',
  };

  String get arabicLabel => switch (this) {
    RequestedAccountType.customer => 'زبون',
    RequestedAccountType.networkOwner => 'صاحب شبكة',
  };
}

class TestAccountRegistration {
  final String fullName;
  final String phone;
  final String password;
  final RequestedAccountType requestedAccountType;
  final String governorate;
  final String city;
  final double latitude;
  final double longitude;
  final double? locationAccuracyMeters;
  final String inviteCode;

  const TestAccountRegistration({
    required this.fullName,
    required this.phone,
    required this.password,
    required this.requestedAccountType,
    required this.governorate,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.inviteCode,
    this.locationAccuracyMeters,
  });

  Map<String, Object?> toFunctionBody() => {
    'full_name': fullName.trim(),
    'phone': normalizeYemeniPhone(phone),
    'password': password,
    'requested_account_type': requestedAccountType.wireValue,
    'governorate': governorate.trim(),
    'city': city.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'location_accuracy_m': locationAccuracyMeters,
    'invite_code': inviteCode.trim(),
  };
}

String normalizeYemeniPhone(String input) {
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in input.trim().runes) {
    final character = String.fromCharCode(rune);
    final arabicIndex = arabicDigits.indexOf(character);
    final persianIndex = persianDigits.indexOf(character);
    if (arabicIndex >= 0) {
      buffer.write(arabicIndex);
    } else if (persianIndex >= 0) {
      buffer.write(persianIndex);
    } else if ('0123456789+'.contains(character)) {
      buffer.write(character);
    }
  }

  var phone = buffer.toString();
  if (phone.startsWith('00967')) {
    phone = '+${phone.substring(2)}';
  } else if (phone.startsWith('967')) {
    phone = '+$phone';
  } else if (phone.startsWith('0')) {
    phone = '+967${phone.substring(1)}';
  } else if (!phone.startsWith('+')) {
    phone = '+967$phone';
  }

  if (!RegExp(r'^\+9677\d{8}$').hasMatch(phone)) {
    throw const FormatException('رقم الهاتف اليمني غير صحيح');
  }
  return phone;
}

String? validateTestPassword(String value) {
  if (value.length < 8) return 'كلمة المرور يجب ألا تقل عن 8 أحرف';
  if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
    return 'استخدم حرفاً إنجليزياً ورقماً على الأقل';
  }
  return null;
}
