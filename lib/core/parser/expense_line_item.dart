const expenseItemsMetadataKey = 'expenseItems';

class ExpenseLineItem {
  const ExpenseLineItem({required this.name, required this.amount});

  final String name;
  final double amount;

  bool get hasPositiveAmount => amount > 0;

  Map<String, Object?> toJson() => {'name': name, 'amount': amount};

  static ExpenseLineItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final amount = _doubleFrom(raw['amount']);
    if (amount == null) return null;
    return ExpenseLineItem(
      name: (raw['name'] as String?)?.trim() ?? '',
      amount: amount,
    );
  }
}

List<ExpenseLineItem> expenseLineItemsFromMetadata(
  Map<String, Object?> metadata,
) {
  final rawItems = metadata[expenseItemsMetadataKey];
  if (rawItems is List) {
    return rawItems
        .map(ExpenseLineItem.fromJson)
        .whereType<ExpenseLineItem>()
        .toList(growable: false);
  }

  final amount = _doubleFrom(metadata['amount']);
  if (amount == null) return const [];
  return [ExpenseLineItem(name: '', amount: amount)];
}

List<ExpenseLineItem> validExpenseLineItemsFromMetadata(
  Map<String, Object?> metadata,
) {
  return expenseLineItemsFromMetadata(
    metadata,
  ).where((item) => item.hasPositiveAmount).toList(growable: false);
}

double expenseLineItemsTotal(Iterable<ExpenseLineItem> items) {
  return items.fold<double>(0, (total, item) => total + item.amount);
}

Map<String, Object?> expenseMetadataForItems(
  Iterable<ExpenseLineItem> items, {
  Map<String, Object?> base = const {},
}) {
  final normalized = items.toList(growable: false);
  return {
    ...base,
    'amount': expenseLineItemsTotal(normalized),
    expenseItemsMetadataKey: normalized
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}

double? _doubleFrom(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
