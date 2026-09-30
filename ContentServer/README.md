# Content server for the MOI headset app

The headset never has the film baked in. It reads `manifest.json` from a web server on the museum LAN,
downloads the film it names, keeps it on the headset, and plays that local copy. If the server is off,
the last downloaded film keeps playing.

## Try it on this PC

    cd ContentServer
    python -m http.server 8765

Then point the app at `http://<this-PC-ip>:8765/manifest.json` (see below). Any web server, NAS or CMS that
can serve two static files works the same way; a CMS only has to output this JSON at a fixed URL.

## manifest.json

| field | meaning |
|---|---|
| `version` | free text, shown small on the idle screen so staff can see what a headset holds |
| `layout` | `Mono360`, `TopBottom360` (stereo, left eye on top), `SideBySide360`, or `FlatScreen` |
| `yaw` | degrees to turn the film if its "front" is not the centre of the frame |
| `video` | the film: `url` (absolute, or relative to the manifest), optional `bytes` and `sha256` checks |

To publish a new film: upload it under a **new file name**, then update `manifest.json`. Headsets check every
10 minutes while idle (never during a visit), download, verify, and switch over. Changing only `layout` or
`yaw` takes effect without a download.

## Telling a headset where the server is

1. Default for new installs: `Content Manifest Url` on `Assets/MOI/Data/PromiseOfSafety.asset`, before building the APK.
2. Per headset, no rebuild: edit `manifestUrl` in
   `Android/data/com.gamex.moi.promiseofsafety/files/moi-config.json` (created on first launch), over USB.

Film spec for Focus Vision with the built-in player: MP4, H.264/H.265, AAC, 30 fps, up to 4096x2048 mono or
4096x4096 top-bottom. Budget about 1 GB at 50 Mbps.
