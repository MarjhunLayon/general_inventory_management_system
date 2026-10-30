import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:general_inventory_management/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late InventoryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = InventoryStore(await SharedPreferences.getInstance());
    await store.load();
  });

  test('seeds inventory and calculates stock totals', () {
    expect(store.products, hasLength(6));
    expect(store.products.map((product) => product.id).toSet(), hasLength(6));
    expect(store.totalUnits, 63);
    expect(store.lowStockCount, 2);
    expect(store.outOfStockCount, 1);
    expect(
        store.categories, containsAll(['Accessories', 'Cameras', 'Displays']));
  });

  test('records movements and restores them from local preferences', () async {
    final mouse =
        store.products.firstWhere((product) => product.sku == 'ACC-001');
    await store.recordMovement(mouse, 'IN', 5, 'Purchase order 42');

    expect(
        store.products.firstWhere((product) => product.id == mouse.id).quantity,
        29);
    expect(store.movements, hasLength(1));
    expect(store.inventoryValue, 137160);

    final restored = InventoryStore(await SharedPreferences.getInstance());
    await restored.load();
    expect(
        restored.products
            .firstWhere((product) => product.id == mouse.id)
            .quantity,
        29);
    expect(restored.movements.single.note, 'Purchase order 42');
  });

  test('rejects stock-outs greater than available quantity', () async {
    final mouse =
        store.products.firstWhere((product) => product.sku == 'ACC-001');

    await expectLater(
      store.recordMovement(mouse, 'OUT', mouse.quantity + 1, ''),
      throwsA(isA<StateError>()),
    );

    expect(
        store.products.firstWhere((product) => product.id == mouse.id).quantity,
        mouse.quantity);
    expect(store.movements, isEmpty);
  });

  test('records product creation and quantity adjustments in history',
      () async {
    final product = Product(
      id: 'new-product',
      name: 'New product',
      sku: 'NEW-001',
      category: 'Tools',
      quantity: 0,
      minStock: 5,
      cost: 10,
      price: 15,
    );
    await store.saveProduct(product);

    expect(store.movements.first.type, 'CREATED');
    expect(store.movements.first.quantity, 0);

    await store.saveProduct(product.copyWith(quantity: 8));
    expect(store.movements.first.type, 'IN');
    expect(store.movements.first.quantity, 8);
    expect(store.movements.first.note, 'Quantity adjusted');

    await store.saveProduct(product.copyWith(quantity: 3));
    expect(store.movements.first.type, 'OUT');
    expect(store.movements.first.quantity, 5);
    expect(store.movements.first.note, 'Quantity adjusted');
  });

  testWidgets('loads saved products when the current key is empty', (
    tester,
  ) async {
    final oldProduct = Product(
      id: 'legacy-pizza',
      name: 'Pizza',
      sku: 'FOOD-001',
      category: 'Food',
      quantity: 12,
      minStock: 3,
      cost: 50,
      price: 85,
    );
    final oldMovement = StockMovement(
      id: 'legacy-movement',
      productId: oldProduct.id,
      productName: oldProduct.name,
      type: 'IN',
      quantity: 4,
      date: DateTime(2026),
    );
    SharedPreferences.setMockInitialValues({
      'products_v1': jsonEncode([]),
      'movements_v1': jsonEncode([]),
      'inventory_products_v1': jsonEncode([oldProduct.toJson()]),
      'inventory_movements_v1': jsonEncode([oldMovement.toJson()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final restored = InventoryStore(preferences);
    await restored.load();

    expect(restored.products, hasLength(1));
    expect(restored.products.single.id, oldProduct.id);
    expect(restored.movements, hasLength(1));
    expect(restored.movements.single.id, oldMovement.id);
    expect(
      (jsonDecode(preferences.getString('products_v1')!) as List<dynamic>),
      hasLength(1),
    );
    expect(
      (jsonDecode(preferences.getString('inventory_products_v1')!)
          as List<dynamic>),
      hasLength(1),
    );

    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: restored)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsOneWidget);
  });

  test('preserves different products that share an old product ID', () async {
    final first = Product(
      id: 'legacy-id',
      name: 'Pizza',
      sku: 'FOOD-001',
      category: 'Food',
      quantity: 12,
      minStock: 3,
      cost: 50,
      price: 85,
    );
    final second = first.copyWith(
      name: 'Pizza Box',
      sku: 'PACK-001',
    );
    SharedPreferences.setMockInitialValues({
      'products_v1': jsonEncode([first.toJson()]),
      'inventory_products_v1': jsonEncode([second.toJson()]),
    });

    final restored = InventoryStore(await SharedPreferences.getInstance());
    await restored.load();

    expect(restored.products.map((product) => product.name),
        containsAll(['Pizza', 'Pizza Box']));
    expect(
      restored.products.map((product) => product.id).toSet(),
      hasLength(2),
    );
  });

  testWidgets('shows the splash screen before opening the dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(InventoryApp(store: store));
    await tester.pump();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'STOCKWISE');
    expect(find.text('STOCKWISE'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(find.text('STOCKWISE'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('shows a newly added product despite active stock filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: store)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('All stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In stock').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Product name'),
      'New filtered product',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'SKU / barcode'),
      'NEW-001',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category'),
      'Accessories',
    );
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();

    expect(find.text('New filtered product'), findsOneWidget);
  });

  testWidgets('reopening Products shows every product and clears search', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: store)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'not a match');
    await tester.pumpAndSettle();
    expect(find.text('Showing 0 of 6 products'), findsOneWidget);

    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 6 of 6 products'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
  });

  testWidgets('renders products in the phone list without layout errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: store)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Wireless Mouse'),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('product-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Wireless Mouse'), findsOneWidget);
    expect(find.text('Showing 6 of 6 products'), findsOneWidget);
  });

  testWidgets('shows supplier and description on product cards', (
    tester,
  ) async {
    await store.saveProduct(
      Product(
        id: 'metadata-product',
        name: 'Metadata item',
        sku: 'META-001',
        category: 'Tools',
        quantity: 4,
        minStock: 1,
        cost: 5,
        price: 8,
        supplier: 'Local supplier',
        description: 'Made for daily use',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: store)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'META-001');
    await tester.pumpAndSettle();

    expect(find.text('Local supplier'), findsOneWidget);
    expect(find.text('Made for daily use'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searches all product fields by multiple words and clears', (
    tester,
  ) async {
    await store.saveProduct(
      Product(
        id: 'search-product',
        name: 'A Widget Pro',
        sku: 'WID-001',
        category: 'Tools',
        quantity: 9,
        minStock: 2,
        cost: 10,
        price: 20,
        supplier: 'Wholesale Depot',
        description: 'Rugged aluminum case',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: store)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      '  WIDGET   WHOLESALE rugged  ',
    );
    await tester.pumpAndSettle();
    expect(find.text('A Widget Pro'), findsOneWidget);
    expect(find.text('Showing 1 of 7 products'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'not a match');
    await tester.pumpAndSettle();
    expect(find.text('A Widget Pro'), findsNothing);
    expect(find.text('Showing 0 of 7 products'), findsOneWidget);
    await tester.tap(find.text('Clear filters').last);
    await tester.pumpAndSettle();
    expect(find.text('A Widget Pro'), findsOneWidget);
  });

  testWidgets('shows a product table on wide screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(store: store)),
    );
    await tester.tap(find.text('Products').last);
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
  });
}
