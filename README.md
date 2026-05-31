# ULOS - Aplikasi Pelacakan Lokasi Petugas SE BPS Kab/kota Seprovinsi Sumatera Utara

[![Flutter](https://flutter.dev/images/flutter-logo-sharing.png)](https://flutter.dev)

ULOS adalah aplikasi mobile Flutter untuk pelacakan lokasi real-time yang dikembangkan untuk Badan Pusat Statistik (BPS) Indonesia. Aplikasi ini mendukung tracking GPS di latar belakang, visualisasi peta dengan clustering marker, penyimpanan lokal dengan sinkronisasi otomatis ke backend API, serta riwayat tracking.

## Fitur Utama
- **Pelacakan GPS Real-time**: Foreground & background location dengan akurasi tinggi (~30m threshold).
- **Peta Interaktif**: FlutterMap dengan marker clustering untuk visualisasi rute/lokasi.
- **Offline Support**: Penyimpanan lokal SQLite + auto-sync saat online.
- **Multi-Environment**: Dev/Prod switching via `ENV=dev/prod`.
- **Dashboard**: Home, Tracking, History, Profile, Login/Register.
- **Backend Integration**: Sinkronisasi dengan Tracking API (Go backend).
- **Multiplatform**: Android, iOS, Web (dev only).

## Tech Stack

| Kategori | Teknologi |
|----------|-----------|
| **Framework** | Flutter 3.x (Dart SDK ^3.11.4), Material Design |
| **State Management** | Flutter BLoC 9.0 + Equatable |
| **HTTP Client** | Dio 5.7 |
| **Location/GPS** | Geolocator 12.0 (foreground/background/permissions) |
| **Maps** | Flutter Map 7.0.2 + Marker Cluster 1.4.0 + LatLong2 |
| **Local DB** | Sqflite 2.3 + Path Provider |
| **Environment** | Flutter Dotenv 5.2 + Crypto |
| **UI/UX** | Shimmer, Flutter Animate 4.5, Intl |
| **Utilities** | Shared Preferences 2.3, Logger 2.5 |
| **Build Tools** | Flutter Launcher Icons |

## Requirements

### Sistem
- **Flutter SDK**: ^3.11.4+ (`flutter doctor` untuk verifikasi).
- **Dart SDK**: ^3.11.4 (termasuk dalam Flutter).


### Dependencies
```
flutter pub get
```


## Environment Configuration

Dukungan otomatis switching **Development** (`dev`) ↔ **Production** (`prod`).

### File Konfigurasi
| File | Tujuan |
|------|--------|
| Dev config (edit `baseUrl`) |
| `.env.dev` / `.env.prod` | Override via flutter_dotenv (optional) |

## env.dev 
BASE_URL=https://trackingapi.bps.web.id

# Background Location Service Configuration
DISTANCE_FILTER_METERS=30 (Minimal radius pergerakan dari titik lokasi sebelumnya)
LOCATION_INTERVAL_SECONDS=10
FLUSH_INTERVAL_SECONDS=60
SYNC_INTERVAL_SECONDS=300
BATCH_LIMIT=100


## Cara Menjalankan (Local Development)

### 1. Setup
```bash
cd ulos
flutter pub get
flutter pub run flutter_launcher_icons  # Generate icons (opsional)
```

### 2. Run dengan Shell Scripts (Recommended)
```bash
# Dev mode
./scripts/run_dev.sh

# Prod mode
./scripts/run_prod.sh 

# Dengan device spesifik
./scripts/run_dev.sh -d emulator-5554
```

### 4. CLI Manual
```bash
# Dev
flutter run --dart-define=ENV=dev

# Prod (default)
flutter run --dart-define=ENV=prod
```


## Building untuk Release

### APK (Debug/Release)
```bash
# Debug APK
flutter build apk --debug

# Release APK (universal)
flutter build apk --release

# Split per ABI (lebih kecil)
flutter build apk --split-per-abi --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk` (dari `build.gradle.kts`: `ulos_{version}.apk`).

### App Bundle (untuk Play Store)
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`.

**Signing**: Saat ini debug keys. Lihat [Play Store](#deploy-ke-play-store).

## Deploy ke Play Store

### 1. Setup Keystore (Upload Key)
```bash
# Generate upload keystore (simpan aman!)
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

# Atau Android Studio: Build > Generate Signed Bundle/APK
```

### 2. Konfigurasi Signing (android/key.properties)
Buat `android/key.properties`:
```
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=/path/to/upload-keystore.jks
```

Update `android/app/build.gradle.kts`:
```kotlin
// Tambah di sebelum android {}
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

### 3. Build Signed AAB
```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

### 4. Upload ke Play Console
- Login [Google Play Console](https://play.google.com/console).
- Buat app baru / track baru (Internal/Closed/Production).
- **Release > Production** → Upload `app-release.aab`.
- Review notes, images, store listing.
- **Rollout** → Review & Release.

**Pro Tips**:
- Version bump di `pubspec.yaml` (`version: 1.0.0+2` → code+build).
- Test signed APK/AAB di emulator/device.
- App ID: `com.bps.ulos` (ubah di `android/app/build.gradle.kts` jika perlu).

## Troubleshooting
- **GPS Permissions**: Android 13+ → `geolocator` auto-handle.
- **Background Location**: Tambah `<uses-permission android:name=\"android.permission.FOREGROUND_SERVICE\" />` di manifest.
- **Web CORS**: Gunakan Chrome no-CORS config.
- **DB Init**: Non-web only (main.dart).

## Kontribusi
1. Fork & clone.
2. `flutter pub get`.
3. Buat branch `feat/xxx`.
4. PR ke `main`.

## Lisensi
[MIT License](LICENSE) (atau sesuaikan).

---

*Terakhir diupdate: $(date)*