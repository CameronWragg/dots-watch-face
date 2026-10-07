# Ubuntu 22.04 is required: the Connect IQ simulator and SDK Manager link
# against libwebkit2gtk-4.0 / libsoup-2.4 / libjpeg8, which newer releases dropped.
FROM mcr.microsoft.com/devcontainers/base:jammy

# Pinned SDK. Versions and filenames: https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json
ARG CIQ_SDK_VERSION=9.2.0
ARG CIQ_SDK_FILE=connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip
ARG CIQ_DOWNLOADS=https://developer.garmin.com/downloads/connect-iq

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        # Compiler toolchain (monkeyc, monkeydo, etc. are Java)
        openjdk-17-jdk-headless \
        # Simulator + SDK Manager runtime libraries
        libgtk-3-0 \
        libwebkit2gtk-4.0-37 \
        libjavascriptcoregtk-4.0-18 \
        libsoup2.4-1 \
        libjpeg-turbo8 \
        libpng16-16 \
        libusb-1.0-0 \
        libudev1 \
        libsecret-1-0 \
        libcurl4 \
        libxxf86vm1 \
        libsm6 \
        libxkbcommon0 \
        libcanberra-gtk3-module \
        libgl1 \
        # SDK Manager stores its Garmin login via libsecret, which needs a keyring
        gnome-keyring \
        dbus-x11 \
        # Misc tooling
        fonts-dejavu-core \
        librsvg2-common \
        shared-mime-info \
        openssl \
        unzip \
        xauth \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Connect IQ SDK (compiler, simulator, docs, samples)
RUN curl -fsSL -o /tmp/sdk.zip "${CIQ_DOWNLOADS}/sdks/${CIQ_SDK_FILE}" \
    && mkdir -p /opt/connectiq-sdk \
    && unzip -q /tmp/sdk.zip -d /opt/connectiq-sdk \
    && rm /tmp/sdk.zip \
    && chmod +x /opt/connectiq-sdk/bin/* \
    && test "$(cat /opt/connectiq-sdk/bin/version.txt)" = "${CIQ_SDK_VERSION}" \
    # monkeyc writes default.jungle into its own bin/, so the SDK must be writable by the dev user
    && chown -R vscode:vscode /opt/connectiq-sdk

# SDK Manager (GUI) - needed to sign in to Garmin and download device definitions
RUN curl -fsSL -o /tmp/sdkmanager.zip "${CIQ_DOWNLOADS}/sdk-manager/connectiq-sdk-manager-linux.zip" \
    && mkdir -p /opt/connectiq-sdk-manager \
    && unzip -q /tmp/sdkmanager.zip -d /opt/connectiq-sdk-manager \
    && rm /tmp/sdkmanager.zip \
    && chmod +x /opt/connectiq-sdk-manager/bin/sdkmanager

COPY ciq-sdkmanager /usr/local/bin/ciq-sdkmanager

ENV CIQ_HOME=/opt/connectiq-sdk \
    PATH=/opt/connectiq-sdk/bin:${PATH} \
    # Avoid blank/garbled WebKit windows when there's no GPU passthrough
    WEBKIT_DISABLE_COMPOSITING_MODE=1 \
    NO_AT_BRIDGE=1
