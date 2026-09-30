# Plan: the visitor flow on the ASUS PC (PC demo) - "headset down -> Press the button" must always work

Executed by the Claude session on the **ASUS PC** (it has the headset, SteamVR, the RTX 5080 and the project copy).
Written and approved on 2026-09-29 in the Claude session on the Lenovo laptop (whose project folder is now in its
Recycle Bin). The user keeps this file in the project folder next to `CLAUDE.md`.
**Project on the ASUS PC: `C:\Users\ASUS\Desktop\VR\VR`** (the inner `VR`, the folder that contains `Assets`) - it was
`C:\Users\Lenovo\VR` on the laptop, so any laptop path `C:\Users\Lenovo\VR\...` below maps to it.

## Context
The user's flow, in their words, step by step:
1. The screen says "Press the button to begin".
2. The Arduino button (or F9) starts the intro video.
3. When the intro ends, the screen says "Please put on the headset".
4. Headset put on -> the screen shows the headset view (mirror).
5. Headset put down -> the screen goes back to "Press the button to begin" (after 5 s; the app goes back to START).
6. Headset put on WITHOUT pressing the button -> the screen shows the headset view.
Decided with the user (2026-09-29): headset put on during the intro -> the intro stops and the view shows at once
(current behaviour). Only ONE start file: `START PC DEMO.bat`; the "button first" file goes.

What the check of the code found:
- `Deploy/visitor-station.ps1` already does all six steps in its default mode (state machine in the timer,
  ~line 1078: Waiting/Intro/Wear/Mirror; off-handling ~line 1133). Every step depends on ONE signal: `$S.worn`,
  which in PC mode comes only from the app's `status.txt` (`Poll-HeadsetStatus`, ~line 905; `worn=Unknown` -> `$null`).
- The Windows app reports worn only through OpenXR user presence (`ExperienceDirector.Worn`, ~line 205;
  `PcVrRuntime.PresenceSupported`). When that is missing or stuck, the station cannot see the headset put
  down (step 5 never fires, step 6 impossible; step 4 only by the 12 s timer). This is what failed on this PC
  on 2026-09-28 (19:34/19:49 runs: no `[MOI] WORN` lines at all), and the likely cause of the user's last
  "button first" test failing too.
- `START PC DEMO (button first).bat` (-> `-WaitForButton`) switches step 6 off by design - the opposite of the flow.

Fix: give the station a second, independent worn signal in PC mode: SteamVR's own system state, which SteamVR
writes to `<Steam>\logs\vrmonitor.txt` whenever the headset goes idle / active. Verified on the laptop's logs:
`... [Info] - [System] Unknown Transition from 'SteamVRSystemState_Ready' to 'SteamVRSystemState_Standby'.`
(35x Ready->Standby, 33x Standby->Ready; other states only at SteamVR start/stop). No Unity rebuild needed.

## Step 0 - Check the migrated project (read-only)
- The project folder `C:\Users\ASUS\Desktop\VR\VR` has: `CLAUDE.md`, `Assets`, `Packages\com.htc.upm.vive.openxr` (its `.aar` files are MBs,
  not 135-byte pointers), `ProjectSettings`, `Deploy` incl. `Deploy\dev-notes` and `Deploy\dev-tools`.
  If `CLAUDE.md` or `Deploy\dev-*` is missing: the user restores `CLAUDE` from the laptop's Recycle Bin and copies
  `C:\Users\Lenovo\VR\Deploy` again (still on the laptop).
- Find the PC demo folder on this PC (probably `C:\Users\ASUS\Downloads\MOI_PC_Demo`; search for `START PC DEMO.bat`).
  Its `MOI_PromiseOfSafety\MOI_PromiseOfSafety_Data\Managed\Assembly-CSharp.dll` must be dated 2026-09-28 20:02 or later (the .exe keeps an old date; this is the build that polls
  `IsUserPresent`). If older, use the one from the latest `MOI_PC_Demo.zip`.
- Unity is NOT needed for this plan.
- The test scripts in `Deploy\dev-tools` find the project from their own location (`$MoiRoot`); the package folders
  they use (`$MoiRoot\Delivery\...`) may be elsewhere on this PC - adjust that line before using one.
- The project copy on this PC came from `VR.rar` (made 2026-09-29 12:02), which is older than `CLAUDE.md`,
  `Deploy\dev-notes` and `Deploy\dev-tools`; the user adds them from `ASUS-handoff.zip` (extracted into the project folder).
