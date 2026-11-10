# BetterKeyLight

A small macOS menu bar app (macOS 14+) for controlling an Elgato Key Light or Key Light Air over its local HTTP API. No Elgato Control Center required.

## Features

- **Menu bar control** – on/off switch, brightness (3–100 %), color temperature (2900–7000 K) and quick brightness buttons. The light bulb icon is filled while the light is on.
- **Automatic discovery** – finds Key Lights on your network via Bonjour and sets itself up with the first one it sees. If the light later gets a new IP address, the app follows it. A manual address is still possible.
- **Presets** – save combinations of brightness and color temperature and apply them with one click from the menu.
- **Camera coupling** – turns the light on while any app uses the camera and off again afterwards, optionally with a preset. A light that was already on is left alone.
- **Sleep handling** – turns the light off when the Mac sleeps or the screen locks, and optionally back on after waking or unlocking.
- **Smooth fade** – ramps the brightness when switching on or off instead of cutting hard.
- **Schedule** – any number of rules (time, weekdays, on/off, optional brightness), with a "run now" button.
- **Device info** – product, name, serial number, firmware and MAC address in Settings.
- **Launch at login**.

Camera coupling and sleep handling are off by default; enable them under Settings → Automation.

## Build

```bash
./build.sh
```

This produces `build/BetterKeyLight.app`. Drag it to `/Applications` and launch it.
Only the Xcode Command Line Tools are required.

## Notes

- The first time the app talks to the light, macOS may ask for permission to access the local network. Please allow it, otherwise neither discovery nor control will work.
- Camera coupling only checks whether a camera is in use. It never accesses the camera image and needs no camera permission.
- Schedule rules only run while the app is running and the Mac is awake. After waking, rules missed by up to 10 minutes are caught up.
- The light's state is polled every 15 seconds so changes made elsewhere show up in the app.
- The app controls one light at a time.

BetterKeyLight is an independent project and is not affiliated with Elgato or Corsair.
