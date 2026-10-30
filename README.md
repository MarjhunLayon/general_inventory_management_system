# General Inventory Management System

A responsive Flutter inventory-management app inspired by the supplied dark dashboard screenshots. It uses a charcoal/navy theme with green accents and supports phones, tablets, and desktop layouts.

## Bug fixes in this version

- **Product search:** searches product name, SKU/barcode, category, supplier, and description. Search is case-insensitive, ignores extra spaces, supports multiple search words, and includes a clear-search button.
- **Clear filters:** when search, category, or stock-status filters hide a product, use **Clear filters** to reset them.
- **Product creation in History:** adding a product now creates a `Product added` history event, including when the opening quantity is zero.
- **Quantity edits in History:** changing a product's quantity in the edit form records a stock-in or stock-out adjustment event.
- **Existing data:** your saved products and movements remain compatible with the existing `products_v1` and `movements_v1` local storage keys. The app does not erase your current inventory when updated.

> History cannot recreate events from before this fix. Existing products will become visible in History when you add or edit them, or record a stock movement from now on.

## Features

- **Dashboard:** total products, total stock units, low-stock count, out-of-stock count, inventory cost value, category summary, alerts, and recent stock activity.
- **Product management:** add, view, edit, and delete products with name, SKU/barcode text, category, quantity, minimum stock, cost price, selling price, supplier, and description.
- **Categories:** automatically groups products by the category assigned to each item.
- **Stock control:** record stock-in and stock-out movements, update quantities automatically, prevent stock from going negative, and attach optional notes.
- **Alerts:** identifies low-stock and out-of-stock products using each product's minimum stock setting.
- **Search and filters:** search by product name, SKU, category, supplier, or description; filter by category and stock status; sort by name or stock quantity.
- **History:** chronological log of product creation, quantity adjustments, stock-in, and stock-out events.
- **Reports:** inventory value, stock-in/out totals, stock by category, and per-product stock values.
- **Responsive UI:** bottom navigation and product cards on smaller screens; navigation rail and product table on larger screens.
- **Local persistence:** products and history are saved on the device using `shared_preferences`.

## Requirements

- Flutter SDK (stable; Dart 3.3 or newer)
- Android Studio or VS Code with Flutter and Dart extensions
- Android SDK for Android builds, or the relevant desktop toolchain for desktop builds

## Install and run in VS Code

1. Download and extract the project ZIP.
2. In VS Code, select **File → Open Folder** and open `general_inventory_management`.
3. Open **Terminal → New Terminal** in VS Code.
4. Run:

   ```bash
   flutter pub get
   ```

5. Connect your Android phone with USB debugging enabled, or start an Android emulator.
6. Check that Flutter detects the device:

   ```bash
   flutter devices
   ```

7. Run the app:

   ```bash
   flutter run
   ```

If the Android/Windows/web platform folders do not exist in your copy, run `flutter create .` once from the project root, then run `flutter pub get` and `flutter run` again. Keep the existing `lib/main.dart`, `pubspec.yaml`, and `README.md` when prompted.

## If you are updating an existing VS Code project

You do **not** paste the README text into `main.dart`. Replace the source file instead:

1. Open your Flutter project folder in VS Code.
2. Open `lib/main.dart`.
3. Replace its contents with the complete `main.dart` included in this ZIP (or download the `main.dart` file linked with this README).
4. Make sure your root `pubspec.yaml` includes the dependencies shown in the ZIP's `pubspec.yaml`.
5. Save the files and run:

   ```bash
   flutter pub get
   flutter run
   ```

Your existing locally saved product data should remain because this update keeps the same SharedPreferences storage keys. Back up important data before replacing an app that is already in use.

## Build an Android APK

```bash
flutter build apk --release
```

The APK will be created at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Project structure

```text
general_inventory_management/
├── lib/
│   └── main.dart
├── pubspec.yaml
├── analysis_options.yaml
├── .gitignore
└── README.md
```

## Data model

### Product

| Field | Purpose |
|---|---|
| id | Unique local identifier |
| name | Product name |
| sku | SKU or barcode value |
| category | Product category |
| quantity | Current available quantity |
| minStock | Low-stock threshold |
| cost | Unit cost |
| price | Selling price |
| supplier | Optional supplier name |
| description | Optional product description |

### History event

| Field | Purpose |
|---|---|
| id | Unique event identifier |
| productId | Related product ID |
| productName | Product name snapshot |
| type | `CREATED`, `IN`, or `OUT` |
| quantity | Opening quantity or units moved |
| date | Event date and time |
| note | Optional note/reference |

## Important implementation notes

- This is a local-first starter app. It is not connected to a cloud backend and does not synchronize between devices or users.
- Data is stored locally on the device. Uninstalling the app or clearing its app data may remove locally stored inventory.
- The SKU field accepts barcode values, but camera-based barcode scanning is not implemented.
- Product image upload and cloud image hosting are not implemented.
- Reports are calculated from locally stored product and movement records. PDF/Excel export, user authentication, role permissions, audit-log protection, and cloud backup are recommended for production use.
- Currency formatting uses Philippine pesos (`₱`) and the `en_PH` locale. Update `money()` in `lib/main.dart` if another currency is required.

## License

Use and modify this project for coursework or an internal prototype. Add an appropriate license before distributing it commercially.
