# NotchMissionControl

The easiest Mission Control trigger for your MacBook notch: throw your pointer at the top center and let Mission Control pop open, because three fingers deserve a break!

노치에 마우스만 툭 던지면 Mission Control이 바로 열립니다. 세 손가락은 이제 연차 쓰세요!

NotchMissionControl is a tiny macOS menu bar app that turns the real MacBook notch, plus the top-center area of external displays, into an invisible Mission Control hot zone.

## Features

- Trigger Mission Control by moving the pointer into the top-center notch zone.
- Keep the normal three-finger trackpad gesture unchanged.
- Use the real MacBook notch gap when available.
- Use an invisible virtual notch zone on external displays.
- Suppress repeat triggers while Mission Control is already active.
- Tune display scope, hit zone size, cooldown, and trigger method from the menu bar.

## Install

Download `NotchMissionControl-1.0.0.zip` from the `v1.0.0` release, unzip it, and open `NotchMissionControl.app`.

For launch at login, add the app in macOS:

`System Settings` -> `General` -> `Login Items & Extensions` -> `Open at Login`

## Build From Source

```sh
swift build
swift run NotchMissionControl
```

## Build A Local App Bundle

```sh
./scripts/build-app.sh
open dist/NotchMissionControl.app
```

The script creates and ad-hoc signs a local app bundle at `dist/NotchMissionControl.app`.

## Notes

- NotchMissionControl opens `/System/Applications/Mission Control.app` first.
- The keyboard shortcut fallback may require macOS Accessibility permission.
- Mission Control active-state detection uses Dock-owned overlay windows because macOS does not expose a public Mission Control state API.
