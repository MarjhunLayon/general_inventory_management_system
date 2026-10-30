import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _background = Color(0xFF0D1117);
const _surface = Color(0xFF151B23);
const _surfaceRaised = Color(0xFF1B2430);
const _green = Color(0xFF35D07F);
const _muted = Color(0xFF8A96A8);

String money(num value) => NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    ).format(value);

int _lastGeneratedId = 0;

String _id() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  _lastGeneratedId =
      timestamp > _lastGeneratedId ? timestamp : _lastGeneratedId + 1;
  return _lastGeneratedId.toString();
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.quantity,
    required this.minStock,
    required this.cost,
    required this.price,
    this.supplier = '',
    this.description = '',
  });

  final String id;
  final String name;
  final String sku;
  final String category;
  final int quantity;
  final int minStock;
  final double cost;
  final double price;
  final String supplier;
  final String description;

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? category,
    int? quantity,
    int? minStock,
    double? cost,
    double? price,
    String? supplier,
    String? description,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        category: category ?? this.category,
        quantity: quantity ?? this.quantity,
        minStock: minStock ?? this.minStock,
        cost: cost ?? this.cost,
        price: price ?? this.price,
        supplier: supplier ?? this.supplier,
        description: description ?? this.description,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'category': category,
        'quantity': quantity,
        'minStock': minStock,
        'cost': cost,
        'price': price,
        'supplier': supplier,
        'description': description,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String,
        category: json['category'] as String,
        quantity: (json['quantity'] as num).toInt(),
        minStock: (json['minStock'] as num).toInt(),
        cost: (json['cost'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        supplier: json['supplier'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );
}

class StockMovement {
  StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.date,
    this.note = '',
  });

  final String id;
  final String productId;
  final String productName;
  final String type;
  final int quantity;
  final DateTime date;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'type': type,
        'quantity': quantity,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        type: json['type'] as String,
        quantity: (json['quantity'] as num).toInt(),
        date: DateTime.parse(json['date'] as String),
        note: json['note'] as String? ?? '',
      );
}

class InventoryStore extends ChangeNotifier {
  InventoryStore(this._preferences);

  final SharedPreferences _preferences;
  static const _productsKey = 'products_v1';
  static const _movementsKey = 'movements_v1';
  static const _previousProductsKey = 'inventory_products_v1';
  static const _previousMovementsKey = 'inventory_movements_v1';
  final List<Product> products = [];
  final List<StockMovement> movements = [];

  Future<void> load() async {
    final savedProducts = _mergeStoredEntries(
      _preferences.getString(_productsKey),
      _preferences.getString(_previousProductsKey),
      identity: (item) => '${item['id']}|${item['sku']}',
    );
    final savedMovements = _mergeStoredEntries(
      _preferences.getString(_movementsKey),
      _preferences.getString(_previousMovementsKey),
      identity: (item) => '${item['id']}|${item['date']}',
    );
    if (savedProducts == null) {
      products.addAll(_seed());
    } else {
      final usedIds = <String>{};
      for (final json in savedProducts) {
        var product = Product.fromJson(json);
        while (!usedIds.add(product.id)) {
          product = product.copyWith(id: _id());
        }
        products.add(product);
      }
    }
    if (savedMovements != null) {
      movements.addAll(savedMovements.map(StockMovement.fromJson));
    }
    await _save();
    notifyListeners();
  }

  List<Map<String, dynamic>>? _mergeStoredEntries(
      String? current, String? previous,
      {required String Function(Map<String, dynamic>) identity}) {
    if (current == null && previous == null) return null;

    final entriesById = <String, Map<String, dynamic>>{};
    for (final json in [previous, current]) {
      if (json == null) continue;
      final entries = jsonDecode(json) as List<dynamic>;
      for (final entry in entries) {
        final item = entry as Map<String, dynamic>;
        entriesById[identity(item)] = item;
      }
    }
    return entriesById.values.toList();
  }

  int get totalUnits =>
      products.fold(0, (total, product) => total + product.quantity);
  int get lowStockCount => products
      .where(
        (product) =>
            product.quantity > 0 && product.quantity <= product.minStock,
      )
      .length;
  int get outOfStockCount =>
      products.where((product) => product.quantity == 0).length;
  double get inventoryValue => products.fold(
        0,
        (total, product) => total + product.quantity * product.cost,
      );
  List<String> get categories {
    final values = products.map((product) => product.category).toSet().toList()
      ..sort();
    return values;
  }

