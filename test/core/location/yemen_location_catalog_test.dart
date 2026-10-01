import 'package:flutter_test/flutter_test.dart';
import 'package:netyemen/core/location/yemen_location_catalog.dart';

void main() {
  test('catalog exposes the 22 unique Yemeni governorates', () {
    expect(YemenLocationCatalog.governorates, hasLength(22));
    expect(YemenLocationCatalog.governorates.toSet(), hasLength(22));
    expect(YemenLocationCatalog.governorates, contains('أمانة العاصمة'));
    expect(YemenLocationCatalog.governorates, contains('سقطرى'));
  });

  test('current legacy value stays selectable without duplication', () {
    final options = YemenLocationCatalog.optionsIncluding(' محافظة قديمة ');

    expect(options.first, 'محافظة قديمة');
    expect(options.where((value) => value == 'محافظة قديمة'), hasLength(1));
    expect(
      YemenLocationCatalog.optionsIncluding('عدن')
          .where((value) => value == 'عدن'),
      hasLength(1),
    );
  });
}
