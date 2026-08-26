import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/network_requests/data/fake_network_request_repository.dart';

void main() {
  group('FakeNetworkRequestRepository', () {
    late FakeNetworkRequestRepository repository;

    setUp(() {
      repository = FakeNetworkRequestRepository();
    });

    test('submitRequest creates a submitted request', () async {
      final request = await repository.submitRequest(
        idempotencyKey: 'key-1',
        observedSsidDisplay: 'MyHomeWiFi',
        proposedNetworkName: 'My Network',
        governorate: 'Sanaa',
      );

      expect(request.status, 'submitted');
      expect(request.observedSsidDisplay, 'MyHomeWiFi');
      expect(request.proposedNetworkName, 'My Network');
      expect(request.governorate, 'Sanaa');
    });

    test(
      'fetchMyRequests returns submitted requests in reverse order',
      () async {
        await repository.submitRequest(
          idempotencyKey: 'key-1',
          observedSsidDisplay: 'First',
        );
        await repository.submitRequest(
          idempotencyKey: 'key-2',
          observedSsidDisplay: 'Second',
        );

        final requests = await repository.fetchMyRequests();
        expect(requests.length, 2);
        expect(requests.first.observedSsidDisplay, 'Second');
      },
    );

    test('cancelRequest transitions status to cancelled', () async {
      final submitted = await repository.submitRequest(
        idempotencyKey: 'key-1',
        observedSsidDisplay: 'ToCancel',
      );

      final cancelled = await repository.cancelRequest(submitted.id);
      expect(cancelled.status, 'cancelled');

      final requests = await repository.fetchMyRequests();
      expect(requests.first.status, 'cancelled');
    });

    test('cancelRequest throws for unknown request', () async {
      expect(() => repository.cancelRequest('missing'), throwsException);
    });
  });
}
