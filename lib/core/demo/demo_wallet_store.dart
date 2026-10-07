import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session-scoped wallet used only by the unconfigured demo build.
class DemoWalletStore {
  int _balance;

  DemoWalletStore({int initialBalance = 5000}) : _balance = initialBalance;

  int get balance => _balance;

  int debit(int amount) {
    if (amount <= 0) throw StateError('INVALID_PLAN_PRICE');
    if (_balance < amount) throw StateError('INSUFFICIENT_BALANCE');
    _balance -= amount;
    return _balance;
  }
}

final demoWalletStoreProvider = Provider<DemoWalletStore>((ref) {
  return DemoWalletStore();
});