- If Unity shows errors on every Scene-view redraw ("... AssetDatabase cannot load now", "Blitter is already initialized"):
  the copied `Library` is broken - close Unity, rename `Library`, reopen (see CLAUDE.md). Same fix as on the laptop.
- If Unity is opened later: in Unity Hub add `C:\Users\ASUS\Desktop\VR\VR` (the inner folder), not the outer `VR`.

## Step 1 - Read the logs of the user's last failed test (read-only, before changing anything)
- `<demo folder>\logs\station-<date>.log`: the `headset: state=... worn=...` lines, `-> Mirror`, and whether
  `headset off for 5 s` / `-> Waiting` ever appear after the put-down.
- `%USERPROFILE%\AppData\LocalLow\GameX\MOI Promise of Safety\Player.log` (and `Player-prev.log`):
  `[MOI] VR runtime reports whether the headset is worn` or `... does NOT report ...`, `[MOI] WORN True/False`.
- `<Steam>\logs\vrmonitor.txt` (Steam path: registry `HKCU\Software\Valve\Steam` value `SteamPath`): do
  `Ready -> Standby` lines appear at the times the headset was put down? This decides whether Step 2 works here.
- Tell the user in 3-4 lines what happened. If WORN False DID reach the station and it still did not go back,
  stop and investigate that instead (it would be a station bug, not the signal).

## Step 2 - Station change: SteamVR state as a second worn signal (PC mode only)
File: `Deploy/visitor-station.ps1` (keep a copy `visitor-station.before-steamvr.ps1` first). Rules from
CLAUDE.md apply (never a `$s` handler parameter; verify syntax in PowerShell).
- Parameters: `[switch]$NoSteamVr` (off switch), `[string]$SteamVrLog = ""` (override, for tests). With `-PcApp`
  and no override: `<SteamPath>\logs\vrmonitor.txt`, fallback `C:\Program Files (x86)\Steam\logs\vrmonitor.txt`.
- New fields in `$S`: `vrWorn = $null; vrWornAt = [DateTime]::MinValue; vrLogPos = 0L; appWorn = $null;
  appWornAt = [DateTime]::MinValue`.
- New `Read-SteamVrState`, called every second next to `Poll-HeadsetStatus` (the 1-second block, ~line 1016),
  only with `-PcApp`:
  - open with `[IO.File]::Open(path, Open, Read, ReadWrite|Delete)`; if the file is shorter than `vrLogPos`
    (SteamVR restarted, new log) start from 0; read only the new text; remember the position.
  - lines matching `^(\w{3} \w{3} \d{2} \d{4} \d{2}:\d{2}:\d{2}\.\d{3}) .*Transition from 'SteamVRSystemState_\w+'
    to 'SteamVRSystemState_(\w+)'`: `Ready` -> `$true`, `Standby` -> `$false`, anything else -> `$null`;
    time = `ParseExact(ts, 'ddd MMM dd yyyy HH:mm:ss.fff', InvariantCulture)`. On a change: `vrWorn`, `vrWornAt`,
    log `SteamVR: <state>`.
  - no `vrserver` process running -> `vrWorn = $null` (a log from an earlier SteamVR run says nothing).
  - the first read at station start goes through the whole file and ends on SteamVR's current state.
- `Poll-HeadsetStatus`, PC branch, where `$S.worn` is set today (~line 931, before the `$raw -eq $S.statusRaw`
  early return): the app's value goes to `appWorn` (`appWornAt` = now when it changes); then
  ```
  if ($null -eq $S.appWorn) { $S.worn = $S.vrWorn }             # app has no wear sensor: SteamVR decides
  elseif ($S.appWorn -and $S.vrWorn -eq $false -and $S.vrWornAt -gt $S.appWornAt) { $S.worn = $false }
                                                                # SteamVR went to standby after the app last said "worn"
  else { $S.worn = $S.appWorn }                                 # the app's sensor decides
  ```
  (SteamVR's "Ready" also comes when staff just pick the headset up by hand, so it only decides when the app has
  no sensor at all; its "Standby" can always end a visit - that covers a sensor that is missing or stuck on
  "worn".) When the two disagree, log it once per change (`worn from SteamVR (Standby) - app says True`).
- Nothing else changes: the Waiting/Intro/Wear/Mirror code already reacts to `$S.worn`. Android/headset mode
  (`-PcApp` not set) is untouched.
