import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/purchase/data/supabase_purchase_repository.dart';
import 'package:netyemen/features/wallet/data/supabase_wallet_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "My purchases" / "my deposits" must filter by the signed-in user: RLS lets
/// network owners, finance and admins read other customers' rows too.
void main() {
  late HttpServer server;
  late List<Uri> requests;
  late SupabaseClient client;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<Object>[]));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('purchase history is filtered by the current user id', () async {
    final repository = SupabasePurchaseRepository(
      client,
      currentUserId: () => 'user-1',
    );

    expect(await repository.getMyPurchaseOrders(), isEmpty);

    expect(requests, hasLength(1));
    expect(requests.single.path, '/rest/v1/purchase_records');
    expect(requests.single.queryParameters['user_id'], 'eq.user-1');
  });

  test('deposit history is filtered by the current user id', () async {
    final repository = SupabaseWalletRepository(
      client,
      currentUserId: () => 'user-1',
    );

    expect(await repository.getMyDepositRequests(), isEmpty);

    expect(requests, hasLength(1));
    expect(requests.single.path, '/rest/v1/wallet_deposit_requests');
    expect(requests.single.queryParameters['user_id'], 'eq.user-1');
  });

  test('no signed-in user returns an empty list without querying', () async {
    expect(
      await SupabasePurchaseRepository(client).getMyPurchaseOrders(),
      isEmpty,
    );
    expect(
      await SupabaseWalletRepository(client).getMyDepositRequests(),
      isEmpty,
    );
    expect(requests, isEmpty);
  });
}
