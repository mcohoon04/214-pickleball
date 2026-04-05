#!/bin/bash
# 214 Pickle — App Store Screenshot Helper
#
# Usage:
#   1. Build and run the app on each simulator first (via Xcode)
#   2. Navigate to the screen you want to capture
#   3. Run: ./scripts/take-screenshots.sh <screen-name>
#
# This captures screenshots from all booted simulators at once.

set -e

SCREEN_NAME="${1:-screenshot}"
OUTPUT_DIR="screenshots"
mkdir -p "$OUTPUT_DIR"

echo "Capturing screenshots for: $SCREEN_NAME"
echo "Make sure the app is showing the correct screen on all simulators!"
echo ""

# Get all booted simulators
BOOTED=$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['state'] == 'Booted':
            print(f\"{d['udid']}|{d['name']}\")
")

if [ -z "$BOOTED" ]; then
    echo "No booted simulators found!"
    echo ""
    echo "Boot the required simulators first:"
    echo "  xcrun simctl boot 'iPhone 16 Pro Max'"
    echo "  xcrun simctl boot 'iPhone 16 Pro'"
    echo ""
    echo "Then build & run the app on each."
    exit 1
fi

while IFS='|' read -r UDID NAME; do
    SAFE_NAME=$(echo "$NAME" | tr ' ' '-')
    FILENAME="${OUTPUT_DIR}/${SCREEN_NAME}_${SAFE_NAME}.png"
    xcrun simctl io "$UDID" screenshot "$FILENAME"
    echo "  Saved: $FILENAME ($NAME)"
done <<< "$BOOTED"

echo ""
echo "Done! Screenshots in ./$OUTPUT_DIR/"
echo ""
echo "Recommended capture order:"
echo "  1. ./scripts/take-screenshots.sh 01-login"
echo "  2. ./scripts/take-screenshots.sh 02-calendar"
echo "  3. ./scripts/take-screenshots.sh 03-schedule"
echo "  4. ./scripts/take-screenshots.sh 04-booking-create"
echo "  5. ./scripts/take-screenshots.sh 05-booking-detail"
