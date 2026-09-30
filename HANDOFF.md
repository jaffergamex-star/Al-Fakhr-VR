> OUTDATED (2026-09-25): superseded by `CLAUDE.md` in this folder and `Deploy/dev-notes/moi-vr-project-log.md`. Kept only for history.

# MOI "The Promise of Safety" — project handoff brief

Paste this into any new chat / give it to any new developer. Everything below is current as of 2026-09-25.

## What this is
A **VR kiosk app for a museum** (UAE Ministry of Interior museum, Abu Dhabi; agency: Al Fakhr; built by GameX).
Headset: **HTC VIVE Focus Vision** (standalone Android, OpenXR). Engine: **Unity 6000.1.4f1**, URP.
Project folder: `VR/` (Unity project). Key folder: `Assets/MOI/` (all our code, data, README).

## The experience, exactly
1. Visitor puts on the headset and stands in a **virtual museum lobby**: dark circular room, curved blue LED wall
   with the Abu Dhabi skyline, a glowing crystal in a glass tube on a podium, warm light strips.
2. A **START** button floats in front of the podium. Press it by pointing a controller and pulling the trigger,
   by looking at it for 2 seconds, or with A/X.
3. The lobby fades to black and a **360° video ("the film"), 3 minutes long, single language,** plays all around
   the visitor with its own soundtrack. No interaction during the film.
4. At the end it fades back to the lobby and waits for the next visitor. Loop forever.
5. **Hidden staff reset:** hold the left Menu button (or squeeze both grips) 2 s -> back to START from anywhere,
   including mid-film; hold 6 s -> full app reload. A single tap does nothing (so visitors can't trigger it).

The film itself is being produced elsewhere (from the 26-page storyboard deck "UAE MINISTRY OF INTERIOR -
MUSEUM VR EXPERIENCE.pdf": 18 beats, museum -> memories -> Abu Dhabi 2076 -> Qasr Al Hosn -> museum).
**It does not exist yet.** A dummy 3-minute 360 test film (`Assets/StreamingAssets/MOI_TestJourney360.mp4`,
storyboard frames + orientation markers + a beep per beat) is bundled in the APK so the loop can be tested.

## Hard requirements from the client/producer
- Runs standalone on the Focus Vision, no PC.
- The film must be **loadable from outside the app, over the museum LAN, from a CMS/content server**, so it can
  be replaced without rebuilding. Exact CMS details still to come from the producer.
- One language only.
- Format of the film (mono/stereo 360, resolution) is not decided; the app must not need a rebuild to change it.

## What is built (all verified in the Unity editor; NOTHING verified on a real headset yet)
- Lobby scene, START button with laser pointer + gaze press, crystal, museum blockout.
- 360 video playback with fades; front of the film lands straight ahead (a +90° yaw correction is applied because
  Unity's Skybox/Panoramic puts the equirect centre at +X — don't remove `EnvironmentManager.FrontIsForward`).
- **ContentManager**: reads `manifest.json` from a LAN URL, downloads the film it names to the headset, verifies
  size/SHA-256, plays the **local copy** (never streams); re-checks every 10 min while idle; if the server is
  down the cached film keeps playing. Manifest: `{ "version", "layout": "Mono360|TopBottom360|SideBySide360|FlatScreen",
  "yaw", "video": { "url", "bytes", "sha256" } }`. Sample server + docs in `ContentServer/`
  (`python -m http.server 8765`). Server URL: `contentManifestUrl` on `Assets/MOI/Data/PromiseOfSafety.asset`,
  overridable per headset in `Android/data/com.gamex.moi.promiseofsafety/files/moi-config.json`.
- Priority when START is pressed: film from server -> bundled film (`masterVideoPath` on the sequence asset)
  -> real-time storyboard beats (a review/fallback mode, not the product).
- Hidden operator reset (above).
- Android build works: `Builds/MOI_PromiseOfSafety.apk` (~81 MB, includes the dummy film).
- Editor tooling under the **MOI** menu: 1 Configure Project (Android + Windows OpenXR, VIVE features),
  2 Build Experience Scene (regenerates the scene from code — the scene is generated, edit code not the scene),
  3 Build APK / 3b Build APK and Run, Review > Capture Stills, Review > Encode 360 Test Film.

## Gotchas already hit (don't re-discover)
- The VIVE OpenXR plugin (`Packages/com.htc.upm.vive.openxr`, v2.5.1) **must stay embedded in Packages/** with
  its real binaries. Added as a Unity git URL its `.aar/.so` files come as 135-byte Git LFS pointers: the editor
  compiles, but the Android build fails with `openxr_loader.aar: zip END header not found`. When copying the
  project to another PC, copy `Assets`, `Packages` (incl. that folder), `ProjectSettings`. `Library/Temp/Logs`
  are not needed.
- StreamingAssets on Android live inside the APK; Unity's VideoPlayer reads them in place because the file is
  stored uncompressed. If a device refuses, the app extracts the film to storage once and plays that copy.
- Windows Play mode -> headset (SteamVR-style) works via **VIVE Streaming Hub + SteamVR set as the active OpenXR
  runtime**; run MOI > 1 Configure once so OpenXR is enabled on the Windows tab. Good for layout iteration only;
  the APK on the headset is the real test (video decode, performance).
- Deck inconsistencies to raise with the client: 2076 vs 2077; "The Last Light" timing (used 00:15–00:22);
  "Safer Journeys" beat has duplicated copy/no VO; wrong flag patches in the "Human-Led Protection" frame.

## Open / next steps, in order
1. **First run on the Focus Vision** (adb install the APK, or MOI > 3b). Check: START press, 360 decode &
   orientation, hold-to-reset, height/scale of the room.
2. Producer's CMS/loading details -> adapt `ContentManager` (URL, auth, HTTPS?).
3. Real film at production resolution on device. Built-in player: H.264/H.265 MP4, AAC, 30 fps, up to
   4096x2048 mono / 4096x4096 top-bottom. 5.7K/8K needs a plugin (AVPro).
4. Kiosk lockdown on the headset (auto-launch, hide system UI, no boundary prompts, no sleep) — HTC device
   settings, not Unity code.
5. On-screen text is English; if the single language is Arabic, title/START need an Arabic font + RTL shaping.
6. Museum art pass (real room dimensions, real LED-wall media, crystal look).
7. Release cleanup: remove dummy film from StreamingAssets, final package name/icon, soak test 50+ plays.

Full details: `Assets/MOI/README.md` and `ContentServer/README.md`.
