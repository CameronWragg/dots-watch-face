#!/usr/bin/env bash
set -euo pipefail

CIQ_DIR="$HOME/.Garmin/ConnectIQ"
KEY_DIR="$HOME/.Garmin"
mkdir -p "$CIQ_DIR"

# Point the Monkey C extension at the baked-in SDK, unless the SDK Manager has
# already selected another SDK that still exists.
CFG="$CIQ_DIR/current-sdk.cfg"
if [[ ! -f "$CFG" || ! -d "$(cat "$CFG")" ]]; then
    echo -n "$CIQ_HOME" > "$CFG"
    echo "Set current SDK to $CIQ_HOME"
fi

# Developer key used to sign builds. Lives outside the repo (in the bind-mounted
# ~/.Garmin) because losing it means you can't publish updates to the store.
if [[ ! -f "$KEY_DIR/developer_key.der" ]]; then
    openssl genrsa -out "$KEY_DIR/developer_key.pem" 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in "$KEY_DIR/developer_key.pem" -out "$KEY_DIR/developer_key.der" -nocrypt
    chmod 600 "$KEY_DIR/developer_key.pem" "$KEY_DIR/developer_key.der"
    echo "Generated developer key at $KEY_DIR/developer_key.der"
fi

if [[ ! -d "$CIQ_DIR/Devices" ]] || [[ -z "$(ls -A "$CIQ_DIR/Devices" 2>/dev/null)" ]]; then
    echo
    echo "No device definitions found. Run 'ciq-sdkmanager', sign in with your"
    echo "Garmin account, and download the devices you want to target."
fi

monkeyc --version
