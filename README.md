# TPMS Libre

Tyre pressure and temperature from Bluetooth TPMS sensors — offline, with no
account and no network access.

The sensors broadcast their readings in the clear. The manufacturer's app asks
you to sign in, wants your photos and your crash logs, and talks to a server,
for numbers that never needed to leave your phone. This app just listens.

## Supported sensors

- **JK Tyre Treel** TPMS sensors — the ones sold for cars and two-wheelers with
  the *SMART TYRE CAR & BIKE* / *Treel Care* apps.

Other BLE sensors are welcome: see [How it works](#how-it-works) for what a
decoder needs to provide.

## What it does

- Pressure (psi) and temperature (°C) for every wheel, live
- Cars with or without a spare, and motorcycles; several vehicles at once
- Separate front and rear targets, with deliberately lopsided tolerances —
  losing pressure is what ruins tyres, while heat alone adds a few psi on a
  drive, so the upper bound is loose
- Assign sensors to wheels and swap them after a rotation
- A photo of your own vehicle on the home screen
- A haptic tap the first time each tyre reports after you open the app

## Privacy

**Release builds have no `INTERNET` permission**, so the app cannot send
anything anywhere — not as a promise, but because Android will not let it.
You can check any APK yourself:

```
aapt2 dump permissions app-release.apk
```

The permissions it does have, and why:

- **Bluetooth scan** — to hear the sensors. The app never connects to
  anything; the sensors cannot be connected to.
- **Location** — not used, never read. Android strips iBeacon data from the
  scan results of any app that declares it is not using Bluetooth for
  location, silently and with no error, and these sensors put their readings
  inside an iBeacon frame. So the permission has to be granted, and location
  has to be on when the scan starts, purely so the readings arrive.
- **None for photos.** Choosing a picture goes through Android's photo
  picker, which hands over the one file you chose and nothing else. The copy
  stays in the app's private storage.

(Debug builds do carry `INTERNET`: Flutter's tooling adds it for hot reload.
Judge the app by a release build.)

## How it works

Each Treel sensor broadcasts a standard iBeacon frame under Apple's
manufacturer id `0x004C`, with a fixed UUID and the readings carried in the
fields a real iBeacon uses for identity:

```
02 15 | ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff e0 | MM MM | mm PP | TT
```

| field | bytes | meaning |
|---|---|---|
| type, length | `02 15` | standard iBeacon |
| UUID | `ff…ffe0` | constant on every sensor; identifies a Treel |
| major | 2 | the 4th and 5th octets of the sensor's MAC |
| minor | 2 | the 6th octet of its MAC, then **pressure in psi** |
| tx power | 1 | **temperature: °C = byte − 110** |

The last three MAC octets travel inside the payload, so they serve as the
sensor's id without needing the Bluetooth address, which phones hide.
Resolution is 1 psi and 1 °C.

Both scales were confirmed against the vendor app on five sensors, and again
independently after a drive: warm a tyre and its pressure has to rise in
proportion to absolute temperature, which it only does if both decodes are
right. Predicted and observed agreed to within 0.2 psi across 27–41 °C.

Sensors broadcast often while the wheel turns and every few minutes when
parked. They also send a second advertisement whose payload is encrypted.
The battery level the vendor app shows is not in the iBeacon frame and cannot
be read over a connection, so it is presumably in there — which is why this
app does not show one.

The decoder is [`lib/treel/reading.dart`](lib/treel/reading.dart). A decoder
for another sensor needs to turn one advertisement into a sensor id, a
pressure and a temperature.

## Building

Flutter 3.47.5 (pinned in `pubspec.yaml`), Android only for now.

```
flutter build apk --release
flutter test
```

Golden-image tests are skipped by default because pixels only match on the
machine that rendered them; see `dart_test.yaml` to run them.

## Screenshots

The listing screenshots are rendered from the app's own widgets by
`test/store_screenshots_test.dart`. The vehicle photos in them are from
[Pexels](https://www.pexels.com/), used under the
[Pexels License](https://www.pexels.com/license/):

- Honda NSX: [*A Red Sports Car*](https://www.pexels.com/photo/a-red-sports-car-17638358/)
  by WAVYVISUALS
- TVS Apache RR310: [*Photo of a Red and Black Big Bike*](https://www.pexels.com/photo/photo-of-a-red-and-black-big-bike-12801272/)
  by Akash A G

They are kept in [`test/screenshot_photos/`](test/screenshot_photos/) so the
screenshots can be rendered again, and are not under the MIT licence. The app
does not ship them. Honda, TVS and their models are trademarks of their
owners, shown only as an owner's photo of their own vehicle would be.

## Not affiliated

JK Tyre and Treel are trademarks of their respective owners. TPMS Libre is an
independent project, not affiliated with, endorsed by or supported by JK Tyre
& Industries or TREEL Mobility Solutions. It reads the radio broadcasts of
sensors you own.

## License

[MIT](LICENSE).
