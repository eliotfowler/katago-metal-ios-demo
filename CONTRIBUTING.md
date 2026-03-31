# Contributing

Bug reports and pull requests are welcome.

## Before you start

- **Test on a physical device for actual performance.** Metal does not work in the simulator on Intel-based macs and leverages the host mac on Apple Silicon macs. Any change to the engine or bridge must be verified on real hardware.
- **KataGoEngine/ is generated — do not edit it directly.** All C++ and Swift files under `KataGoEngine/` are copied from the `katago/` submodule by `scripts/copy_katago_files.sh`. Changes made directly there will be overwritten. If you need to modify KataGo source, fork the submodule.
- **Run `./scripts/setup.sh` after pulling.** If the submodule has been updated, re-running setup will refresh `KataGoEngine/` and re-download any missing weights.
- **Set your own signing values in Xcode before building on device.** Select your Apple Developer Team and a unique bundle identifier in the app target's Signing & Capabilities settings.

## Issues

Please include:

- Device model and iOS version
- Xcode version
- Which neural net model you were using
- The full error message or log output from the app's log panel

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your change and verify it builds and runs on a physical device.
3. Open a PR with a description of what changed and why.

## What's out of scope

- Changes to `KataGoEngine/` directly (modify the `katago` submodule instead)
- Support for the iOS simulator (Metal limitation)
- Windows or Android ports