- Header comment + parameter help: one line each for `-NoSteamVr` / `-SteamVrLog`.
- Quick offline check before the headset: run the station windowed with `-PcApp <exe> -SteamVrLog <temp file>
  -Windowed -QuitAfter 90`, append Ready/Standby lines to the temp file, confirm `SteamVR: ...` and the state
  changes in the station log.

## Step 3 - One start file
- Delete `Deploy/pc-demo/START PC DEMO (button first).bat` (and the copy in the demo folder).
- `Deploy/pc-demo/start-pc-demo.ps1`: remove the `-ButtonFirst` switch (lines ~11, 14, 76).
- `Deploy/pc-demo/README-PC-DEMO.txt`: remove the "button first" lines under OTHER WAYS TO START; under IF
  SOMETHING DOES NOT WORK add that the station also follows SteamVR's standby (`vrmonitor.txt`).
- `Deploy/DEPLOYMENT.md` (~line 136): note the SteamVR signal; `-WaitForButton` stays in the station as an
  advanced option only. The PC demo handbook has no "button first" text (checked).

## Step 4 - Test with the headset, one step at a time (the user's "step by step")
Copy the new `visitor-station.ps1`, `start-pc-demo.ps1`, README into the demo folder. Warn the user before
starting (the station takes the whole screen). For each step: tell the user what to do, wait, then read the
station log (and Player.log / vrmonitor.txt) and confirm before the next step.
| # | User does | Screen must show | Station log must show |
|---|-----------|------------------|-----------------------|
| 1 | Headset on the table, double-click START PC DEMO | Press the button to begin | `VR app started`, `SteamVR: Standby` or `worn=False` |
| 2 | Press the Arduino button | Intro plays | `serial: PUSH_TO_PLAY`, `-> Intro` |
| 3 | Wait for the intro to end | Please put on the headset | `-> Wear` |
| 4 | Put the headset on | Headset view within ~2 s | `headset put on`, `-> Mirror` |
| 5 | Put the headset down on the table | Press the button, ~5-10 s later | `headset off for 5 s`, `-> Waiting`, `app told to reset` |
| 6 | Without the button, put the headset on | Headset view, START in the headset | `headset put on - straight to the headset view` |
| 7 | Button, then headset on during the intro | Intro stops, view shows | `headset put on during the intro` |
| 8 | START in the headset, film plays, put it down | Press the button; film stopped | `headset off for 5 s`; Player.log `Command from the station: reset` |
| 9 | Lift the headset 2 s and put it back on | Nothing changes | no `-> Waiting` |
| 10 | Close (Ctrl+Shift+Q); headset ON; start the demo | Headset view at once | `-> Mirror` without the button |
Also check the film is smooth (`[MOI] Film 7680x3840 ... 30.0 fps, 0 frame(s) dropped` in Player.log).
If step 5 still fails and vrmonitor.txt shows no Standby on this PC: contingency is an app change (on Windows,
when presence is missing, use the OpenXR session state FOCUSED vs not) - needs Unity + a Windows build; discuss first.

## Step 5 - Package and hand back
- Copy the final `visitor-station.ps1` into both packages (PC demo + VR station; the new code only runs with
  `-PcApp`, so the headset station behaves as before - one quick put-on/put-down check on a headset if one is
  plugged in with adb).
- Rebuild `MOI_PC_Demo.zip` (and `MOI_VR_Station.zip` if its folder is on this PC) with `ZipArchive` and
  forward-slash entry names, excluding `logs` and `intro_previous.mp4` (CLAUDE.md, "Packages").
- Update `CLAUDE.md` (open item 1 -> done, the new signal in "Rules") and the project log in `Deploy/dev-notes`.
- Tell the user where the new zip is, in one line.

## Message for the user to paste as the first message in the ASUS session (opened in `C:\Users\ASUS\Desktop\VR\VR`)
> C:\Users\ASUS\Desktop\VR\VR is my MOI "Promise of Safety" VR project, moved from my Lenovo laptop to this PC. Read CLAUDE.md
> first, then NEXT-SESSION-PLAN.md, and follow that plan step by step: check the project copy, read the logs of my
> last test and tell me what went wrong, make the station change, then test the visitor flow with me one step at
> a time - tell me what to do with the headset and read the logs before the next step. Don't change anything
> outside the plan, warn me before anything takes over the screen, and ask before installing anything.