  Future<void> saveProduct(Product product) async {
    final index = products.indexWhere((item) => item.id == product.id);
    if (index == -1) {
      products.insert(0, product);
      movements.insert(
        0,
        StockMovement(
          id: _id(),
          productId: product.id,
          productName: product.name,
          type: 'CREATED',
          quantity: product.quantity,
          date: DateTime.now(),
        ),
      );
    } else {
      final previous = products[index];
      products[index] = product;
      final quantityChange = product.quantity - previous.quantity;
      if (quantityChange != 0) {
        movements.insert(
          0,
          StockMovement(
            id: _id(),
            productId: product.id,
            productName: product.name,
            type: quantityChange > 0 ? 'IN' : 'OUT',
            quantity: quantityChange.abs(),
            date: DateTime.now(),
            note: 'Quantity adjusted',
          ),
        );
      }
    }
    notifyListeners();
    await _save();
  }

  Future<void> deleteProduct(Product product) async {
    products.removeWhere((item) => item.id == product.id);
    notifyListeners();
    await _save();
  }

  Future<void> recordMovement(
    Product product,
    String type,
    int quantity,
    String note,
  ) async {
    if (quantity <= 0)
      throw ArgumentError('Quantity must be greater than zero.');
    if (type == 'OUT' && quantity > product.quantity) {
      throw StateError(
        'There are not enough units in stock for this stock-out.',
      );
    }
    final updated = product.copyWith(
      quantity: product.quantity + (type == 'IN' ? quantity : -quantity),
    );
    products[products.indexWhere((item) => item.id == product.id)] = updated;
    movements.insert(
      0,
      StockMovement(
        id: _id(),
        productId: product.id,
        productName: product.name,
        type: type,
        quantity: quantity,
        date: DateTime.now(),
        note: note,
      ),
    );
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final productsJson =
        jsonEncode(products.map((product) => product.toJson()).toList());
    final movementsJson =
        jsonEncode(movements.map((movement) => movement.toJson()).toList());
    final saved = await Future.wait([
      _preferences.setString(_productsKey, productsJson),
      _preferences.setString(_movementsKey, movementsJson),
      _preferences.setString(_previousProductsKey, productsJson),
      _preferences.setString(_previousMovementsKey, movementsJson),
    ]);
    if (saved.any((success) => !success)) {
      throw StateError('Inventory changes could not be saved to this device.');
    }
  }

