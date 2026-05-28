#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$(dirname "$0")/../.env.screenshots"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found. Copy .env.screenshots.example and fill in your credentials."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
export SCREENSHOT_SERVER_URL SCREENSHOT_USERNAME SCREENSHOT_PASSWORD

DEVICES=(
  "iPhone 17 Pro Max"
  "iPhone 17"
  "iPad Pro 11-inch (M5)"
)

for device in "${DEVICES[@]}"; do
  echo ""
  echo "==> Capturing screenshots for: $device"
  SNAPSHOT_DEVICE="$device" bundle exec fastlane screenshots
done

echo ""
echo "Done. Screenshots saved to fastlane/screenshots/"
