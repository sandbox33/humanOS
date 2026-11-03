import 'package:drift/drift.dart';

/// The user's word on how a food keeps and travels (B4). A NULL column
/// means "not said": the suggestion from the food's group applies.
/// `food_key` is `f<food id>` or `b<barcode>`.
@DataClassName('FoodHandlingRow')
class FoodHandlingFlags extends Table {
  TextColumn get foodKey => text()();
  BoolColumn get needsCold => boolean().nullable()();
  BoolColumn get portable => boolean().nullable()();
  BoolColumn get needsCooking => boolean().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {foodKey};
}

/// A receipt line the user linked to a food once; the next receipt with the
/// same words is linked without asking again.
@DataClassName('ReceiptLinkRow')
class ReceiptLinks extends Table {
  /// The line's product words, normalised (`receiptKey`).
  TextColumn get lineKey => text()();
  IntColumn get foodId => integer().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {lineKey};
}
