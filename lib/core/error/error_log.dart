import 'dart:developer' as developer;

/// Records a technical failure for developers without showing it to users.
///
/// `dart:developer` logs stay on the device's debug channel (they are not
/// sent anywhere), so the raw error may be attached for diagnosis. Callers
/// must still show customers a generic message, never the raw error text,
/// and must not put personal data in [context].
void logError(String context, Object error, [StackTrace? stackTrace]) {
  developer.log(
    context,
    name: 'waselnet',
    level: 1000,
    error: error,
    stackTrace: stackTrace,
  );
}
