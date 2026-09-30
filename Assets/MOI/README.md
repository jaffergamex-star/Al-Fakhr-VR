# The Promise of Safety — MOI Museum VR (VIVE Focus)

Three-minute, passive, guided VR journey for the UAE Ministry of Interior museum.
Target: VIVE Focus 3 / Focus Vision / XR Elite via OpenXR + VIVE OpenXR Plugin. Unity 6000.1, URP.

## Getting going

`MOI` menu in the editor:

1. **Configure Project for VIVE Focus** – Android, IL2CPP/ARM64, Vulkan, OpenXR loader, *VIVE XR Support*
   and *VIVE Focus 3 Controller Interaction*, single-pass instanced, mobile URP settings.
2. **Build Experience Scene** – generates `Scenes/PromiseOfSafety.unity` from the storyboard.
3. **Build APK** / **Build APK and Run** – output in `Builds/`.

In Play mode without a headset: click **START** with the mouse (or `Space`), `←/→` previous/next beat,
`Esc` back to idle, hold right mouse to look around.
`MOI > Review > Capture Stills` plays the journey and writes a still per beat into `Review/`.

On the headset the visitor stands in the virtual museum and presses **START** on the kiosk in front of
the crystal: point a controller and pull the trigger, or just look at the button for two seconds (for
visitors who are not holding controllers). A/X also starts. The film is single-language, so there is nothing else to choose.

**Hidden operator reset:** hold the left Menu button, or squeeze both grips, for 2 s -> back to the START
screen from anywhere, mid-film included. Keep holding to 6 s -> full app reload. Backspace (hold) does the
same from a paired Bluetooth keyboard; `Esc` is instant in the editor. A single tap does nothing, on purpose. `Auto Start When Worn` on the director is available for a
fully hands-free kiosk but is off by default.

## Delivering the journey as one video (click START -> film plays)

On `Data/PromiseOfSafety.asset`, under **Single-video delivery**:

- `masterVideo` – a VideoClip imported into the project, **or**
- `masterVideoPath` – a file under `Assets/StreamingAssets/`, an absolute path on the headset
  (`/sdcard/MOI/journey.mp4`), or a URL. Use a path for a big 360 file so the APK stays small.
- `masterVideoLayout` – `FlatScreen` (16:9 on a large curved screen), `Mono360`, `TopBottom360`, `SideBySide360`.

When any of these is set, START fades the museum out, plays the film with its own soundtrack, and fades
back to the museum at the end. Nothing else needs to change. With none set, the real-time / previs beats play.

Encoding for VIVE Focus 3 with Unity's built-in player: H.264 or H.265 MP4, up to 4096x2048 mono or
4096x4096 top-bottom stereo at 30 fps, ~40-60 Mbps, AAC audio. Anything above that (5.7K/8K) needs a
native player plugin such as AVPro Video.

The film's horizontal centre is treated as "front" and is placed straight ahead of the visitor at START
(`masterVideoYaw` nudges it if the film was authored differently). The film should open and close on the
museum view so the fade from/to the real-time lobby reads as continuous.

**Test film.** `MOI > Review > Encode 360 Test Film` writes `StreamingAssets/MOI_TestJourney360.mp4`: a full-length
mono 2048x1024 stand-in made from the storyboard (frames dead ahead, green bar = left, blue bar = right,
red block = behind, a beep on every beat). It is currently assigned on the sequence, so START plays it.
Verified in the editor: playback, seeking, beat sync, orientation. **Not yet verified on a headset**, and
not with a production-resolution file. Replace the path with the real film when it arrives and delete
the test file from StreamingAssets before the release build.

## Loading the film from the museum LAN (no rebuild to change content)

`ContentManager` reads a JSON manifest from a web server / CMS on the LAN, downloads the film it names to
the headset, verifies it (size, optional SHA-256) and plays that **local copy**; it never streams. Checks
happen at launch and every 10 minutes while idle, never during a visit. Server down = the cached film keeps
playing. The manifest also carries `layout` (mono / stereo 360 / flat) and `yaw`, so the film's format is a
content decision, not an app build. A film from the server wins over the fields on the sequence asset, which
win over the real-time beats.

Manifest format, publishing steps and how to point a headset at the server: `ContentServer/README.md`
(that folder is a ready-to-serve sample: `python -m http.server 8765`).
Verified in the editor against a local server: fetch, download, hash check, playback from cache, and
offline fallback. **Not yet verified on the headset over Wi-Fi.** The build allows plain-HTTP (cleartext)
traffic for this; if the museum's CMS is HTTPS with a private certificate, that needs handling.

## How it is put together

- `Data/PromiseOfSafety.asset` is the timeline: 18 beats with times, direction, EN/AR voice-over text,
  voice clips, environment, transition, museum state and crystal state. Edit timing here, not in code.
- `ExperienceDirector` evaluates everything from one clock (the audio DSP clock), so picture cannot drift
  from voice-over and any beat can be jumped to.
- `EnvironmentManager` decides how each beat is delivered. A beat only names an environment id; the
  entry behind it can be a live **Set**, a **PrevisFrame**, a **Panorama360** still or a **Video360** clip
  (mono / top-bottom / side-by-side). Swapping a beat from previs to final is a data change.
- `CrystalGuide` is one persistent crystal: podium → floating guide → back to podium.
- No real-time lights anywhere; all `MOI/*` shaders are unlit and single-pass-instanced.

## What is real and what is a stand-in

| Beats | State |
|---|---|
| 1–3, 17–18 Museum, dimming to outlines to dark and back | Real-time blockout. LED wall content is a crop of storyboard frame 1 – replace `Textures/T_MuseumWall_Placeholder` with the real wall media. Room dimensions are guesses until we get the museum's drawings. |
| 4 Preserving the Legacy | Real-time. Blank archive cards – drop real photos/documents into `Legacy Gallery > Memory Gallery > Photos`. |
| 5 The passage opens | Real-time (crystal glow ramp into white-out). |
| 6–16 Abu Dhabi 2076 … Qasr Al Hosn | **Previs only**: storyboard frames on a curved screen so timing and VO can be reviewed in-headset. The 3D crystal is hidden here because the frames already contain it. |

To finish a beat: add an `EnvironmentEntry` (or change the existing `previs_NN` entry's kind), assign the
set root / 360 video, and set that beat's `crystal` to `Floating` – its `crystalOffset` is already
placed to match the storyboard.

## Voice-over

Assign clips per beat in the sequence asset (`voiceClipEn`, `voiceClipAr`). Clips start at the beat's
start time. `music` on the asset is an optional bed started at 00:00. Subtitles are English only for
now: TextMeshPro does not shape Arabic, so Arabic subtitles need an RTL shaping pass and an Arabic font asset.

## Open points from the deck (need client answers)

- Summary page says **2077**, the beat page and both voice-overs say **2076**. Built as 2076.
- "The Last Light" is printed as 00:08–00:15 (same as the previous beat). Built as 00:15–00:22.
- "Safer Journeys" (00:53–01:06) repeats the previous beat's description and voice-over. Its voice-over is
  empty in the sequence until the real line is supplied.
- In the "Human-Led Protection" frame the officers' shoulder flags are not the UAE flag (AI image artefact).
  Worth fixing before the frame is shown to the Ministry, and a note for whoever produces the final beat.
