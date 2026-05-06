#!/bin/bash
# Run Flutter app in PROD environment
# Usage: ./scripts/run_prod.sh [extra_flutter_args]
set -e

cd "$(dirname "$0")/.."

echo "🚀 Running Flutter in PROD mode..."
flutter run --dart-define=ENV=prod "$@"

