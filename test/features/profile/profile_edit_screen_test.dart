import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/features/profile/data/customer_profile_repository.dart';
import 'package:netyemen/features/profile/domain/customer_profile.dart';
import 'package:netyemen/features/profile/presentation/profile_edit_screen.dart';

void main() {
  const profile = CustomerProfile(
    id: 'profile-1',
    fullName: 'اسم قديم',
    governorate: 'مأرب',
    city: 'مدينة مأرب',
  );

  testWidgets('validates and saves customer profile fields', (tester) async {
    final repository = _FakeCustomerProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerProfileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ProfileEditScreen(profile: profile)),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('profile-full-name-field')),
      '  أحمد محمد  ',
    );
    await tester.tap(find.byKey(const Key('profile-governorate-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عدن').last);
    await tester.pumpAndSettle();
    final cityField = tester.widget<TextFormField>(
      find.byKey(const Key('profile-city-field')),
    );
    expect(cityField.controller?.text, isEmpty);
    expect(find.text('أدخل المدينة أو المديرية داخل عدن'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('profile-city-field')),
      '  كريتر  ',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pump();

    expect(repository.update?.fullName, '  أحمد محمد  ');
    expect(repository.update?.governorate, 'عدن');
    expect(repository.update?.city, '  كريتر  ');
    expect(repository.update?.toJson(), {
      'full_name': 'أحمد محمد',
      'default_governorate': 'عدن',
      'default_city': 'كريتر',
    });
  });

  testWidgets('rejects empty required profile fields', (tester) async {
    final repository = _FakeCustomerProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerProfileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ProfileEditScreen(profile: profile)),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('profile-full-name-field')),
      ' ',
    );
    await tester.enterText(find.byKey(const Key('profile-city-field')), ' ');
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pump();

    expect(find.text('الاسم مطلوب'), findsOneWidget);
    expect(find.text('المدينة مطلوب'), findsOneWidget);
    expect(repository.update, isNull);
  });

  testWidgets('shows a safe retry message when profile update fails', (
    tester,
  ) async {
    final repository = _FakeCustomerProfileRepository()..shouldFail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerProfileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ProfileEditScreen(profile: profile)),
      ),
    );

    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pump();

    expect(find.byKey(const Key('profile-update-error')), findsOneWidget);
    expect(
      find.text('تعذر حفظ الملف الشخصي. تحقق من الاتصال ثم أعد المحاولة.'),
      findsOneWidget,
    );
  });
}

class _FakeCustomerProfileRepository implements CustomerProfileRepository {
  CustomerProfileUpdate? update;
  bool shouldFail = false;

  @override
  Future<CustomerProfile?> fetchMyProfile() async => null;

  @override
  Future<void> updateMyProfile(CustomerProfileUpdate value) async {
    if (shouldFail) throw StateError('NETWORK_FAILURE');
    update = value;
  }
}
