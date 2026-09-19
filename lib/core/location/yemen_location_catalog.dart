class YemenLocationCatalog {
  const YemenLocationCatalog._();

  static const governorates = <String>[
    'أمانة العاصمة',
    'صنعاء',
    'عدن',
    'تعز',
    'الحديدة',
    'إب',
    'ذمار',
    'حضرموت',
    'مأرب',
    'الجوف',
    'صعدة',
    'حجة',
    'عمران',
    'المحويت',
    'ريمة',
    'البيضاء',
    'الضالع',
    'لحج',
    'أبين',
    'شبوة',
    'المهرة',
    'سقطرى',
  ];

  static List<String> optionsIncluding(String? currentValue) {
    final current = currentValue?.trim() ?? '';
    return <String>{
      if (current.isNotEmpty) current,
      ...governorates,
    }.toList(growable: false);
  }
}
