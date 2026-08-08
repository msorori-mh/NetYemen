// lib/features/wallet/data/fake_wallet_repository.dart

import 'wallet_repository.dart';
import '../domain/entities.dart';

class FakeWalletRepository implements WalletRepository {
  final int _balance = 5000;
  final List<DepositRequest> _deposits = [
    DepositRequest(
      id: 'fake-deposit-1',
      amount: 2000,
      currency: 'YER',
      status: 'approved',
      proofReference: 'REF-123',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  @override
  Future<WalletSummary> getMyWalletSummary() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return WalletSummary(
      userId: 'fake-user',
      balance: _balance,
      currency: 'YER',
      accountStatus: 'active',
    );
  }

  @override
  Future<List<DepositRequest>> getMyDepositRequests() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_deposits);
  }

  @override
  Future<List<DepositChannel>> getActiveDepositChannels() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return const [
      DepositChannel(
        id: 'fake-bank',
        displayName: 'Kuraimi Bank (demo)',
        channelType: 'bank_transfer',
        accountReference: 'DEMO-123',
        instructions: 'Demo only',
        isActive: true,
      ),
    ];
  }

  @override
  Future<String> createDepositRequest({
    required int amount,
    String? channelId,
    String? proofReference,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final id = 'fake-deposit-${_deposits.length + 1}';
    _deposits.add(DepositRequest(
      id: id,
      amount: amount,
      currency: 'YER',
      status: 'submitted',
      channelId: channelId,
      proofReference: proofReference,
      createdAt: DateTime.now(),
    ));
    return id;
  }
}
