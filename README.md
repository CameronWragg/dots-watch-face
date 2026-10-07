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

## Building

The face targets the fēnix 8 Solar 47mm only. Build and run it from VS Code (*Monkey C: Run*), or:

```sh
monkeyc -f monkey.jungle -d fenix8solar47mm -o bin/DotRing.prg -y ~/.Garmin/developer_key.der -w -l 3
connectiq &                                   # start the simulator
monkeydo bin/DotRing.prg fenix8solar47mm
```

Unit tests (ring fill, 12 and 24 hour times, weekdays, temperatures):

```sh
monkeyc -f monkey.jungle -d fenix8solar47mm -o bin/test.prg -y ~/.Garmin/developer_key.der --unit-test
monkeydo bin/test.prg fenix8solar47mm -t
```

The dots and icons are one generated bitmap font, so `setColor` can tint them. Edit the icons in
`tools/make_glyphs.py`, then regenerate `resources/fonts/glyphs.{fnt,png}`:

```sh
python3 tools/make_glyphs.py --preview /tmp/icons.png
```
