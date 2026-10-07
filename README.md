# dots-watch-face
A watch face made for Garmin devices formed with lots of little circles.

## Development

Open the repo in the dev container (VS Code: *Dev Containers: Reopen in Container*). It ships with
the Connect IQ SDK, Java 17, the SDK Manager and the Monkey C extension.

On first use:

1. Run `ciq-sdkmanager` in the container terminal, sign in with your Garmin account and download
   the device definitions you want to target. (Garmin requires a login for these, so they can't be
   baked into the image.)
2. A developer signing key is generated at `~/.Garmin/developer_key.der` automatically. Back it up:
   you need the same key to publish updates to the Connect IQ Store.

`~/.Garmin` is bind-mounted from the host, so devices, login and the key survive container rebuilds.
The simulator and SDK Manager display through the host's X11 socket (`/tmp/.X11-unix`), which also
works under Wayland via XWayland.