  List<Product> _seed() => [
        Product(
          id: _id(),
          name: 'Wireless Mouse',
          sku: 'ACC-001',
          category: 'Accessories',
          quantity: 24,
          minStock: 8,
          cost: 450,
          price: 799,
          supplier: 'TechSupply Co.',
        ),
        Product(
          id: _id(),
          name: 'Mechanical Keyboard',
          sku: 'ACC-002',
          category: 'Accessories',
          quantity: 6,
          minStock: 10,
          cost: 1800,
          price: 2699,
          supplier: 'TechSupply Co.',
        ),
        Product(
          id: _id(),
          name: 'USB-C Hub',
          sku: 'ACC-003',
          category: 'Accessories',
          quantity: 0,
          minStock: 5,
          cost: 950,
          price: 1499,
          supplier: 'Gadget House',
        ),
        Product(
          id: _id(),
          name: '27-inch Monitor',
          sku: 'DSP-001',
          category: 'Displays',
          quantity: 12,
          minStock: 4,
          cost: 8200,
          price: 10999,
          supplier: 'Vision Electronics',
        ),
        Product(
          id: _id(),
          name: 'Laptop Stand',
          sku: 'ACC-004',
          category: 'Accessories',
          quantity: 18,
          minStock: 6,
          cost: 620,
          price: 999,
          supplier: 'Gadget House',
        ),
        Product(
          id: _id(),
          name: 'Webcam HD',
          sku: 'CAM-001',
          category: 'Cameras',
          quantity: 3,
          minStock: 5,
          cost: 1250,
          price: 1899,
          supplier: 'Vision Electronics',
        ),
      ];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final store = InventoryStore(preferences);
  await store.load();
  runApp(InventoryApp(store: store));
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key, required this.store});

  final InventoryStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'STOCKWISE',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _green,
            brightness: Brightness.dark,
            surface: _surface,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: _background,
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
        home: SplashScreen(store: store),
      );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.store});

  final InventoryStore store;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = curved;
    _scale = Tween<double>(begin: 0.75, end: 1).animate(curved);
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1800), _openDashboard);
  }

  void _openDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            InventoryHome(store: widget.store),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.15),
              radius: 1.15,
              colors: [_surfaceRaised, _background],
            ),
          ),
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: _green.withValues(alpha: 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _green.withValues(alpha: 0.12),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: _green,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'STOCKWISE',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Inventory, in control.',
                      style: TextStyle(color: _muted, fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    const SizedBox(
                      width: 88,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                        backgroundColor: _surfaceRaised,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({super.key, required this.store});
  final InventoryStore store;

  @override
  State<InventoryHome> createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome> {
  int _selected = 0;
  final _productsPageKey = GlobalKey<_ProductsPageState>();
  static const _titles = ['Dashboard', 'Products', 'Stock history', 'Reports'];

  void _selectPage(int index) {
    if (index == 1) {
      _productsPageKey.currentState?.showAllProducts();
    }
    setState(() => _selected = index);
  }

  Future<void> _addProduct() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => const ProductFormDialog(),
    );
    if (product != null) await _run(() => widget.store.saveProduct(product));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      DashboardPage(
        store: widget.store,
        onNavigate: _selectPage,
      ),
      ProductsPage(
        key: _productsPageKey,
        store: widget.store,
        onRun: _run,
      ),
      HistoryPage(store: widget.store),
      ReportsPage(store: widget.store),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selected],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_selected == 1)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add, size: 19),
                label: const Text('Add product'),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _selected,
              onDestinationSelected: _selectPage,
              labelType: NavigationRailLabelType.all,
              backgroundColor: _background,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: Text('Overview'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: Text('Products'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history),
                  label: Text('History'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_rounded),
                  label: Text('Reports'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(index: _selected, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selected,
              onDestinationSelected: _selectPage,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: 'Products',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_rounded),
                  label: 'Reports',
                ),
              ],
            ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.store,
    required this.onNavigate,
  });
  final InventoryStore store;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final alerts = store.products
            .where((p) => p.quantity <= p.minStock)
            .take(4)
            .toList();
        final recent = store.movements.take(5).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              'Here’s what’s happening with your inventory.',
              style: TextStyle(color: _muted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1200
                    ? 5
                    : constraints.maxWidth > 1000
                        ? 4
                        : constraints.maxWidth > 560
                            ? 2
                            : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                final metrics = [
                  _Metric(
                    'Total products',
                    '${store.products.length}',
                    Icons.inventory_2_outlined,
                    const Color(0xFF7C9CFF),
                  ),
                  _Metric(
                    'Stock units',
                    '${store.totalUnits}',
                    Icons.layers_outlined,
                    _green,
                  ),
                  _Metric(
                    'Low stock',
                    '${store.lowStockCount}',
                    Icons.warning_amber_rounded,
                    const Color(0xFFFFB454),
                  ),
                  _Metric(
                    'Out of stock',
                    '${store.outOfStockCount}',
                    Icons.remove_shopping_cart_outlined,
                    const Color(0xFFFF7272),
                  ),
                  _Metric(
                    'Inventory value',
                    money(store.inventoryValue),
                    Icons.payments_outlined,
                    const Color(0xFFCB8CFF),
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: metrics
                      .map(
                        (metric) => SizedBox(
                          width: width,
                          child: _MetricCard(metric: metric),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      _AlertsCard(
                        alerts: alerts,
                        onViewAll: () => onNavigate(1),
                      ),
                      const SizedBox(height: 16),
                      _ActivityCard(
                        movements: recent,
                        onViewAll: () => onNavigate(2),
                      ),
                      const SizedBox(height: 16),
                      _CategoriesCard(store: store),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          _AlertsCard(
                            alerts: alerts,
                            onViewAll: () => onNavigate(1),
                          ),
                          const SizedBox(height: 16),
                          _CategoriesCard(store: store),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _ActivityCard(
                        movements: recent,
                        onViewAll: () => onNavigate(2),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Metric {
  const _Metric(this.title, this.value, this.icon, this.color);
  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  metric.title,
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                Icon(metric.icon, color: metric.color, size: 20),
              ],
            ),
            const SizedBox(height: 15),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                metric.value,
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.045)),
        ),
        child: child,
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.alerts, required this.onViewAll});
  final List<Product> alerts;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(
              'Stock alerts',
              trailing: TextButton(
                onPressed: onViewAll,
                child: const Text('View products'),
              ),
            ),
            if (alerts.isEmpty)
              const _EmptyState('All stocked up', 'No products need attention.')
            else
              ...alerts.map(
                (product) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      _ProductIcon(category: product.category),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              product.category,
                              style:
                                  const TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _StockBadge(
                        quantity: product.quantity,
                        minStock: product.minStock,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.movements, required this.onViewAll});
  final List<StockMovement> movements;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(
              'Recent activity',
              trailing: TextButton(
                onPressed: onViewAll,
                child: const Text('View history'),
              ),
            ),
            if (movements.isEmpty)
              const _EmptyState(
                'No activity yet',
                'Stock movements will appear here.',
              )
            else
              ...movements.map(
                (movement) => Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: _MovementRow(movement: movement),
                ),
              ),
          ],
        ),
      );
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.store});
  final InventoryStore store;

  @override
  Widget build(BuildContext context) {
    final categories = store.categories;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading('Categories'),
          if (categories.isEmpty)
            const _EmptyState(
              'No categories yet',
              'Add products to see a breakdown.',
            )
          else
            ...categories.map((category) {
              final count =
                  store.products.where((p) => p.category == category).length;
              final fraction = count / store.products.length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(category)),
                        Text(
                          '$count ${count == 1 ? 'product' : 'products'}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        backgroundColor: _surfaceRaised,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(subtitle,
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
      );
}

class _ProductIcon extends StatelessWidget {
  const _ProductIcon({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final icon = switch (category.toLowerCase()) {
      'displays' => Icons.monitor_outlined,
      'cameras' => Icons.camera_alt_outlined,
      'audio' => Icons.headphones_outlined,
      _ => Icons.devices_other_outlined,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _surfaceRaised,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 19, color: _green),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.minStock});
  final int quantity;
  final int minStock;

  @override
  Widget build(BuildContext context) {
    final out = quantity == 0;
    final color = out ? const Color(0xFFFF7272) : const Color(0xFFFFB454);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        out ? 'Out of stock' : '$quantity left',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.store, required this.onRun});
  final InventoryStore store;
  final Future<void> Function(Future<void> Function()) onRun;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _search = TextEditingController();
  String _category = 'All categories';
  String _stock = 'All stock';
  String _sort = 'Name';
  late Set<String> _knownProductIds;

  @override
  void initState() {
    super.initState();
    _knownProductIds =
        widget.store.products.map((product) => product.id).toSet();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void didUpdateWidget(covariant ProductsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      _knownProductIds =
          widget.store.products.map((product) => product.id).toSet();
      widget.store.addListener(_handleStoreChanged);
    }
  }

  void _handleStoreChanged() {
    final productIds =
        widget.store.products.map((product) => product.id).toSet();
    final hasNewProduct = productIds.difference(_knownProductIds).isNotEmpty;
    _knownProductIds = productIds;
    if (!hasNewProduct || !mounted) return;

    _search.clear();
    setState(() {
      _category = 'All categories';
      _stock = 'All stock';
      _sort = 'Name';
    });
  }

  bool get _hasActiveFilters =>
      _search.text.trim().isNotEmpty ||
      _category != 'All categories' ||
      _stock != 'All stock';

  void showAllProducts() {
    _search.clear();
    setState(() {
      _category = 'All categories';
      _stock = 'All stock';
      _sort = 'Name';
    });
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _category = 'All categories';
      _stock = 'All stock';
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(Product? product) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (_) => ProductFormDialog(product: product),
    );
    if (result != null) {
      await widget.onRun(() => widget.store.saveProduct(result));
    }
  }

  Future<void> _movement(Product product) async {
    final result = await showDialog<_MovementInput>(
      context: context,
      builder: (_) => MovementDialog(product: product),
    );
    if (result != null) {
      await widget.onRun(
        () => widget.store.recordMovement(
          product,
          result.type,
          result.quantity,
          result.note,
        ),
      );
    }
  }

  Future<void> _delete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('“${product.name}” will be removed from your inventory.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD95656),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onRun(() => widget.store.deleteProduct(product));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final query =
              _search.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          final queryWords =
              query.split(' ').where((word) => word.isNotEmpty).toList();
          final products = widget.store.products.where((product) {
            final searchableText = [
              product.name,
              product.sku,
              product.category,
              product.supplier,
              product.description,
            ].join(' ').toLowerCase();
            final normalizedText =
                searchableText.replaceAll(RegExp(r'\s+'), ' ');
            final matchesSearch = queryWords.every(normalizedText.contains);
            final matchesCategory =
                _category == 'All categories' || product.category == _category;
            final matchesStock = switch (_stock) {
              'Low stock' =>
                product.quantity > 0 && product.quantity <= product.minStock,
              'Out of stock' => product.quantity == 0,
              'In stock' => product.quantity > product.minStock,
              _ => true,
            };
            return matchesSearch && matchesCategory && matchesStock;
          }).toList();
          products.sort(
            (a, b) => _sort == 'Quantity'
                ? a.quantity.compareTo(b.quantity)
                : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            'Search name, SKU, category, supplier, or description',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterDropdown(
                            value: _category,
                            values: [
                              'All categories',
                              ...widget.store.categories
                            ],
                            onChanged: (value) =>
                                setState(() => _category = value),
                          ),
                          const SizedBox(width: 8),
                          _FilterDropdown(
                            value: _stock,
                            values: const [
                              'All stock',
                              'In stock',
                              'Low stock',
                              'Out of stock',
                            ],
                            onChanged: (value) =>
                                setState(() => _stock = value),
                          ),
                          const SizedBox(width: 8),
                          _FilterDropdown(
                            value: _sort,
                            values: const ['Name', 'Quantity'],
                            onChanged: (value) => setState(() => _sort = value),
                            label: 'Sort',
                          ),
                        ],
                      ),
                    ),
                    if (_hasActiveFilters)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Clear filters'),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Showing ${products.length} of '
                    '${widget.store.products.length} products',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _EmptyState(
                              'No products found',
                              'Try a shorter search or clear the active filters.',
                            ),
                            if (_hasActiveFilters)
                              TextButton.icon(
                                onPressed: _clearFilters,
                                icon: const Icon(
                                  Icons.filter_alt_off_outlined,
                                ),
                                label: const Text('Clear filters'),
                              ),
                          ],
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 1000
                              ? 3
                              : constraints.maxWidth >= 650
                                  ? 2
                                  : 1;
                          if (columns == 1) {
                            return ListView.separated(
                              key: const ValueKey('product-list'),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: products.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) => _ProductCard(
                                product: products[index],
                                onEdit: () => _edit(products[index]),
                                onMovement: () => _movement(products[index]),
                                onDelete: () => _delete(products[index]),
                              ),
                            );
                          }
                          if (columns == 3) {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Product')),
                                    DataColumn(label: Text('Supplier')),
                                    DataColumn(label: Text('Description')),
                                    DataColumn(label: Text('Category')),
                                    DataColumn(label: Text('Stock')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Selling price')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: products
                                      .map(
                                        (product) => DataRow(
                                          cells: [
                                            DataCell(
                                              SizedBox(
                                                width: 240,
                                                child: Row(
                                                  children: [
                                                    _ProductIcon(
                                                      category:
                                                          product.category,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            product.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          Text(
                                                            product.sku,
                                                            style:
                                                                const TextStyle(
                                                              color: _muted,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 180,
                                                child: Text(
                                                  product.supplier.isEmpty
                                                      ? 'Not specified'
                                                      : product.supplier,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 240,
                                                child: Text(
                                                  product.description.isEmpty
                                                      ? 'No description'
                                                      : product.description,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(Text(product.category)),
                                            DataCell(
                                              Text('${product.quantity} units'),
                                            ),
                                            DataCell(
                                              _StockBadge(
                                                quantity: product.quantity,
                                                minStock: product.minStock,
                                              ),
                                            ),
                                            DataCell(
                                                Text(money(product.price))),
                                            DataCell(
                                              PopupMenuButton<String>(
                                                onSelected: (action) {
                                                  switch (action) {
                                                    case 'edit':
                                                      _edit(product);
                                                    case 'movement':
                                                      _movement(product);
                                                    case 'delete':
                                                      _delete(product);
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Edit product'),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'movement',
                                                    child: Text(
                                                      'Record stock movement',
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text(
                                                      'Delete product',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            );
                          }
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: products.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              mainAxisExtent: 270,
                            ),
                            itemBuilder: (context, index) => _ProductCard(
                              product: products[index],
                              onEdit: () => _edit(products[index]),
                              onMovement: () => _movement(products[index]),
                              onDelete: () => _delete(products[index]),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.values,
    required this.onChanged,
    this.label,
  });
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            dropdownColor: _surface,
            items: values
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            hint: label == null ? null : Text(label!),
          ),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onMovement,
    required this.onDelete,
  });
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onMovement;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _Panel(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProductIcon(category: product.category),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.sku,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        onEdit();
                      case 'movement':
                        onMovement();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit product')),
                    PopupMenuItem(
                      value: 'movement',
                      child: Text('Record stock movement'),
                    ),
                    PopupMenuItem(
                        value: 'delete', child: Text('Delete product')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ProductDetail(
              label: 'Supplier',
              value: product.supplier.isEmpty
                  ? 'Not specified'
                  : product.supplier,
            ),
            const SizedBox(height: 8),
            _ProductDetail(
              label: 'Description',
              value: product.description.isEmpty
                  ? 'No description'
                  : product.description,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  product.category,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                _StockBadge(
                    quantity: product.quantity, minStock: product.minStock),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${product.quantity} units',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  money(product.price),
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ProductDetail extends StatelessWidget {
  const _ProductDetail({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      );
}

class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({super.key, this.product});
  final Product? product;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late final TextEditingController _quantity;
  late final TextEditingController _minStock;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _supplier;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _sku = TextEditingController(text: product?.sku ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _quantity = TextEditingController(text: '${product?.quantity ?? 0}');
    _minStock = TextEditingController(text: '${product?.minStock ?? 5}');
    _cost = TextEditingController(text: '${product?.cost ?? 0}');
    _price = TextEditingController(text: '${product?.price ?? 0}');
    _supplier = TextEditingController(text: product?.supplier ?? '');
    _description = TextEditingController(text: product?.description ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _sku,
      _category,
      _quantity,
      _minStock,
      _cost,
      _price,
      _supplier,
      _description,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
  String? _number(String? value, {bool decimal = false}) {
    if (_required(value) != null) return _required(value);
    final parsed = decimal ? double.tryParse(value!) : int.tryParse(value!);
    if (parsed == null || parsed < 0)
      return 'Enter a valid non-negative number.';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Product(
        id: widget.product?.id ?? _id(),
        name: _name.text.trim(),
        sku: _sku.text.trim(),
        category: _category.text.trim(),
        quantity: int.parse(_quantity.text),
        minStock: int.parse(_minStock.text),
        cost: double.parse(_cost.text),
        price: double.parse(_price.text),
        supplier: _supplier.text.trim(),
        description: _description.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product == null ? 'Add product' : 'Edit product'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _formField(_name, 'Product name', validator: _required),
                  _formField(_sku, 'SKU / barcode', validator: _required),
                  _formField(_category, 'Category', validator: _required),
                  Row(
                    children: [
                      Expanded(
                        child: _formField(
                          _quantity,
                          'Quantity',
                          keyboardType: TextInputType.number,
                          validator: _number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _formField(
                          _minStock,
                          'Minimum stock',
                          keyboardType: TextInputType.number,
                          validator: _number,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _formField(
                          _cost,
                          'Cost price',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) => _number(v, decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _formField(
                          _price,
                          'Selling price',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) => _number(v, decimal: true),
                        ),
                      ),
                    ],
                  ),
                  _formField(_supplier, 'Supplier (optional)'),
                  _formField(_description, 'Description (optional)',
                      maxLines: 2),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save product')),
        ],
      );
}

Widget _formField(
  TextEditingController controller,
  String label, {
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  int maxLines = 1,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );

class _MovementInput {
  const _MovementInput(this.type, this.quantity, this.note);
  final String type;
  final int quantity;
  final String note;
}

class MovementDialog extends StatefulWidget {
  const MovementDialog({super.key, required this.product});
  final Product product;

  @override
  State<MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  String _type = 'IN';

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Record stock movement'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${widget.product.name} · ${widget.product.quantity} available',
                    style: const TextStyle(color: _muted),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'IN',
                      label: Text('Stock in'),
                      icon: Icon(Icons.add),
                    ),
                    ButtonSegment(
                      value: 'OUT',
                      label: Text('Stock out'),
                      icon: Icon(Icons.remove),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selection) =>
                      setState(() => _type = selection.first),
                ),
                const SizedBox(height: 12),
                _formField(
                  _quantity,
                  'Quantity',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final amount = int.tryParse(value ?? '');
                    if (amount == null || amount <= 0)
                      return 'Enter a quantity greater than zero.';
                    if (_type == 'OUT' && amount > widget.product.quantity) {
                      return 'Only ${widget.product.quantity} units are available.';
                    }
                    return null;
                  },
                ),
                _formField(_note, 'Note or reference (optional)'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _MovementInput(
                    _type, int.parse(_quantity.text), _note.text.trim()),
              );
            },
            child: const Text('Save movement'),
          ),
        ],
      );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.store});
  final InventoryStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          if (store.movements.isEmpty) {
            return const Center(
              child: _EmptyState(
                'No stock movements',
                'Record a stock-in or stock-out to get started.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: store.movements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _Panel(
              child: _MovementRow(
                  movement: store.movements[index], showDate: true),
            ),
          );
        },
      );
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement, this.showDate = false});
  final StockMovement movement;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final isCreated = movement.type == 'CREATED';
    final isIn = movement.type == 'IN';
    final color = isCreated
        ? const Color(0xFF7C9CFF)
        : isIn
            ? _green
            : const Color(0xFFFFB454);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCreated
                ? Icons.add_box_outlined
                : isIn
                    ? Icons.south_west
                    : Icons.north_east,
            color: color,
            size: 17,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movement.productName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                '${isCreated ? 'Product added · ' : ''}${showDate ? DateFormat('MMM d, yyyy · h:mm a').format(movement.date) : DateFormat('MMM d · h:mm a').format(movement.date)}${movement.note.isEmpty ? '' : ' · ${movement.note}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isCreated
              ? '+${movement.quantity} opening'
              : '${isIn ? '+' : '-'}${movement.quantity}',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.store});
  final InventoryStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final stockIn = store.movements
              .where((movement) => movement.type == 'IN')
              .fold(0, (total, movement) => total + movement.quantity);
          final stockOut = store.movements
              .where((movement) => movement.type == 'OUT')
              .fold(0, (total, movement) => total + movement.quantity);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 650 ? 3 : 1;
                  final width =
                      (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: width,
                        child: _MetricCard(
                          metric: _Metric(
                            'Inventory value',
                            money(store.inventoryValue),
                            Icons.payments_outlined,
                            const Color(0xFFCB8CFF),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _MetricCard(
                          metric: _Metric(
                            'Units received',
                            '$stockIn',
                            Icons.south_west,
                            _green,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _MetricCard(
                          metric: _Metric(
                            'Units dispatched',
                            '$stockOut',
                            Icons.north_east,
                            const Color(0xFFFFB454),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeading('Stock by category'),
                    if (store.categories.isEmpty)
                      const _EmptyState(
                        'No data yet',
                        'Add products to generate a report.',
                      )
                    else
                      ...store.categories.map((category) {
                        final products = store.products
                            .where((p) => p.category == category)
                            .toList();
                        final units = products.fold(
                          0,
                          (total, p) => total + p.quantity,
                        );
                        final value = products.fold(
                          0.0,
                          (total, p) => total + p.quantity * p.cost,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${products.length} products · $units units',
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                money(value),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeading('Product valuation'),
                    if (store.products.isEmpty)
                      const _EmptyState(
                        'No products yet',
                        'Add products to see their stock values.',
                      )
                    else
                      ...store.products.map(
                        (product) => Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${product.quantity} × ${money(product.cost)}',
                                style: const TextStyle(
                                    color: _muted, fontSize: 12),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                money(product.quantity * product.cost),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      );
}
