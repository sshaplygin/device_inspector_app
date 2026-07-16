# DeviceInspector

A Flutter app for Android and iOS that inspects the device it runs on and
shows a live report of its trust signals:

- **VPN Active** — from `connectivity_plus`, plus a tunnel-interface check
  (`tun*`/`ppp*` on Android; on iOS only tunnel interfaces carrying a
  routable address count, since system `utun` interfaces are always present)
- **Jailbreak / Root Access** — via `safe_device`
- **Real Device vs Emulator** — via `safe_device`
- **Real vs Mock Location** — via `geolocator` (`Position.isMocked`) when
  location permission is granted, falling back to `safe_device`
- **Dev Mode / ADB** — via `safe_device`
- **Network interfaces** — the device's active interface list

Checks re-run automatically on connectivity changes and every 15 seconds
while the app is in the foreground; polling pauses in the background.

The UI is platform-adaptive: Cupertino on iOS, Material 3 on Android.

## Permissions

Location (while in use) is requested once at startup and used only to read
the mock-location flag of a position fix. Nothing is stored or sent
anywhere — all checks run on-device.

## Running

```sh
flutter pub get
flutter run
```

## Testing

```sh
flutter analyze
flutter test
```

## Caveats

All signals are client-side heuristics; a determined user can spoof them.
This app is an inspector UI — don't build server-side trust decisions on
its output alone.
