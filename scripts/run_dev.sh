#!/bin/bash
# Run Flutter app in DEV environment
# Usage: ./scripts/run_dev.sh [extra_flutter_args]
set -e

cd "$(dirname "$0")/.."

echo "🚀 Running Flutter in DEV mode..."
flutter run --dart-define=ENV=dev "$@" --web-browser-flag=--disable-web-security, --web-browser-flag=--disable-features=IsolateOrigins,site-per-process, --web-browser-flag=--disable-site-isolation-trials