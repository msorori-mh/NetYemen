/// PIN state returned by [PinRepository.hasPin].
enum PinStatus {
  /// The user has not set a PIN yet.
  notSet,

  /// The user has a PIN and this device is trusted.
  setAndTrusted,

  /// The user has a PIN but this device is NOT trusted (must verify).
  setAndUntrusted,
}
