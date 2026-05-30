#!/usr/bin/env bash
set -euo pipefail

# Initialize rbenv so the correct Ruby version is used in non-interactive shells
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
if command -v rbenv &>/dev/null; then
  eval "$(rbenv init - bash)"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.screenshots"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found."
  echo "Copy .env.screenshots.example and fill in your credentials."

  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
export SCREENSHOT_SERVER_URL SCREENSHOT_USERNAME SCREENSHOT_PASSWORD

DEVICES=(
  "iPhone 17 Pro Max"
  "iPhone 17"
  "iPad Pro 11-inch (M5)"
  "iPhone Air"
)

cd "$REPO_ROOT"

SCREENSHOTS_DIR="$REPO_ROOT/fastlane/screenshots"

echo "Clearing previous screenshots..."
rm -rf "$SCREENSHOTS_DIR"

for device in "${DEVICES[@]}"; do
  echo ""
  echo "==> Capturing screenshots for: $device"
  SNAPSHOT_DEVICE="$device" bundle exec fastlane screenshots
done
# echo ""
# echo "Screenshots saved to: $SCREENSHOTS_DIR"
# open "$SCREENSHOTS_DIR"

echo ""
read -rp "Upload screenshots to App Store Connect? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  if [[ -z "${ASC_API_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_API_KEY:-}" ]]; then
    echo "Error: ASC_API_ID, ASC_ISSUER_ID, and ASC_API_KEY must be set in $ENV_FILE to upload."
    exit 1
  fi
  export ASC_API_ID ASC_ISSUER_ID ASC_API_KEY
  echo ""
  bundle exec fastlane upload_screenshots
  echo ""
  echo "Screenshots uploaded to App Store Connect."
else
  echo "Skipped upload."
fi
