import 'package:netyemen/features/security/data/pin_repository.dart';
import 'package:netyemen/features/security/domain/pin_status.dart';

/// Test double for [PinRepository]. Never holds a real PIN.
class FakePinRepository implements PinRepository {
  FakePinRepository({
    this.status = PinStatus.setAndTrusted,
    this.resolveError,
    this.verifyResult = true,
    this.recentlyVerified = true,
  });

  PinStatus status;

  /// When set, [resolveStatus] throws it — used to prove the gate fails closed.
  Object? resolveError;

  bool verifyResult;

  /// What [hasRecentVerification] reports; a successful [verifyPin] sets it.
  bool recentlyVerified;

  /// When set, [verifyPin] throws it (e.g. `PIN_LOCKED`).
  Object? verifyError;

  final List<String> setPins = <String>[];
  final List<String> verifiedPins = <String>[];
  int resetRequests = 0;
  final List<String> trustedUsers = <String>[];

  @override
  Future<PinStatus> resolveStatus(String userId) async {
    if (resolveError != null) throw resolveError!;
    return status;
  }

  @override
  Future<void> setPin(String pin) async => setPins.add(pin);

  @override
  Future<bool> verifyPin(String pin) async {
    verifiedPins.add(pin);
    if (verifyError != null) throw verifyError!;
    if (verifyResult) recentlyVerified = true;
    return verifyResult;
  }

  @override
  Future<void> requestReset() async => resetRequests++;

  @override
  Future<void> trustDevice(String userId) async => trustedUsers.add(userId);

  @override
  Future<bool> hasRecentVerification() async => recentlyVerified;
}
