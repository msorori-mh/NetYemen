import 'package:netyemen/features/security/data/pin_repository.dart';
import 'package:netyemen/features/security/domain/pin_status.dart';

/// Test double for [PinRepository]. Never holds a real PIN.
class FakePinRepository implements PinRepository {
  FakePinRepository({
    this.status = PinStatus.setAndTrusted,
    this.resolveError,
    this.verifyResult = true,
  });

  PinStatus status;

  /// When set, [resolveStatus] throws it — used to prove the gate fails closed.
  Object? resolveError;

  bool verifyResult;

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
    return verifyResult;
  }

  @override
  Future<void> requestReset() async => resetRequests++;

  @override
  Future<void> trustDevice(String userId) async => trustedUsers.add(userId);
}
