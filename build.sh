#!/bin/sh
# Build DinoDiner.pdx with the official Playdate SDK compiler.
set -e
cd "$(dirname "$0")"
if ! command -v pdc >/dev/null 2>&1; then
    if [ -n "$PLAYDATE_SDK_PATH" ]; then
        PATH="$PLAYDATE_SDK_PATH/bin:$PATH"
    else
        echo "pdc not found: install the Playdate SDK and set PLAYDATE_SDK_PATH" >&2
        exit 1
    fi
fi
pdc source DinoDiner.pdx
echo "Built DinoDiner.pdx"
