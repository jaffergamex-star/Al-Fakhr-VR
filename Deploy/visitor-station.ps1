<#
  MOI visitor station: one PC + one headset (USB cable) + one screen + a physical button.

    Waiting  : screen says "Press the button to begin".
    Button   : the intro video plays full screen on the PC (with sound).
    Wear     : screen says "Please put on the headset".
    Mirror   : as soon as the headset is worn (or START is pressed in it), the screen shows the live view from
               the headset. Nobody puts it on within WearGiveUp seconds -> back to Waiting.
    Back     : when the film in the headset ends, back to Waiting.
  The headset decides as well: put on at ANY time (also at "Press the button" or during the intro) -> Mirror at
  once; taken off for OffReset seconds (5), film or not -> Waiting, and the app is sent back to its START screen.
  (-WaitForButton and -KeepFilmWhenOff restore the older behaviour.)

  The button (Arduino): the Arduino sends a line of text over USB serial when the button is pressed,
  "START" by default (sketch in Deploy\arduino\moi_button). The station finds the Arduino's COM port by
  itself and reconnects if it is unplugged. A line containing "RESET" sends the station back to waiting.
      -SerialPort COM5         use a specific port instead of auto-detect ("none" = keyboard only)
      -BaudRate 9600           must match Serial.begin() in the sketch
      -SerialCommand "PUSH_TO_PLAY,START"   texts that start the sequence, comma-separated (empty = any line)

  Keyboard backup: any USB button/sensor that types a key (most "USB big buttons" and sensor-to-USB boards can be
  set to send one key). Tell the script which key with -TriggerKey (default F9). The key is read globally,
  so it works whatever window has focus.

  Run:
      powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -Intro "D:\media\intro.mp4"
  Options:
      -TriggerKey Space        key the button sends (any name from System.Windows.Forms.Keys: F9, Space, Enter, A...)
      -Screen 2                force one screen (1 = leftmost). Default: automatic - the screen attached to the
                               PC (a laptop's own panel only while nothing else is connected), the largest if
                               several; re-checked every few seconds, so it moves there when the screen comes on
      -WearGiveUp 120          seconds "Please put on the headset" waits for someone to put it on, then back to waiting
      -OffReset 5              headset taken off, unplugged or switched off this long -> back to waiting (and the app
                               back to START)
      -WearTimeout 12          only when the headset reports nothing (not connected): seconds after the intro before
                               the station moves on to the mirror / "Connecting to the headset..."
      -MirrorTimeout 420       safety net: longest wait for START in the headset, and longest film
      -Crop w:h:x:y            override the mirror crop (default: 16:9 slice of the left eye, detected automatically)
      -Square                  show the whole (square) left eye, with bars, instead of a slice shaped like the screen
      -MirrorCentre 0.578      where "straight ahead" is in the left-eye image, as a share of its width (measured on a
                               Focus Vision 2026-09-30: 1414 of 2448 px; the lens sits towards the nose). The slice is
                               centred there, so the mirror shows what the visitor looks at
      -MirrorCropFor 3096x1290 print the mirror slice and stream size the station would use on a screen of that size
      -IntroFill               crop the intro to fill the screen when its shape differs (default: whole video, with bars)
      -IdentifyScreens         show each screen's number for 6 seconds and say which one the station will use
      -IntroSkip 5             start the intro 5 s in (skips a black lead-in in the video file)
      -Portrait                portrait layout (automatic when the screen is taller than wide, e.g. 4K 2160x3840)
      -MirrorWidth 1920        mirror stream size, longest side (default: 1280 on screens up to full HD wide, else
                               the slice's full size up to about 2 megapixels - same load as a full-HD stream)
      -MirrorBitRate 20M       mirror picture quality: the stream's bit rate (was 6M until 2026-09-30 - blocky and smeared
                               on the moving 360 film; at the museum's 3096x1290 LED the slice is 2048x856 at 30 fps, and 6M
                               is only ~0.11 bit per pixel). Costs the headset's encoder almost nothing (size and fps do).
      -MirrorCodec h264        mirror stream codec: h264 | h265 | av1 (h265 = better picture for the same bit rate, if the
                               headset's encoder has it; Deploy\dev-tools\MIRROR QUALITY TEST.bat compares them)
      -MirrorFps 30            mirror frame rate (the film is 30 fps)
      -MirrorAudio             also play the headset's sound on the PC during the mirror
      -ShowStatus              keep the small grey status line visible in full-screen mode (hidden by default)
      -InstallAutostart / -RemoveAutostart   start this at Windows logon (keeps the options you pass with it)
  Test on a desktop without the button:
      -Windowed -AutoPressAfter 3 -QuitAfter 30

  The station also starts the MOI app on the headset by itself, and restarts it if it closes or crashes
  (checked every 10 s). -NoLaunchApp turns that off.

  PC VR demo (-PcApp): the app runs on this PC and is streamed to the headset by VIVE Streaming / SteamVR instead of
  running on the headset. Same visitor flow. The app's own window, placed full screen on the VR screen, is the
  mirror; the station starts the app (or takes over one that is running), restarts it if it closes, and reads its
  status file on this PC. Closing the station closes the app.
      -PcApp "MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe"   relative to this script's folder, or a full path
      -PcFilm "content\journey_4k.mp4"                       the film the app plays (relative to the app's folder)
      -PcAppArgs:"..."                                       anything else for the app (colon form: it starts with -)
      -WaitForButton       older flow: the headset view only after the button and the intro (a headset put on while
                           "Press the button" is showing or during the intro is ignored until then)
      -KeepFilmWhenOff     older flow: taking the headset off during the film does not end the visit; the headset app
                           ends the film by itself after about 10 s off, and the station follows it
      -OffRestartsApp      (with -PcApp) when the headset comes off, the whole app is closed and started again, instead
                           of being sent back to START
      -KeepViveLayers      (with -PcApp) leave VIVE Hub's OpenXR add-on layers on for the app (off by default: the app
                           doesn't use them, and one of them hid the headset's wear sensor on a PC)
      Worn / taken off in the PC demo: the headset's own proximity sensor, read over the USB cable with adb once a second
                           (MoiProximityPoller) - exact and instant in any position. The app's wear sensor and SteamVR's
                           Ready / Standby are only the fallback while there is no proximity reading: both stay "worn"
                           until the headset falls asleep, 3 minutes after it is put down (measured 2026-09-30).
                           Needs USB debugging on the headset and this PC allowed once. Log: "headset proximity sensor: ...".
      -NoProximity         (with -PcApp) don't read the proximity sensor (then the app's sensor + SteamVR decide)
      -PcAppSoundAlways    (with -PcApp) keep the app's sound on all the time. Default: the app is heard only in the headset
                           view while the headset is on; at "Press the button", the intro and "Please put on the headset"
                           the station mutes it in the Windows volume mixer (the intro keeps its own sound).
      -NoSteamVr           (with -PcApp) don't use SteamVR's own state (Ready / Standby, from its log vrmonitor.txt) as a
                           second "headset worn" signal next to the app's wear sensor
      -SteamVrLog <file>   (with -PcApp) read this SteamVR log instead of <Steam>\logs\vrmonitor.txt (for tests)

  Desktop icons "Start VR Station" / "Stop VR Station" (created once with -InstallShortcuts):
      ... visitor-station.ps1 -InstallShortcuts        (add start options here, e.g. -Screen 2)
  Only one station runs at a time; starting it again while it runs does nothing.

  Staff: Ctrl+Shift+Q quits (Alt+F4 is ignored: it's a kiosk). Needs scrcpy (winget install Genymobile.scrcpy) and USB debugging allowed.
#>
param(
    [string]$Intro = (Join-Path $PSScriptRoot "intro.mp4"),
    # Seconds to skip at the start of the intro (e.g. a black lead-in in the video file).
    [double]$IntroSkip = 0,
    [string]$TriggerKey = "F9",
    [int]$Screen = 0,
    [int]$WearTimeout = 12,
    [int]$WearGiveUp = 120,
    # Headset taken off, unplugged or switched off this long -> back to "Press the button" and the app back to START.
    # Long enough to ride out someone adjusting the strap.
    [int]$OffReset = 5,
    [int]$MirrorTimeout = 420,
    [string]$Crop = "",
    [switch]$MirrorAudio,
    [switch]$Square,
    [string]$MirrorCropFor = "",
    [switch]$IntroFill,
    [int]$MirrorWidth = 1280,
    [double]$MirrorCentre = 0.578,
    [string]$MirrorBitRate = "20M",
    [ValidateSet("h264", "h265", "av1")] [string]$MirrorCodec = "h264",
    [int]$MirrorFps = 30,
    [string]$Serial = "",
    [string]$WaitingText = "Press the button to begin",
    [string]$WearText = "Please put on the headset",
    [switch]$Windowed,
    [switch]$ShowStatus,
    [switch]$Portrait,
    [int]$SimulateLateScreen = 0,
    # Test without a headset: the status line is read from this file (file missing = headset unplugged), and a
    # stand-in window plays the mirror.
    [string]$SimulateHeadset = "",
    [string]$PcApp = "",
    [string]$PcFilm = "",
    [string]$PcAppArgs = "",
    [switch]$WaitForButton,
    [switch]$KeepFilmWhenOff,
    [switch]$OffRestartsApp,
    [switch]$KeepViveLayers,
    [switch]$NoSteamVr,
    [string]$SteamVrLog = "",
    [switch]$NoProximity,
    [switch]$PcAppSoundAlways,
    [int]$AutoPressAfter = 0,
    [int]$QuitAfter = 0,
    [string]$SerialPort = "auto",
    [int]$BaudRate = 9600,
    # Comma-separated. PUSH_TO_PLAY is what the museum's button board sends; START is our own sketch.
    [string]$SerialCommand = "PUSH_TO_PLAY,START",
    [int]$SerialBootIgnore = 3,
    [int]$SimulateSerialAfter = 0,
    [switch]$NoLaunchApp,
    [switch]$ListPorts,
    [switch]$IdentifyScreens,
    [string]$AppPackage = "com.gamex.moi.promiseofsafety",
    [switch]$InstallAutostart,
    [switch]$RemoveAutostart,
    [switch]$InstallShortcuts,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"
# The headset decides the flow unless the older behaviour is asked for (see the help above).
$MirrorWhenWorn = -not $WaitForButton
$OffEndsVisit = -not $KeepFilmWhenOff

# The button box's settings come from button-commands.txt next to this script, so staff can change them with Notepad:
#   command = PUSH_TO_PLAY, START     texts that start a visit (a line from the box containing one of them)
#   port = auto                       or COM5
#   baud = 9600
# Options given on the command line win over the file.
$ButtonFile = Join-Path $PSScriptRoot "button-commands.txt"
$ButtonSource = "built-in default"
if (Test-Path $ButtonFile) {
    $texts = @()
    foreach ($raw in Get-Content $ButtonFile) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        if ($line -match '^baud\s*[=:]\s*(\d+)') { if (-not $PSBoundParameters.ContainsKey("BaudRate")) { $BaudRate = [int]$Matches[1] } }
        elseif ($line -match '^port\s*[=:]\s*(COM\d+|auto|none)') { if (-not $PSBoundParameters.ContainsKey("SerialPort")) { $SerialPort = $Matches[1] } }
        elseif ($line -match '^commands?\s*[=:]\s*(.*)$') { $texts += @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        else { $texts += $line }
    }
    if ($texts.Count -gt 0 -and -not $PSBoundParameters.ContainsKey("SerialCommand")) { $SerialCommand = $texts -join ","; $ButtonSource = "button-commands.txt" }
}
if ($PSBoundParameters.ContainsKey("SerialCommand")) { $ButtonSource = "command line" }
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class MoiDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][MoiDpi]::SetProcessDPIAware()
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$StartupLink = Join-Path ([Environment]::GetFolderPath("Startup")) "MOI Visitor Station.lnk"
$Desktop = [Environment]::GetFolderPath("Desktop")

# Options given together with -InstallAutostart / -InstallShortcuts are baked into what they start.
function Get-PassThroughArgs {
    $pass = @()
    foreach ($k in $script:BoundForLinks.Keys) {
        if ($k -in @("InstallAutostart", "InstallShortcuts", "RemoveAutostart", "Stop")) { continue }
        $v = $script:BoundForLinks[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $pass += "-$k" } }
        else { $pass += "-$k `"$v`"" }
    }
    $pass -join " "
}
$script:BoundForLinks = $PSBoundParameters

function New-StationLink($path, $extraArgs, $description) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = "powershell.exe"
    $link.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" $extraArgs"
    $link.WorkingDirectory = $PSScriptRoot
    $link.Description = $description
    $link.IconLocation = "$env:SystemRoot\System32\shell32.dll,$(if ($extraArgs -match '-Stop') { 131 } else { 137 })"
    $link.Save()
}

if ($RemoveAutostart) {
    if (Test-Path $StartupLink) { Remove-Item $StartupLink }
    Write-Host "Autostart removed."; return
}
if ($InstallAutostart) {
    $pass = Get-PassThroughArgs
    New-StationLink $StartupLink $pass "Starts the MOI VR station when Windows signs in"
    Write-Host "Visitor station will start at logon with: $pass"
    return
}
if ($InstallShortcuts) {
    $pass = Get-PassThroughArgs
    New-StationLink (Join-Path $Desktop "Start VR Station.lnk") $pass "Start the MOI VR station (full screen)"
    New-StationLink (Join-Path $Desktop "Stop VR Station.lnk") "-Stop" "Close the MOI VR station"
    Write-Host "Desktop icons created: 'Start VR Station' and 'Stop VR Station' (start options: $pass)"
    return
}

# Stop: close a running station and its mirror (what the "Stop VR Station" icon does).
if ($Stop) {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match "visitor-station\.ps1" -and $_.CommandLine -notmatch "-Stop" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process scrcpy -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # PC VR demo: the app runs on this PC.
    Get-Process MOI_PromiseOfSafety -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    return
}

# PC VR demo: the app's .exe (relative to this script) and the status file it writes on this PC.
if ($PcApp) {
    if (-not [IO.Path]::IsPathRooted($PcApp)) { $PcApp = Join-Path $PSScriptRoot $PcApp }
    if (-not (Test-Path $PcApp)) { Write-Host "No VR app at $PcApp"; exit 1 }
    $PcApp = (Resolve-Path $PcApp).Path
}
$PcStatusFile = Join-Path $env:USERPROFILE "AppData\LocalLow\GameX\MOI Promise of Safety\status.txt"
# PC VR demo: SteamVR's log, where it writes its state whenever the headset goes idle or comes back (Read-SteamVrState).
if ($PcApp -and $NoSteamVr) { $SteamVrLog = "" }
elseif ($PcApp -and -not $SteamVrLog) {
    $steam = try { (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath } catch { $null }
    if (-not $steam) { $steam = Join-Path ${env:ProgramFiles(x86)} "Steam" }
    $SteamVrLog = Join-Path ($steam -replace "/", "\") "logs\vrmonitor.txt"
}


# ---------------------------------------------------------------- helpers (C#: background reading + global key)
Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class MoiScreens {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, uint i, ref DISPLAY_DEVICE dd, uint flags);
    // e.g. \\?\DISPLAY#LEN66F7#4&386843f&0&UID4145#{e6f07b5f-...}
    public static string MonitorPath(string displayName) {
        var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
        return EnumDisplayDevices(displayName, 0, ref dd, 1) ? dd.DeviceID : "";
    }
}

// The mirror is another program's window, so only calls that don't wait for it to answer: a mirror that hangs
// must never freeze the station (ShowWindow / SetWindowPos on another program's window otherwise wait).
public static class MoiWin {
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }

    // During the mirror step the mirror is TOPMOST, so no other window (Explorer, a notification, another
    // app) can cover it. The station window takes the top spot back when it is shown again.
    public static bool Raise(IntPtr h) {
        if (h == IntPtr.Zero) return false;
        ShowWindowAsync(h, 9);                               // SW_RESTORE: un-minimise / show
        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x4003); // HWND_TOPMOST, keep size and position, async
        return SetForegroundWindow(h);
    }
    // Once a second during the mirror step: back to the very top (above the taskbar, or a window that also
    // wants to be on top), without taking the keyboard focus.
    public static void KeepOnTop(IntPtr h) {
        if (h == IntPtr.Zero) return;
        if (IsIconic(h)) ShowWindowAsync(h, 9);
        SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x4013); // HWND_TOPMOST, no move/size/activate, async
    }
    public static void Lower(IntPtr h) {
        if (h == IntPtr.Zero) return;
        SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x4013); // HWND_NOTOPMOST, no move/size/activate, async
    }
    // PC VR demo: the app's window exactly on the VR screen, z-order untouched.
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    public static void Place(IntPtr h, int x, int y, int w, int hh) {
        if (h == IntPtr.Zero) return;
        SetWindowPos(h, IntPtr.Zero, x, y, w, hh, 0x4014);    // no z-order change, no activate, async
    }
    public static bool IsAt(IntPtr h, int x, int y, int w, int hh) {
        RECT r;
        if (h == IntPtr.Zero || !GetWindowRect(h, out r)) return false;
        return r.L == x && r.T == y && r.R - r.L == w && r.B - r.T == hh;
    }
    // Process id of the top-level window at a screen point (real pixels).
    public static uint PidAt(int x, int y) {
        var p = new POINT { X = x, Y = y };
        IntPtr h = GetAncestor(WindowFromPoint(p), 2);
        uint pid; GetWindowThreadProcessId(h, out pid);
        return pid;
    }
}

// The button key and Ctrl+Shift+Q are watched on a thread of their own, about 60 times a second. The station's
// main thread is busy for a moment every second (reading the headset over USB) and could miss a short tap.
public static class MoiKeys {
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    static bool Down(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
    static int presses;
    static volatile bool quit;
    public static bool QuitRequested { get { return quit; } }
    public static int TakePresses() { return Interlocked.Exchange(ref presses, 0); }
    public static void Watch(int vk) {
        new Thread(() => {
            bool was = false;
            while (true) {
                bool down = Down(vk);
                if (down && !was) Interlocked.Increment(ref presses);
                was = down;
                if (Down(0x11) && Down(0x10) && Down(0x51)) quit = true;
                Thread.Sleep(10);
            }
        }) { IsBackground = true }.Start();
    }
}

// Runs "adb logcat" and hands its lines over through a queue (PowerShell can't take callbacks from other threads).
// Reads lines from a serial port (Arduino) on a background thread; survives unplugging.
public class MoiSerial {
    public readonly ConcurrentQueue<string> Lines = new ConcurrentQueue<string>();
    System.IO.Ports.SerialPort port;
    public string PortName { get { return port != null ? port.PortName : ""; } }
    public bool IsOpen { get { try { return port != null && port.IsOpen; } catch { return false; } } }
    public string LastError = "";
    public bool Open(string name, int baud) {
        Close();
        try {
            port = new System.IO.Ports.SerialPort(name, baud);
            port.ReadTimeout = 150; port.DtrEnable = true; port.RtsEnable = true;
            port.Open();
            var p = port;
            new Thread(() => {
                var buf = new System.Text.StringBuilder();
                Action flush = () => { var t = buf.ToString().Trim(); buf.Length = 0; if (t.Length > 0) Lines.Enqueue(t); };
                while (true) {
                    try {
                        int b = p.ReadByte();
                        if (b < 0) break;
                        if (b == 13 || b == 10) flush(); else buf.Append((char)b);
                    }
                    catch (TimeoutException) { flush(); }
                    catch { break; }
                }
            }) { IsBackground = true }.Start();
            LastError = "";
            return true;
        } catch (Exception e) { LastError = e.Message; port = null; return false; }
    }
    public void Close() { try { if (port != null) port.Close(); } catch { } port = null; }
}

// Reads the headset over USB on a thread of its own, once a second: which headset is connected, and the app's
// status line (only while the app runs). The station's main thread just looks at the latest result, so the
// reads never hold up the intro video - and the headset is watched during the intro too.
public class MoiHeadsetPoller {
    readonly string adb, package, wanted;
    volatile string headset = "", status = "";
    long statusTicks;
    volatile bool stop;
    public string Headset { get { return headset; } }
    public string Status { get { return status; } }
    public DateTime StatusAt { get { return new DateTime(Interlocked.Read(ref statusTicks)); } }
    public MoiHeadsetPoller(string adb, string package, string wanted) { this.adb = adb; this.package = package; this.wanted = wanted ?? ""; }
    public void Start() { new Thread(Loop) { IsBackground = true }.Start(); }
    public void Stop() { stop = true; }
    void Loop() {
        bool serverUp = false;
        while (!stop) {
            var sw = Stopwatch.StartNew();
            try {
                // Starting the adb server can take over 5 s (5.1 s on the dev laptop). Cut off by the 5 s limit below it
                // never came up and the headset was never seen - so the server is started with a longer limit first,
                // and again whenever a call had to be cut off.
                if (!serverUp) serverUp = Run("start-server", 30000) != null;
                string found = "";
                string list = Run("devices", 5000);
                if (list == null) { serverUp = false; list = ""; }
                foreach (var raw in list.Split('\n')) {
                    var line = raw.Trim();
                    if (!line.EndsWith("\tdevice")) continue;
                    var serial = line.Split('\t')[0];
                    if (wanted.Length == 0 || serial == wanted) { found = serial; break; }
                }
                headset = found;
                if (found.Length > 0) {
                    status = (Run("-s " + found + " shell \"pidof " + package + " >/dev/null && cat /sdcard/Android/data/" + package + "/files/status.txt\"", 5000) ?? "").Trim();
                    Interlocked.Exchange(ref statusTicks, DateTime.Now.Ticks);
                } else status = "";
            } catch { headset = ""; status = ""; }
            int rest = 1000 - (int)sw.ElapsedMilliseconds;
            Thread.Sleep(rest > 50 ? rest : 50);
        }
    }
    // adb with a time limit: a hung adb must not stop the polling. null = it had to be cut off.
    string Run(string args, int limitMs) {
        var psi = new ProcessStartInfo(adb, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        using (var p = Process.Start(psi)) {
            var outTask = p.StandardOutput.ReadToEndAsync();
            var errTask = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(limitMs)) { try { p.Kill(); } catch { } return null; }
            return outTask.Wait(1000) ? outTask.Result : "";
        }
    }
}

// PC demo: the headset's own proximity sensor (a face in the headset or not), read over the USB cable once a second.
// The headset logs every change of it ("ucs148c1 Proximity Sensor Wakeup: last 30 events", value 0.00 = near = worn,
// 1.00 = far = off); the newest event (by its ts, not the headset's clock, which is wrong without internet) is the state.
// SteamVR's own "worn" and Ready/Standby only change when the headset falls asleep, 3 minutes after it is put down.
public class MoiProximityPoller {
    readonly string adb;
    volatile string serial = "", problem = "";
    volatile int state = -1;          // -1 no reading, 0 taken off, 1 worn
    long atTicks;
    volatile bool stop;
    public string Serial { get { return serial; } }
    public string Problem { get { return problem; } }
    public int State { get { return state; } }
    public DateTime At { get { return new DateTime(Interlocked.Read(ref atTicks)); } }
    public MoiProximityPoller(string adb) { this.adb = adb; }
    public void Start() { new Thread(Loop) { IsBackground = true }.Start(); }
    public void Stop() { stop = true; }
    void Loop() {
        bool serverUp = false;
        var nextFind = DateTime.MinValue;
        while (!stop) {
            var sw = Stopwatch.StartNew();
            try {
                // As MoiHeadsetPoller: starting the adb server can take over 5 s.
                if (!serverUp) serverUp = Run("start-server", 30000) != null;
                if (serial.Length == 0 && DateTime.Now >= nextFind) { nextFind = DateTime.Now.AddSeconds(3); serial = FindHeadset(); }
                if (serial.Length > 0) {
                    string text = Run("-s " + serial + " shell dumpsys sensorservice", 5000);
                    // Unplugged, or one call failed: look for it again. The last reading is kept; it counts for 3 s only
                    // (see the station), so one hiccup changes nothing.
                    if (text == null) { serverUp = false; serial = ""; }
                    else if (text.Length == 0) serial = "";
                    else {
                        int s = Parse(text);
                        if (s < 0) problem = "the headset reports no proximity sensor history";
                        else { problem = ""; state = s; Interlocked.Exchange(ref atTicks, DateTime.Now.Ticks); }
                    }
                }
            } catch (Exception e) { problem = e.Message; }
            int rest = 1000 - (int)sw.ElapsedMilliseconds;
            Thread.Sleep(rest > 50 ? rest : 50);
        }
    }
    // A VIVE headset among the adb devices (a phone on the same PC also has a proximity sensor). Says why when there is none.
    string FindHeadset() {
        string list = Run("devices", 5000);
        if (list == null) { problem = "adb did not answer"; return ""; }
        bool unauthorized = false;
        foreach (var raw in list.Split('\n')) {
            var line = raw.Trim();
            if (line.EndsWith("\tunauthorized")) { unauthorized = true; continue; }
            if (!line.EndsWith("\tdevice")) continue;
            var s = line.Split('\t')[0];
            var model = Run("-s " + s + " shell getprop ro.product.model", 5000) ?? "";
            if (model.IndexOf("VIVE", StringComparison.OrdinalIgnoreCase) >= 0 || model.IndexOf("Focus", StringComparison.OrdinalIgnoreCase) >= 0) { problem = ""; return s; }
        }
        problem = unauthorized ? "USB debugging not allowed for this PC yet (accept 'Allow USB debugging?' in the headset)"
                               : "no headset over adb (USB debugging off, or the cable is out)";
        return "";
    }
    static readonly System.Text.RegularExpressions.Regex Event = new System.Text.RegularExpressions.Regex(@"^\s*\d+ \(ts=([\d.]+), wall=[\d:.]+\) (-?[\d.]+),");
    public static int Parse(string text) {
        string[] lines = text.Split('\n');
        int block = -1;
        for (int i = 0; i < lines.Length; i++) {
            if (lines[i].IndexOf("Proximity Sensor", StringComparison.OrdinalIgnoreCase) < 0 || lines[i].IndexOf(": last", StringComparison.Ordinal) < 0) continue;
            block = i;
            if (lines[i].IndexOf("Wakeup", StringComparison.Ordinal) >= 0 && lines[i].IndexOf("Non-wakeup", StringComparison.Ordinal) < 0) break;  // prefer the wake-up sensor
        }
        if (block < 0) return -1;
        double bestTs = -1, value = -1;
        for (int i = block + 1; i < lines.Length; i++) {
            var m = Event.Match(lines[i]);
            if (!m.Success) break;
            double ts = double.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
            if (ts > bestTs) { bestTs = ts; value = double.Parse(m.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture); }
        }
        if (bestTs < 0) return -1;
        return value < 0.5 ? 1 : 0;
    }
    string Run(string args, int limitMs) {
        var psi = new ProcessStartInfo(adb, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        using (var p = Process.Start(psi)) {
            var outTask = p.StandardOutput.ReadToEndAsync();
            var errTask = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(limitMs)) { try { p.Kill(); } catch { } return null; }
            return outTask.Wait(1000) ? outTask.Result : "";
        }
    }
}

public class MoiLogWatcher {
    public readonly ConcurrentQueue<string> Lines = new ConcurrentQueue<string>();
    Process proc;
    public bool Alive { get { return proc != null && !proc.HasExited; } }
    public void Start(string adb, string args) {
        Stop();
        var psi = new ProcessStartInfo(adb, args) { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
        proc = Process.Start(psi);
        var p = proc;
        new Thread(() => { try { string l; while ((l = p.StandardOutput.ReadLine()) != null) Lines.Enqueue(l); } catch { } }) { IsBackground = true }.Start();
    }
    public void Stop() { try { if (Alive) proc.Kill(); } catch { } proc = null; }
}
"@

function Find-Scrcpy {
    # A copy shipped next to this script (delivery package) wins, so the site PC needs no internet.
    $bundled = Join-Path $PSScriptRoot "tools\scrcpy\scrcpy.exe"
    if (Test-Path $bundled) { return $bundled }
    if (Test-Path "C:\Tools\scrcpy\scrcpy.exe") { return "C:\Tools\scrcpy\scrcpy.exe" }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetRoot) {
        $hit = Get-ChildItem $wingetRoot -Directory -Filter "Genymobile.scrcpy*" -ErrorAction SilentlyContinue |
               Get-ChildItem -Recurse -Filter scrcpy.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $cmd = Get-Command scrcpy -ErrorAction SilentlyContinue
    if ($cmd) { $item = Get-Item $cmd.Source; if ($item.Target) { return [string]($item.Target | Select-Object -First 1) }; return $cmd.Source }
    return $null
}

$Scrcpy = Find-Scrcpy
$Adb = "C:\Program Files\Unity\Hub\Editor\6000.1.4f1\Editor\Data\PlaybackEngines\AndroidPlayer\SDK\platform-tools\adb.exe"
if ($Scrcpy -and (Test-Path (Join-Path (Split-Path $Scrcpy) "adb.exe"))) { $Adb = Join-Path (Split-Path $Scrcpy) "adb.exe" }

# Arduino boards are recognised by USB vendor ID: genuine Arduino (2341, 2A03), and the USB-serial chips
# used on clones (CH340/CH9102 1A86, CP210x 10C4, FTDI 0403). Names like "USB Serial Device" are too generic.
function Find-ArduinoPort {
    $ports = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\((COM\d+)\)" })
    $dev = $ports | Where-Object { $_.PNPDeviceID -match "VID_(2341|2A03|1A86|10C4|0403)" } | Select-Object -First 1
    if (-not $dev) { $dev = $ports | Where-Object { $_.Name -match "Arduino|CH340|CH9102|CP210|FTDI" } | Select-Object -First 1 }
    if ($dev -and $dev.Name -match "\((COM\d+)\)") { return $Matches[1] }
    return $null
}

# ---------------------------------------------------------------- VR screen
# Automatic unless -Screen N is given: the screen attached to the PC. A laptop's built-in panel is only used while
# no other screen is connected; with several attached screens, the largest. Checked again every few seconds, so
# the station moves to the screen if it is plugged in or switched on after the PC started.
$script:StartedAt = Get-Date
$script:MirrorWidthGiven = $PSBoundParameters.ContainsKey("MirrorWidth")
$script:InternalKey = "-"; $script:Internal = @{}
function Get-InternalScreens($list) {
    $key = ($list | ForEach-Object { $_.DeviceName }) -join ","
    if ($key -eq $script:InternalKey) { return $script:Internal }
    $conn = @{}
    try { Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop | ForEach-Object { $conn[$_.InstanceName.ToUpper()] = [int64]$_.VideoOutputTechnology } } catch { }
    $internal = @{}
    foreach ($scr in $list) {
        $path = [MoiScreens]::MonitorPath($scr.DeviceName)
        if ($path -match '^\\\\\?\\(.+)#\{') {
            $id = $Matches[1].Replace('#', '\').ToUpper()
            $hit = $conn.Keys | Where-Object { $_.StartsWith($id) } | Select-Object -First 1
            # Built-in panels report "internal" (0x80000000), LVDS (6), embedded DisplayPort (11) or embedded UDI (13).
            if ($hit -and ($conn[$hit] -in 2147483648, 6, 11, 13)) { $internal[$scr.DeviceName] = $true }
        }
    }
    $script:InternalKey = $key; $script:Internal = $internal
    return $internal
}

function Select-VrScreen {
    $list = @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.Bounds.X }, { $_.Bounds.Y })
    if ($Screen -gt 0) {
        $pick = $list[[Math]::Max(0, [Math]::Min($Screen, $list.Count) - 1)]; $how = "set with -Screen $Screen"
    } else {
        $internal = Get-InternalScreens $list
        $attached = @($list | Where-Object { -not $internal.ContainsKey($_.DeviceName) })
        if ($SimulateLateScreen -gt 0 -and ((Get-Date) - $script:StartedAt).TotalSeconds -lt $SimulateLateScreen) { $attached = @() }
        if ($attached.Count) {
            $pick = $attached | Sort-Object { -($_.Bounds.Width * $_.Bounds.Height) }, { $_.Primary } | Select-Object -First 1
            $how = "attached screen"
        } else {
            $pick = $list | Where-Object { $_.Primary } | Select-Object -First 1
            if (-not $pick) { $pick = $list[0] }
            $how = "no attached screen yet - using the PC's own display until one is connected"
        }
    }
    $number = 1; for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].DeviceName -eq $pick.DeviceName) { $number = $i + 1 } }
    return @{ screen = $pick; number = $number; how = $how; key = "{0}|{1}" -f $pick.DeviceName, $pick.Bounds }
}

function Screen-Text {
    "screen {0}, {1}x{2} {3} ({4})" -f $script:VrChoice.number, $script:bounds.Width, $script:bounds.Height, $(if ($script:IsPortrait) { "portrait" } else { "landscape" }), $script:VrChoice.how
}

# Puts the station (and the mirror, which restarts) on the chosen screen and sets the layout for its shape.
function Apply-Screen($choice, [switch]$Quiet) {
    $script:VrChoice = $choice
    $script:bounds = $choice.screen.Bounds
    $script:IsPortrait = $Portrait -or ($script:bounds.Height -gt $script:bounds.Width)
    if (-not $Quiet) { Log ("VR screen now: " + (Screen-Text)) }
    if ($script:window -and -not $Windowed) {
        $script:window.WindowState = "Normal"
        $script:window.Left = $script:bounds.X / $dpi; $script:window.Top = $script:bounds.Y / $dpi
        $script:window.Width = $script:bounds.Width / $dpi; $script:window.Height = $script:bounds.Height / $dpi
        $script:window.WindowState = "Maximized"
    }
    # The mirror restarts on the new screen. The PC VR app (-PcApp) is moved there instead (Place-PcApp): restarting
    # it would end a visitor's film.
    if (-not $PcApp -and $script:S -and $script:S.scrcpy -and -not $script:S.scrcpy.HasExited) { try { $script:S.scrcpy.Kill() } catch { } }
}

# The headset shows both eyes side by side; the mirror shows a slice of the left eye with the same shape as the
# VR screen, so it fills it. The slice has to stay inside the lens-shaped (oval) eye image, or black corners
# show. Measured on the Focus Vision (2448 px eye): landscape at most 2224 x 1248 around (1222, 1224) - wider
# screens get a lower band, squarer ones a narrower slice; portrait at most 1056 x 1872 around (1280, 1260).
# Sizes are multiples of 16/8 for the headset's video encoder.
function Get-OneEyeCrop($serial) {
    $size = (& $Adb -s $serial shell wm size 2>$null) -join " "
    if ($size -notmatch "(\d+)x(\d+)") { return "" }
    $w = [int]$Matches[1]; $h = [int]$Matches[2]
    if ($w -lt 2 * $h - 8) { return "" }            # not a side-by-side VR display
    $eye = [int]($w / 2)
    if ($Square) { return "$($eye):$($h):0:0" }
    $a = $script:bounds.Width / $script:bounds.Height
    # Straight ahead is not the middle of the eye image: centre the slice there, narrower where the image edge is near.
    $ahead = [int]($eye * $MirrorCentre)
    $room = [int]([Math]::Floor(2 * [Math]::Min($ahead - 8, $eye - $ahead - 8) / 16) * 16)
    if ($a -ge 1) {
        $maxW = [Math]::Min([int]([Math]::Floor($eye * 0.915 / 16) * 16), $room); $maxH = [int]([Math]::Floor($maxW * 9 / 16 / 8) * 8)
        $cx = $ahead; $cy = $h / 2
        $cw = $maxW; $ch = [int]([Math]::Round($cw / $a / 8) * 8)
        if ($ch -gt $maxH) { $ch = $maxH; $cw = [int]([Math]::Round($ch * $a / 16) * 16) }
    } else {
        $maxW = [Math]::Min([int]([Math]::Floor($eye * 0.4314 / 16) * 16), $room); $maxH = [int]([Math]::Floor($maxW * 16 / 9 / 16) * 16)
        $cx = $ahead; $cy = [int]([Math]::Floor($h * 0.1324 / 2) * 2) + $maxH / 2
        $ch = $maxH; $cw = [int]([Math]::Round($ch * $a / 16) * 16)
        if ($cw -gt $maxW) { $cw = $maxW; $ch = [int]([Math]::Round($cw / $a / 8) * 8) }
    }
    $x = [Math]::Max(0, [int]([Math]::Floor(($cx - $cw / 2) / 2) * 2)); $y = [Math]::Max(0, [int]([Math]::Floor(($cy - $ch / 2) / 2) * 2))
    return "$($cw):$($ch):$($x):$($y)"
}

# Stream size (longest side) for a slice: 1280 on screens up to full-HD width (lighter on the headset), else the
# slice's full size as long as it stays around 2 megapixels - the same load as the full-HD stream.
function Get-MirrorSize($crop) {
    if ($script:MirrorWidthGiven) { return $MirrorWidth }
    if (-not $script:IsPortrait -and $script:bounds.Width -le 1920) { return 1280 }
    if ($crop -match "^(\d+):(\d+)") {
        $cw = [int]$Matches[1]; $ch = [int]$Matches[2]
        $scale = [Math]::Min(1.0, [Math]::Sqrt(2100000 / ($cw * $ch)))
        return [int]([Math]::Floor([Math]::Max($cw, $ch) * $scale / 16) * 16)
    }
    return 1920
}

# What the mirror would look like on a screen of another size (needs the headset connected).
if ($MirrorCropFor) {
    if ($MirrorCropFor -notmatch '^(\d+)x(\d+)$') { Write-Host "Use -MirrorCropFor WIDTHxHEIGHT, e.g. 3096x1290"; exit 1 }
    $script:bounds = New-Object System.Drawing.Rectangle 0, 0, ([int]$Matches[1]), ([int]$Matches[2])
    $script:IsPortrait = $Portrait -or ($script:bounds.Height -gt $script:bounds.Width)
    $hs = @(& $Adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
    if (-not $hs) { Write-Host "Connect the headset first (the slice depends on its display)."; exit 1 }
    $c = if ($Crop) { $Crop } else { Get-OneEyeCrop $hs[0] }
    Write-Host ("Screen {0}: mirror slice {1} (width:height:x:y of the headset's left eye), streamed at up to {2} px, {3} {4}bit/s {5} fps" -f $MirrorCropFor, $c, (Get-MirrorSize $c), $MirrorCodec, $MirrorBitRate, $MirrorFps)
    exit 0
}

if ($ListPorts) {
    Write-Host "Serial (COM) ports on this PC:"
    Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match "\(COM\d+\)" } | ForEach-Object { Write-Host "  $($_.Name)" }
    $auto = Find-ArduinoPort
    if ($auto) { Write-Host "Auto-detect would use: $auto" }
    else { Write-Host "Auto-detect finds no Arduino. Plug it in, or pass -SerialPort COMx (e.g. for a virtual port)." }
    Write-Host "Button texts: $($SerialCommand -replace ',', ', ') at $BaudRate baud, port $SerialPort (from $ButtonSource)"
    exit 0
}

# Shows a big number on every screen for 6 seconds: that number is what -Screen expects.
if ($IdentifyScreens) {
    $all = @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.Bounds.X }, { $_.Bounds.Y })
    $choice = Select-VrScreen
    $forms = @()
    for ($i = 0; $i -lt $all.Count; $i++) {
        $b = $all[$i].Bounds
        $isVr = $all[$i].DeviceName -eq $choice.screen.DeviceName
        Write-Host ("Screen {0}: {1} x {2}{3}{4}" -f ($i + 1), $b.Width, $b.Height, $(if ($all[$i].Primary) { "  (main screen)" } else { "" }), $(if ($isVr) { "  <- VR screen" } else { "" }))
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = "None"; $f.StartPosition = "Manual"; $f.Bounds = $b; $f.TopMost = $true
        $f.BackColor = [System.Drawing.Color]::FromArgb(14, 26, 43); $f.ShowInTaskbar = $false
        $l = New-Object System.Windows.Forms.Label
        $l.Dock = "Fill"; $l.TextAlign = "MiddleCenter"; $l.ForeColor = [System.Drawing.Color]::White
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 72, [System.Drawing.FontStyle]::Bold)
        $l.Text = "Screen $($i + 1)" + $(if ($isVr) { "`nVR screen" } else { "" })
        $f.Controls.Add($l); $f.Show(); $forms += $f
    }
    $end = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    $forms | ForEach-Object { $_.Close() }
    Write-Host ("The station will use screen {0} ({1})." -f $choice.number, $choice.how)
    Write-Host "To force another screen, start it with -Screen N (e.g. -Screen 2)."
    exit 0
}

function Get-Headset {
    if ($SimulateHeadset) { if (Test-Path $SimulateHeadset) { return "SIMULATED" } else { return $null } }
    if ($PcApp) { if ($S.scrcpy -and -not $S.scrcpy.HasExited) { return "PC app" } else { return $null } }
    if ($S.poller) { $h = $S.poller.Headset; if ($h) { return $h } else { return $null } }
    $list = @(& $Adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0] })
    if ($Serial) { if ($list -contains $Serial) { return $Serial } else { return $null } }
    if ($list.Count -gt 0) { return $list[0] }
    return $null
}

# Only one station at a time: a second copy (Start icon clicked twice, or clicked while the autostart copy
# is running) would fight the first over the button and the mirror.
$script:SingleInstance = New-Object System.Threading.Mutex($false, "Local\MOIVisitorStation")
if (-not $script:SingleInstance.WaitOne(0)) {
    Write-Host "The VR station is already running."
    return
}

$vk = [int]([System.Windows.Forms.Keys]$TriggerKey)
# WPF positions in device-independent units; Windows reports pixels.
$dpi = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / [System.Windows.SystemParameters]::PrimaryScreenWidth
# Sets $bounds (where the station and mirror go) and $IsPortrait (tall layout); the mirror slice follows its shape.
Apply-Screen (Select-VrScreen) -Quiet

# ---------------------------------------------------------------- window
$window = New-Object System.Windows.Window
$window.Title = "MOI Visitor Station"
$window.Background = [System.Windows.Media.Brushes]::Black
$window.WindowStartupLocation = "Manual"
if ($Windowed) {
    $window.Left = 80; $window.Top = 80; $window.Width = 960; $window.Height = 540
    if ($IsPortrait) { $window.Left = 400; $window.Top = 20; $window.Width = 405; $window.Height = 720 }
} else {
    $window.WindowStyle = "None"; $window.ResizeMode = "NoResize"; $window.Topmost = $true
    $window.Left = $bounds.X / $dpi; $window.Top = $bounds.Y / $dpi
    $window.Width = $bounds.Width / $dpi; $window.Height = $bounds.Height / $dpi
}

$grid = New-Object System.Windows.Controls.Grid
$media = New-Object System.Windows.Controls.MediaElement
$media.LoadedBehavior = "Manual"; $media.UnloadedBehavior = "Stop"
# Whole video with bars when its shape differs from the screen; -IntroFill crops it to fill the screen instead.
$media.Stretch = if ($IntroFill) { "UniformToFill" } else { "Uniform" }
$cover = New-Object System.Windows.Shapes.Rectangle
$cover.Fill = [System.Windows.Media.Brushes]::Black
$text = New-Object System.Windows.Controls.TextBlock
$text.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(200, 215, 255))
$text.FontSize = 56; $text.FontFamily = "Segoe UI"; $text.TextAlignment = "Center"; $text.TextWrapping = "Wrap"
$text.HorizontalAlignment = "Center"; $text.VerticalAlignment = "Center"
$status = New-Object System.Windows.Controls.TextBlock
$status.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(70, 80, 100))
$status.FontSize = 14; $status.Margin = "12"; $status.HorizontalAlignment = "Left"; $status.VerticalAlignment = "Bottom"
[void]$grid.Children.Add($media); [void]$grid.Children.Add($cover); [void]$grid.Children.Add($text); [void]$grid.Children.Add($status)
# Visitors see only the picture: the status line is for staff/testing, and the mouse pointer is hidden.
if (-not $Windowed -and -not $ShowStatus) { $status.Visibility = "Collapsed" }
if (-not $Windowed) { $window.Cursor = [System.Windows.Input.Cursors]::None }
# Text scales with the screen, so it looks the same on a 1080p monitor and a 4K TV.
$window.Add_SizeChanged({
    $text.FontSize = [Math]::Max(20, [Math]::Min($window.ActualHeight * 0.065, $window.ActualWidth * 0.06))
    $status.FontSize = [Math]::Max(10, [Math]::Min($window.ActualHeight * 0.016, $window.ActualWidth * 0.012))
})
$window.Content = $grid
if (-not $Windowed) { $window.Add_Loaded({ $window.WindowState = "Maximized" }) }

# ---------------------------------------------------------------- state machine
# Film playing and the headset off this long without the headset app ending the film (it normally does after
# about 10 s): back to waiting anyway.
$FilmOffFallback = 30
$S = @{
    state = ""; since = [DateTime]::Now; allowClose = $false
    headset = $null; scrcpy = $null; filmStarted = $false; filmSince = $null; offSince = $null; goneSince = $null
    mirrorShown = $false; stationCheck = [DateTime]::MinValue; coveredKey = ""; coveredAt = [DateTime]::MinValue; statusAt = [DateTime]::MinValue
    pcAppStarted = [DateTime]::MaxValue; pcAppNextStart = [DateTime]::MinValue; pcAppPlaced = 0; pcAppExitSeen = $false
    vrWorn = $null; vrWornAt = [DateTime]::MinValue; vrState = ""; vrLogPos = [long]0; vrLogHead = ""; vrStateLogged = $false
    appWorn = $null; appWornAt = [DateTime]::MinValue; wornNote = ""
    prox = $null; proxReading = $null; proxWorn = $null; proxProblem = ""; proxStarted = [DateTime]::MinValue
    appSoundOn = $null; appSoundPid = 0; appSoundError = $false
    watcher = New-Object MoiLogWatcher; worn = $null; paused = $null; status = $null; statusRaw = ""; serial = New-Object MoiSerial; serialNextTry = [DateTime]::MinValue; serialOpenedAt = [DateTime]::MinValue; introStarted = $false; warming = $false; warmStart = [DateTime]::MinValue; warmOpenedAt = $null; rendered = $false; mirrorCheck = [DateTime]::MinValue; screenCheck = [DateTime]::Now; appNextCheck = [DateTime]::MinValue; simSent = $false; lastCheck = [DateTime]::MinValue; started = [DateTime]::Now; autoPressed = $false
}

$LogDir = Join-Path $PSScriptRoot "logs"
try { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null } catch { }
$LogFile = Join-Path $LogDir ("station-{0:yyyy-MM-dd}.log" -f (Get-Date))
function Log($m) {
    $line = "{0:HH:mm:ss}  {1}" -f (Get-Date), $m
    Write-Host $line
    # Shared for reading (staff or a test may have the log open); a busy file is retried, not skipped.
    for ($try = 0; $try -lt 3; $try++) {
        try {
            $fs = [IO.File]::Open($LogFile, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
            $sw = New-Object IO.StreamWriter($fs, (New-Object Text.UTF8Encoding($true)))
            $sw.WriteLine($line); $sw.Dispose()
            return
        } catch { Start-Sleep -Milliseconds 25 }
    }
}

# The intro is opened once and kept loaded. Measured on screen: the first play of a freshly opened video shows
# its first frame and then does not move for several seconds while the sound runs; a second play of a loaded
# video is smooth from the first frame. So whenever "Press the button" is showing, the intro is played silently
# for a moment underneath a black cover and stopped again, and every visitor gets that smooth second play.
# It must really be drawn during the warm-up, just covered: warming it up while Hidden (or transparent) does
# not help. And never give the player a command while no video is loaded - it keeps the command and applies it
# to the next video it opens (a Stop at start-up made the first intro stop and restart).
function Start-WarmUp {
    if (-not (Test-Path $Intro)) { return }
    $uri = New-Object System.Uri((Resolve-Path $Intro).Path)
    $cover.Visibility = "Visible"; $media.Visibility = "Visible"; $media.Opacity = 1; $media.IsMuted = $true
    $S.warmStart = [DateTime]::Now; $S.warmOpenedAt = $null; $S.warming = $true
    if ($media.Source -and $media.Source.AbsoluteUri -eq $uri.AbsoluteUri) { $S.warmOpenedAt = [DateTime]::Now }
    else { $media.Source = $uri }
    $media.Play()
}

function Finish-WarmUp {
    $S.warming = $false
    $media.Stop()
    if ($IntroSkip -gt 0) { $media.Position = [TimeSpan]::FromSeconds($IntroSkip) }
    Log "intro ready"
}

function Enter-State($name) {
    $S.state = $name; $S.since = [DateTime]::Now
    Log "-> $name"
    switch ($name) {
        "Waiting" {
            $text.Text = $WaitingText; $text.Visibility = "Visible"
            $cover.Visibility = "Visible"
            Show-Window
            if ($S.rendered) { Start-WarmUp }
        }
        "Intro" {
            if (Test-Path $Intro) {
                $uri = New-Object System.Uri((Resolve-Path $Intro).Path)
                if (-not $media.Source -or $media.Source.AbsoluteUri -ne $uri.AbsoluteUri) { $media.Source = $uri }
                if ($S.warming) {
                    # Pressed during the warm-up: start from the beginning, no need to finish warming up.
                    $S.warming = $false
                    $media.Position = [TimeSpan]::FromSeconds($IntroSkip)
                    Log "button pressed during the intro warm-up"
                }
                $media.IsMuted = $false; $media.Opacity = 1; $media.Visibility = "Visible"
                $text.Visibility = "Collapsed"; $cover.Visibility = "Collapsed"
                $media.Play()
                $S.introStarted = $false
            } else {
                Log "No intro video at $Intro - skipping"
                Enter-State "Wear"
            }
        }
        "Wear" {
            # Keep the intro loaded (see Start-WarmUp): stop it and put the cover back.
            $S.warming = $false
            if ($media.Source) { $media.Stop() }
            $media.IsMuted = $true; $cover.Visibility = "Visible"
            $text.Text = $WearText; $text.Visibility = "Visible"
            $S.filmStarted = $false; $S.offSince = $null
            # Whether it is already on is decided on the next headset reading (none are taken during the intro).
        }
        "Mirror" {
            $S.filmStarted = $false; $S.filmSince = $null; $S.offSince = $null; $S.goneSince = $null
            $S.mirrorShown = $false; $S.mirrorCheck = [DateTime]::MinValue
        }
    }
}

function Show-Window {
    try { if ($S.scrcpy -and -not $S.scrcpy.HasExited) { $S.scrcpy.Refresh(); [MoiWin]::Lower($S.scrcpy.MainWindowHandle) } } catch { }
    if (-not $window.IsVisible) { $window.Show() }
    if (-not $Windowed) { $window.Topmost = $false; $window.Topmost = $true }
    [void]$window.Activate()
}

# What covered the visitor screen goes in the log once per culprit and minute, not every second.
function Log-Covered($topPid, $what) {
    $who = try { (Get-Process -Id $topPid -ErrorAction Stop).ProcessName } catch { "pid $topPid" }
    if ("$what|$who" -ne $S.coveredKey -or ([DateTime]::Now - $S.coveredAt).TotalSeconds -ge 60) {
        Log "$what was covered by '$who' - bringing it back to the front"
        $S.coveredKey = "$what|$who"; $S.coveredAt = [DateTime]::Now
    }
}


# -SimulateHeadset: a borderless window in a process of its own plays the mirror. Like scrcpy's, its window only
# appears a moment after the start.
function Start-StandInMirror {
    $code = @"
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class D { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[void][D]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Start-Sleep -Milliseconds 1200
`$f = New-Object System.Windows.Forms.Form
`$f.FormBorderStyle = 'None'; `$f.StartPosition = 'Manual'; `$f.Text = 'MOI headset (simulated)'
`$f.Bounds = New-Object System.Drawing.Rectangle $($bounds.X), $($bounds.Y), $($bounds.Width), $($bounds.Height)
`$f.BackColor = [System.Drawing.Color]::DarkGreen
`$l = New-Object System.Windows.Forms.Label
`$l.Dock = 'Fill'; `$l.TextAlign = 'MiddleCenter'; `$l.ForeColor = [System.Drawing.Color]::White
`$l.Font = New-Object System.Drawing.Font('Segoe UI', 40); `$l.Text = 'SIMULATED HEADSET MIRROR'
`$f.Controls.Add(`$l)
[System.Windows.Forms.Application]::Run(`$f)
"@
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand " + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $S.scrcpy = [System.Diagnostics.Process]::Start($psi)
    Log "stand-in mirror started (simulated headset)"
}

# PC VR demo: the app itself plays the mirror's part ($S.scrcpy holds its process). Started here, or an already
# running one is taken over; restarted if it closes, with a pause in between so an app that fails at start isn't
# restarted in a loop.
function Ensure-PcApp {
    if ($S.scrcpy -and -not $S.scrcpy.HasExited) { return $true }
    # The app closed or crashed: say so once, with its exit code, and give the VR runtime a few seconds to let go
    # of the old session before the next start. (Seen on the dev laptop: SteamVR's vrclient_x64.dll crashing the
    # app around headset standby changes; the station brought it back each time.)
    if ($S.scrcpy -and -not $S.pcAppExitSeen) {
        $S.pcAppExitSeen = $true
        $code = try { $S.scrcpy.ExitCode } catch { "?" }
        $crash = "$code" -match '^-?\d+$' -and [int64]$code -ne 0
        Log ("VR app closed (exit code {0}){1} - starting it again in 5 s" -f $code, $(if ($crash) { " - a crash; details in Windows' Application event log" } else { "" }))
        $S.pcAppNextStart = [DateTime]::Now.AddSeconds(5)
        return $false
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($PcApp)
    $running = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { try { -not $_.HasExited -and $_.Path -eq $PcApp } catch { $false } } | Select-Object -First 1
    if ($running) {
        $S.scrcpy = $running; $S.pcAppStarted = $running.StartTime
        Log "VR app already running on this PC (pid $($running.Id)) - using it"
        return $true
    }
    if ([DateTime]::Now -lt $S.pcAppNextStart) { return $false }
    $S.pcAppNextStart = [DateTime]::Now.AddSeconds(10)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PcApp
    $psi.WorkingDirectory = Split-Path $PcApp
    # Borderless window the size of the VR screen (Place-PcApp puts it on it).
    $extra = $PcAppArgs
    if ($PcFilm) { $extra = "-film `"$PcFilm`" $extra" }
    $psi.Arguments = ("-screen-fullscreen 0 -popupwindow -screen-width {0} -screen-height {1} {2}" -f $bounds.Width, $bounds.Height, $extra).Trim()
    $psi.UseShellExecute = $false
    # VIVE Hub adds four OpenXR add-on layers (hand, face, passthrough, tracker) to every VR app. The app uses none
    # of them, and on one PC the face-tracking one stood in for the headset itself ("Vive SRanipal", no tracking,
    # no wear sensor). So they are switched off for the app - each layer names its own off switch.
    if (-not $KeepViveLayers) {
        foreach ($v in "DISABLE_XR_APILAYER_VIVE_HAND_TRACKING_1", "DISABLE_XR_APILAYER_VIVE_FACIAL_TRACKING_1", "DISABLE_XR_APILAYER_VIVE_MR_1", "DISABLE_XR_APILAYER_VIVE_XRTRACKER_1") { $psi.EnvironmentVariables[$v] = "1" }
    }
    $S.scrcpy = [System.Diagnostics.Process]::Start($psi)
    $S.pcAppStarted = [DateTime]::Now; $S.pcAppExitSeen = $false
    Log ("VR app started on this PC: {0} {1}" -f (Split-Path $PcApp -Leaf), $extra.Trim())
    return $true
}

# A one-word command for the app (it reads and deletes command.txt in its own folder every 0.5 s):
#   reset = back to the START screen, reload = reload the app. Written whole, then renamed into place.
function Send-AppCommand($cmd, $why) {
    if ($PcApp) {
        $p = Join-Path (Split-Path $PcStatusFile) "command.txt"
        try { [IO.File]::WriteAllText("$p.tmp", $cmd); Move-Item "$p.tmp" $p -Force } catch { Log "could not send '$cmd' to the app: $($_.Exception.Message)"; return }
    } elseif ($S.headset -and -not $SimulateHeadset) {
        $f = "/sdcard/Android/data/$AppPackage/files/command.txt"
        & $Adb -s $S.headset shell "echo $cmd > $f.tmp && mv $f.tmp $f" 2>&1 | Out-Null
    } else { return }
    Log "app told to $cmd ($why)"
}

# PC VR demo (-OffRestartsApp): close the app and start it again at once, so the next visitor gets a fresh START.
function Restart-PcApp($why) {
    if ($S.scrcpy -and -not $S.scrcpy.HasExited) {
        try { $S.scrcpy.Kill(); [void]$S.scrcpy.WaitForExit(2000) } catch { }
    }
    $S.pcAppExitSeen = $true; $S.pcAppNextStart = [DateTime]::MinValue
    Log "VR app restarting ($why)"
}

# PC demo: the app's sound only while the headset is worn. Windows keeps a volume per program (the volume mixer); the
# station mutes and unmutes the app's own entries there, on every playback device, so no app change is needed and the
# station's intro keeps its own sound. Core Audio COM: devices -> session manager -> the app's sessions -> SetMute.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class MoiAppAudio {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
    }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }
    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        [PreserveSig] int GetAudioSessionControl(IntPtr groupingParam, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr groupingParam, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }
    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session);
    }
    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr context);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr context);
        [PreserveSig] int GetGroupingParam(out Guid param);
        [PreserveSig] int SetGroupingParam(ref Guid param, IntPtr context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out uint pid);
    }
    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume {
        [PreserveSig] int SetMasterVolume(float level, ref Guid context);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute(int mute, ref Guid context);
        [PreserveSig] int GetMute(out int mute);
    }
    // Mutes or unmutes every sound entry of the process on every playback device. Returns how many entries it found
    // (0 = the program has not played anything yet: Windows creates its entry with the first sound).
    public static int SetMute(int pid, bool mute) {
        int found = 0;
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDeviceCollection devices;
        if (enumerator.EnumAudioEndpoints(0 /* render */, 1 /* active */, out devices) != 0) return 0;
        int count; devices.GetCount(out count);
        Guid managerId = typeof(IAudioSessionManager2).GUID, ctx = Guid.Empty;
        for (int d = 0; d < count; d++) {
            IMMDevice device; if (devices.Item(d, out device) != 0) continue;
            object o; if (device.Activate(ref managerId, 23 /* CLSCTX_ALL */, IntPtr.Zero, out o) != 0) continue;
            IAudioSessionEnumerator sessions; if (((IAudioSessionManager2)o).GetSessionEnumerator(out sessions) != 0) continue;
            int n; sessions.GetCount(out n);
            for (int i = 0; i < n; i++) {
                object s; if (sessions.GetSession(i, out s) != 0) continue;
                uint sp; if (((IAudioSessionControl2)s).GetProcessId(out sp) != 0 || sp != (uint)pid) continue;
                found++;
                var v = (ISimpleAudioVolume)s;
                int now; v.GetMute(out now);
                if ((now != 0) != mute) v.SetMute(mute ? 1 : 0, ref ctx);
            }
        }
        return found;
    }
}
"@

# Every second: the app is heard only in the headset view (Mirror) while the headset is not known to be off. At "Press
# the button", during the intro and "Please put on the headset" it is silent - the intro has the room to itself.
function Update-PcAppSound {
    if (-not $PcApp -or $PcAppSoundAlways) { return }
    if (-not $S.scrcpy -or $S.scrcpy.HasExited) { $S.appSoundPid = 0; return }
    $on = $S.state -eq "Mirror" -and $S.worn -ne $false
    $n = 0
    try { $n = [MoiAppAudio]::SetMute($S.scrcpy.Id, -not $on) }
    catch { if (-not $S.appSoundError) { $S.appSoundError = $true; Log "app sound: could not set it ($($_.Exception.Message))" } }
    if ($n -gt 0 -and ($on -ne $S.appSoundOn -or $S.appSoundPid -ne $S.scrcpy.Id)) {
        $S.appSoundOn = $on; $S.appSoundPid = $S.scrcpy.Id
        Log $(if ($on) { "app sound on (headset on)" } else { "app sound off (headset not on)" })
    }
}

# PC VR demo: the app's window exactly on the VR screen. Checked every second: the app may still resize itself while
# it starts, and the VR screen can change.
function Place-PcApp {
    if (-not $S.scrcpy -or $S.scrcpy.HasExited) { return }
    $h = [IntPtr]::Zero
    try { $S.scrcpy.Refresh(); $h = $S.scrcpy.MainWindowHandle } catch { }
    if ($h -eq [IntPtr]::Zero) { return }
    if ([MoiWin]::IsAt($h, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)) { return }
    [MoiWin]::Place($h, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    if ($S.pcAppPlaced -ne $S.scrcpy.Id) { $S.pcAppPlaced = $S.scrcpy.Id; Log ("VR app window placed on the VR screen ({0}x{1})" -f $bounds.Width, $bounds.Height) }
}

function Ensure-Scrcpy {
    if ($PcApp) { return Ensure-PcApp }
    if (-not $S.headset) { return $false }
    if ($S.scrcpy -and -not $S.scrcpy.HasExited) { return $true }
    if ($SimulateHeadset) { Start-StandInMirror; return $true }
    if (-not $Scrcpy) { return $false }
    # Kept light on purpose: the headset encodes this stream itself, on top of tracking and the app.
    $c = $Crop
    if (-not $c) { $c = Get-OneEyeCrop $S.headset }
    $ms = Get-MirrorSize $c
    $a = @("-s", $S.headset, "--no-control", "--max-size", "$ms", "--max-fps", "$MirrorFps", "--video-bit-rate", $MirrorBitRate,
              "--video-codec=$MirrorCodec",
              "--window-title", "`"MOI headset`"", "--window-borderless",
              "--window-x", "$($bounds.X)", "--window-y", "$($bounds.Y)",
              "--window-width", "$($bounds.Width)", "--window-height", "$($bounds.Height)")
    if (-not $MirrorAudio) { $a += "--no-audio" }
    if ($c) { $a += @("--crop", $c) }
    # Full screen gives black borders when the headset picture and the screen differ in shape, and keeps the
    # taskbar off the mirror. (scrcpy does not minimise itself on focus loss.)
    if (-not $Windowed) { $a += "--fullscreen" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Scrcpy
    $psi.Arguments = ($a -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $S.scrcpy = [System.Diagnostics.Process]::Start($psi)
    Log ("mirror started for {0}: headset view slice {1}, streamed at up to {2} px, {3} {4}bit/s {5} fps" -f $S.headset, $(if ($c) { $c } else { "none" }), $ms, $MirrorCodec, $MirrorBitRate, $MirrorFps)
    return $true
}

# PC VR demo: SteamVR's own state, a second "headset worn" signal next to the app's wear sensor. SteamVR appends a line
# to its log whenever the headset goes idle or comes back:
#   Tue Sep 29 2026 19:12:32.270 [Info] - [System] Unknown Transition from 'SteamVRSystemState_Ready' to 'SteamVRSystemState_Standby'.
# Standby = nobody is using the headset; Ready = in use (or just picked up). The other states (Startup, Connecting,
# NotReady, Shutdown...) only come while SteamVR starts, looks for the headset or closes: no answer then.
# Read every second from where the last read stopped (the log keeps growing across SteamVR restarts).
function Read-SteamVrState {
    if (-not $SteamVrLog) { return }
    $prev = $S.vrWorn
    if (-not (Get-Process vrserver -ErrorAction SilentlyContinue)) {
        # SteamVR not running: its log only tells about an earlier run.
        $S.vrWorn = $null; $S.vrState = "not running"
    }
    else {
        try {
            $fs = [IO.File]::Open($SteamVrLog, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            try {
                # A different first line (or a shorter file): the log was replaced - read it from the start.
                $buf = New-Object byte[] 64
                $n = $fs.Read($buf, 0, 64)
                $head = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
                if ($head -ne $S.vrLogHead -or $fs.Length -lt $S.vrLogPos) { $S.vrLogHead = $head; $S.vrLogPos = [long]0 }
                # The log grows for as long as the kiosk runs: the latest 1 MB is plenty for the current state.
                if ($fs.Length - $S.vrLogPos -gt 1MB) { $S.vrLogPos = $fs.Length - 1MB }
                if ($fs.Length -gt $S.vrLogPos) {
                    [void]$fs.Seek($S.vrLogPos, [IO.SeekOrigin]::Begin)
                    $bytes = New-Object byte[] ($fs.Length - $S.vrLogPos)
                    $got = 0
                    while ($got -lt $bytes.Length) { $r = $fs.Read($bytes, $got, $bytes.Length - $got); if ($r -le 0) { break }; $got += $r }
                    # Whole lines only: a line still being written is read next time.
                    $end = if ($got -gt 0) { [Array]::LastIndexOf($bytes, [byte]10, $got - 1) } else { -1 }
                    if ($end -ge 0) {
                        $S.vrLogPos += $end + 1
                        $text = [Text.Encoding]::UTF8.GetString($bytes, 0, $end + 1)
                        $rx = "(?m)^(\w{3} \w{3} \d{2} \d{4} \d{2}:\d{2}:\d{2}\.\d{3}) .*Transition from 'SteamVRSystemState_\w+' to 'SteamVRSystemState_(\w+)'"
                        foreach ($m in [regex]::Matches($text, $rx)) {
                            $S.vrState = $m.Groups[2].Value
                            $S.vrWorn = if ($S.vrState -eq "Ready") { $true } elseif ($S.vrState -eq "Standby") { $false } else { $null }
                            $at = [DateTime]::MinValue
                            $ok = [DateTime]::TryParseExact($m.Groups[1].Value, "ddd MMM dd yyyy HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$at)
                            $S.vrWornAt = if ($ok) { $at } else { [DateTime]::Now }
                        }
                    }
                }
            }
            finally { $fs.Dispose() }
        }
        catch { }   # log missing or busy: next second
    }
    if ($S.vrWorn -ne $prev -or -not $S.vrStateLogged) {
        $S.vrStateLogged = $true
        Log ("SteamVR: {0}" -f $(if ($S.vrState) { $S.vrState } else { "no state in its log yet" }))
    }
}

# PC demo: which adb reads the proximity sensor. The one already running as the adb server (VIVE Hub's, Unity's, scrcpy's
# all speak adb protocol 41, so any of them works with any server - taking the same program just avoids surprises), else
# VIVE Hub's own copy (installed on every PC-demo PC), else the one next to scrcpy / in Unity, else one on PATH.
function Find-ProximityAdb {
    $running = $null
    try { $running = @(Get-CimInstance Win32_Process -Filter "Name='adb.exe'" -ErrorAction Stop | Where-Object { $_.ExecutablePath } | Select-Object -ExpandProperty ExecutablePath)[0] } catch { }
    if ($running -and (Test-Path $running)) { return $running }
    foreach ($c in @((Join-Path $env:ProgramFiles "VIVE Hub\VIVE Hub\CommonTools\ADB\adb.exe"), (Join-Path $env:ProgramFiles "VIVE Hub\VIVE Business Streaming\CommonTools\ADB\adb.exe"), $Adb)) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# PC demo: the proximity sensor's answer - $true worn, $false taken off, $null no reading (not started, no adb, no allowed
# headset, or the last reading is older than 3 s). Logs when the reading comes and goes, and every change.
function Get-ProximityWorn {
    if (-not $S.prox) { return $null }
    $p = $S.prox
    $worn = if ($p.State -ge 0 -and ([DateTime]::Now - $p.At).TotalSeconds -le 3) { $p.State -eq 1 } else { $null }
    $reading = $null -ne $worn
    # The first seconds after the start the reader is still finding the headset: no "no reading" note for that.
    if (-not $reading -and $null -eq $S.proxReading -and ([DateTime]::Now - $S.proxStarted).TotalSeconds -lt 15) { return $null }
    if ($reading -ne $S.proxReading) {
        $S.proxReading = $reading
        if ($reading) { Log "headset proximity sensor: read over USB ($($p.Serial)) - it decides worn / taken off" }
        else { $S.proxProblem = $p.Problem; Log ("headset proximity sensor: no reading - the app's sensor and SteamVR decide" + $(if ($p.Problem) { " ($($p.Problem))" } else { "" })) }
    }
    elseif (-not $reading -and $p.Problem -and $p.Problem -ne $S.proxProblem) { $S.proxProblem = $p.Problem; Log "headset proximity sensor: $($p.Problem)" }
    if ($reading -and $worn -ne $S.proxWorn) { $S.proxWorn = $worn; Log $(if ($worn) { "headset proximity sensor: worn" } else { "headset proximity sensor: taken off" }) }
    return $worn
}

# Reads the app's one-line status file on the headset (written by the app on every change):
#   state=Idle worn=True paused=False films=3
# and turns changes into the same events the station reacts to. (The headset's log buffer is too small
# to rely on: HTC services overwrite it within minutes.)
function Poll-HeadsetStatus {
    if (-not $S.headset) { return }
    if ($PcApp) {
        # A status file older than the running app is left over from an earlier run.
        $f = Get-Item $PcStatusFile -ErrorAction SilentlyContinue
        if (-not $f -or $f.LastWriteTime -lt $S.pcAppStarted) { return }
        $raw = ((Get-Content $PcStatusFile -ErrorAction SilentlyContinue) -join " ").Trim()
    }
    elseif ($SimulateHeadset) { $raw = ((Get-Content $SimulateHeadset -ErrorAction SilentlyContinue) -join " ").Trim() }
    else {
        # From the background reader (only while the app runs: a status file left over from an earlier run, e.g.
        # "worn=True", must not count). A reading older than a few seconds means the reads are failing: no status.
        $raw = $S.poller.Status
        if (([DateTime]::Now - $S.poller.StatusAt).TotalSeconds -gt 6) { $raw = "" }
    }
    if ($raw -notmatch "state=(\w+) worn=(\w+) paused=(\w+) films=(\d+)") {
        if ($S.status) { $S.status = $null; $S.statusRaw = ""; $S.worn = $null; $S.paused = $null; Log "headset app not running - no status" }
        return
    }
    $now = @{ state = $Matches[1]; worn = $Matches[2]; paused = $Matches[3]; films = [int]$Matches[4] }
    $prev = $S.status
    $S.status = $now; $S.statusAt = [DateTime]::Now
    # worn=Unknown: on the headset, not put on since the app started, so nobody is wearing it. On a PC runtime
    # (-PcApp) it can also mean the runtime doesn't report wearing at all, so there it counts as "no signal".
    # "paused" is NOT "taken off": the headset also pauses the app for its own screens (lens/IPD adjustment,
    # boundary) while someone wears it.
    $appWorn = if ($now.worn -eq "True") { $true } elseif ($now.worn -eq "False" -or -not $PcApp) { $false } else { $null }
    if ($PcApp) {
        # PC VR demo: the headset's proximity sensor decides whenever it can be read (Get-ProximityWorn). Without it, two
        # fallback signals - the app's wear sensor and SteamVR's own state (Read-SteamVrState). Both stay "worn" until the
        # headset falls asleep, 3 minutes after it is put down. SteamVR's "Ready" also comes when staff just pick the
        # headset up by hand, so it only decides when the app has no sensor at all; its "Standby" after the app last said
        # "worn" always counts (a sensor that is missing or stuck on "worn").
        if ($appWorn -ne $S.appWorn -or -not $prev) { $S.appWorn = $appWorn; $S.appWornAt = [DateTime]::Now }
        $prox = Get-ProximityWorn
        if ($null -ne $prox) { $worn = $prox; $note = "" }
        else {
            $worn = if ($null -eq $S.appWorn) { $S.vrWorn }
                    elseif ($S.appWorn -and $S.vrWorn -eq $false -and $S.vrWornAt -gt $S.appWornAt) { $false }
                    else { $S.appWorn }
            $note = if ($null -eq $S.appWorn -and $null -ne $S.vrWorn) { "worn/not worn from SteamVR ($($S.vrState)): the app reports no wear sensor" }
                    elseif ($S.appWorn -and $worn -eq $false) { "headset counted as off: SteamVR went to Standby after the app last said worn" }
                    else { "" }
        }
        if ($note -ne $S.wornNote) { $S.wornNote = $note; if ($note) { Log $note } }
        $S.worn = $worn
    }
    else { $S.worn = $appWorn }
    $S.paused = $now.paused -eq "True"
    if ($raw -eq $S.statusRaw) { return }
    $S.statusRaw = $raw
    Log "headset: $raw"
    if (-not $prev) { return }   # first read after connecting: the starting point
    # "films" counts starts, so a film that began and ended between two reads is still seen.
    if ($now.films -gt $prev.films) { Handle-Headset-Line "[MOI] STATE Playing" }
    if ($now.state -eq "Idle" -and ($prev.state -ne "Idle" -or $now.films -gt $prev.films)) { Handle-Headset-Line "[MOI] STATE Idle" }
}

# Being worn or not is read as it is (Poll-HeadsetStatus, the Wear and Mirror steps); film start and end are events.
function Handle-Headset-Line($line) {
    $i = $line.IndexOf("[MOI] ")
    if ($i -lt 0) { return }
    $msg = $line.Substring($i + 6).Trim()
    switch -Regex ($msg) {
        "^STATE Playing" {
            # PC demo: the proximity sensor says nobody wears the headset, yet the film started - not a visitor (an app
            # that starts on a look can be set off by a headset standing on a table, facing START). The app goes straight
            # back to START and the screen stays on "Press the button".
            if ($PcApp -and ($S.state -in @("Wear", "Waiting", "Intro")) -and ((Get-ProximityWorn) -eq $false)) {
                Log "film started while nobody wears the headset (proximity sensor) - ignored"
                Send-AppCommand "reset" "film started with the headset off"
                return
            }
            # Somebody pressed START inside the headset: they are in it, whatever the wear sensor says - so also from
            # "Press the button" or the intro (which is stopped by the Wear step).
            if ($S.state -in "Wear", "Waiting", "Intro") {
                Log "START pressed in the headset"
                if ($S.state -eq "Intro") { Enter-State "Wear" }
                Enter-State "Mirror"
            }
            $S.filmStarted = $true; $S.filmSince = [DateTime]::Now; Log "film started"
        }
        "^STATE Idle" {
            if ($S.state -eq "Mirror" -and $S.filmStarted) {
                Log $(if ($S.worn -eq $false) { "film stopped by the headset (taken off)" } else { "film finished" })
                Enter-State "Waiting"
            }
        }
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(50)
$timer.Add_Tick({
  try {
    $now = [DateTime]::Now

    # Button key (collected on its own thread, see MoiKeys) + test auto-press.
    $pressed = [MoiKeys]::TakePresses() -gt 0
    if ($pressed) { Log "button: key $TriggerKey" }
    if ($AutoPressAfter -gt 0 -and -not $S.autoPressed -and ($now - $S.started).TotalSeconds -ge $AutoPressAfter) { $S.autoPressed = $true; $pressed = $true }
    if ($pressed -and $S.state -eq "Waiting") { Enter-State "Intro" }

    # Arduino button over serial (+ test injection).
    if ($SimulateSerialAfter -gt 0 -and -not $S.simSent -and ($now - $S.started).TotalSeconds -ge $SimulateSerialAfter) {
        $S.simSent = $true; $S.serial.Lines.Enqueue("START")
    }
    $sl = $null
    while ($S.serial.Lines.TryDequeue([ref]$sl)) {
        if (-not $sl) { continue }
        if (([DateTime]::Now - $S.serialOpenedAt).TotalSeconds -lt $SerialBootIgnore) { Log "serial (board start-up, ignored): $sl"; continue }
        Log "serial: $sl"
        if ($sl -match "RESET") { Enter-State "Waiting"; continue }
        $isStart = -not $SerialCommand
        foreach ($cmd in ($SerialCommand -split ",")) { if ($cmd.Trim() -and $sl.ToUpperInvariant().Contains($cmd.Trim().ToUpperInvariant())) { $isStart = $true } }
        if ($isStart -and $S.state -eq "Waiting") { Enter-State "Intro" }
    }

    # Staff quit.
    if ([MoiKeys]::QuitRequested) { $S.allowClose = $true; $window.Close(); return }
    if ($QuitAfter -gt 0 -and ($now - $S.started).TotalSeconds -ge $QuitAfter) { $S.allowClose = $true; $window.Close(); return }

    # Every second: headset connection, status, mirror process, button box. The headset itself is read on a
    # background thread (MoiHeadsetPoller) or from a file (PC demo), so this costs nothing during the intro; the
    # calls that do go out to the headset or search the PC (app start, button-box search, mirror start) wait
    # until the intro is over - they briefly hold up the thread that also drives the intro video.
    if (($now - $S.lastCheck).TotalSeconds -ge 1) {
        $S.lastCheck = $now
        $introNow = $S.state -eq "Intro"
        if (-not $Windowed -and ($now - $S.screenCheck).TotalSeconds -ge 3) {
            $S.screenCheck = $now
            $c = Select-VrScreen
            if ($c.key -ne $script:VrChoice.key) { Apply-Screen $c }
        }
        $h = Get-Headset
        if ($h -ne $S.headset) {
            $S.headset = $h
            $S.status = $null; $S.statusRaw = ""; $S.worn = $null; $S.paused = $null
            if ($h) { Log "headset connected: $h" } else { Log "headset disconnected" }
        }
        if ($PcApp) { Read-SteamVrState }
        Poll-HeadsetStatus
        if ($PcApp -or -not $introNow) { [void](Ensure-Scrcpy) }
        if ($PcApp) { Place-PcApp; Update-PcAppSound }
        if (-not $NoLaunchApp -and -not $SimulateHeadset -and -not $PcApp -and -not $introNow -and $S.headset -and $now -ge $S.appNextCheck) {
            $S.appNextCheck = $now.AddSeconds(10)
            $appPid = (& $Adb -s $S.headset shell pidof $AppPackage 2>$null) -join ""
            if (-not $appPid.Trim()) {
                Log "MOI app not running on the headset - starting it"
                # Its old status file goes first: the fresh app writes a new one within seconds.
                & $Adb -s $S.headset shell "rm -f /sdcard/Android/data/$AppPackage/files/status.txt" 2>&1 | Out-Null
                & $Adb -s $S.headset shell monkey -p $AppPackage -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
            }
        }
        if ($SerialPort -ne "none" -and -not $S.serial.IsOpen -and $now -ge $S.serialNextTry -and $S.state -ne "Intro") {
            $S.serialNextTry = $now.AddSeconds(3)
            $port = $SerialPort
            if ($port -eq "auto") { $port = Find-ArduinoPort }
            if ($port) {
                if ($S.serial.Open($port, $BaudRate)) { $S.serialOpenedAt = [DateTime]::Now; Log "button connected on $port ($BaudRate baud)" }
                else {
                    $why = $S.serial.LastError
                    if ($why -match "denied|in use") { $why = "port is busy - close Hercules / Arduino Serial Monitor / other programs using $port" }
                    Log "could not open ${port}: $why"
                }
            }
        }
        $buttonText = "button: key $TriggerKey"
        if ($S.serial.IsOpen) { $buttonText = "button: $($S.serial.PortName) + key $TriggerKey" }
        elseif ($SerialPort -ne "none") { $buttonText = "button: Arduino not found (key $TriggerKey works)" }
        $mirrorText = "no mirror (scrcpy not installed)"
        if ($Scrcpy) { $mirrorText = "mirror ready" }
        if ($PcApp) { $mirrorText = "PC VR app" }
        $headsetText = "headset: not connected"
        if ($S.headset) { $headsetText = "headset: $($S.headset)" }
        $status.Text = "$headsetText   |   $mirrorText   |   $buttonText   |   $($S.state)"
    }


    # Waiting, intro, "put on the headset": the station screen must be what the visitor screen shows. (The mirror
    # runs in the background all the time, and a window that has just started can come up over the station.)
    if (-not $Windowed -and $S.state -ne "Mirror" -and $window.IsVisible -and $now -ge $S.stationCheck) {
        $S.stationCheck = $now.AddMilliseconds(250)
        $topPid = [MoiWin]::PidAt($bounds.X + [int]($bounds.Width / 2), $bounds.Y + [int]($bounds.Height / 2))
        if ($topPid -ne 0 -and $topPid -ne $PID) { Log-Covered $topPid "station screen"; Show-Window }
    }

    $inState = ($now - $S.since).TotalSeconds
    if ($S.warming) {
        if ($S.warmOpenedAt -and ($now - $S.warmOpenedAt).TotalSeconds -ge 1.5) { Finish-WarmUp }
        elseif (-not $S.warmOpenedAt -and ($now - $S.warmStart).TotalSeconds -ge 15) { $S.warming = $false; Log "intro did not open for the warm-up" }
    }
    if ($S.state -eq "Intro" -and -not $S.introStarted -and $media.Position.TotalMilliseconds -gt 0) {
        $S.introStarted = $true
        Log ("intro playing {0:N0} ms after the button" -f ($now - $S.since).TotalMilliseconds)
    }
    # Safety net: a broken intro file never reports that it finished, which left the visitor on a black screen.
    if ($S.state -eq "Intro") {
        $introLimit = if ($media.NaturalDuration.HasTimeSpan) { $media.NaturalDuration.TimeSpan.TotalSeconds - $IntroSkip + 10 } else { 0 }
        # ($inState = 0: the Wear step below starts its own clock now, instead of timing out in this same tick.)
        if (-not $S.introStarted -and $inState -ge 8) { Log "intro did not start (file broken?) - on to the headset"; Enter-State "Wear"; $inState = 0 }
        elseif ($introLimit -gt 0 -and $inState -ge $introLimit) { Log "intro did not finish in time - on to the headset"; Enter-State "Wear"; $inState = 0 }
    }
    switch ($S.state) {
        "Waiting" {
            # -MirrorWhenWorn: somebody wearing the headset gets the headset view without the button and the intro.
            # (A reading taken in this state, so a visitor still wearing it after the film keeps the view.)
            if ($MirrorWhenWorn -and $S.headset -and $S.worn -eq $true -and $S.statusAt -gt $S.since) { Log "headset put on - straight to the headset view"; Enter-State "Mirror" }
        }
        "Intro" {
            if ($MirrorWhenWorn -and $S.headset -and $S.worn -eq $true -and $S.statusAt -gt $S.since) {
                Log "headset put on during the intro - straight to the headset view"
                Enter-State "Wear"      # stops the intro
                Enter-State "Mirror"
            }
        }
        "Wear" {
            # The mirror comes up as soon as the headset is put on (or START is pressed in it: Handle-Headset-Line).
            # Only a reading taken after the intro counts: the headset is not read while the intro plays.
            if ($S.worn -eq $true -and $S.statusAt -gt $S.since) { Log "headset put on"; Enter-State "Mirror" }
            # No "worn" signal at all (headset not connected, or a PC runtime that doesn't report it): on to the
            # mirror (or "Connecting to the headset...") after a while.
            elseif ($null -eq $S.worn -and $inState -ge $WearTimeout) { Log "no worn signal from the headset - on to the mirror"; Enter-State "Mirror" }
            elseif ($inState -ge $WearGiveUp) { Log "nobody put the headset on within $WearGiveUp s"; Enter-State "Waiting" }
        }
        "Mirror" {
            $live = $S.scrcpy -and -not $S.scrcpy.HasExited
            if (-not $live) {
                $text.Text = "Connecting to the headset..."
                if (-not $window.IsVisible) { Show-Window }
            } elseif ($now -ge $S.mirrorCheck) {
                $S.mirrorCheck = $now.AddMilliseconds(250)
                $mw = [IntPtr]::Zero
                try { $S.scrcpy.Refresh(); $mw = $S.scrcpy.MainWindowHandle } catch { }
                if ($mw -eq [IntPtr]::Zero) {
                    # The mirror window opens with the first picture from the headset; the station screen stays until then.
                    $text.Text = "Connecting to the headset..."
                    if (-not $window.IsVisible) { Show-Window }
                } elseif ($window.IsVisible) {
                    # Mirror on top first, while the station window still has the focus to hand over, then the station
                    # window goes (the other way round, the desktop shows in between).
                    [void][MoiWin]::Raise($mw)
                    $window.Hide()
                    if (-not $S.mirrorShown) { $S.mirrorShown = $true; Log ("mirror on screen ({0:N1} s)" -f $inState) }
                } else {
                    # Once a second: the mirror back on top of everything, and a check of what the screen really shows.
                    $S.mirrorCheck = $now.AddSeconds(1)
                    [MoiWin]::KeepOnTop($mw)
                    $topPid = [MoiWin]::PidAt($bounds.X + [int]($bounds.Width / 2), $bounds.Y + [int]($bounds.Height / 2))
                    if ($topPid -ne 0 -and $topPid -ne $S.scrcpy.Id) { Log-Covered $topPid "mirror"; [void][MoiWin]::Raise($mw) }
                }
            }
            # Back to "Press the button" when the film is over (the headset says so: Handle-Headset-Line), when the
            # headset is unplugged or switched off, or taken off before the film. During the film the headset app
            # decides: it ends the film itself about 10 s after the headset comes off, so a visitor who lifts it for a
            # moment keeps the film and the mirror. ($FilmOffFallback: in case the app never reports the end.)
            # -OffEndsVisit / -OffRestartsApp (PC demo): off for OffReset seconds, film or not, and the app is sent back
            # to START (or restarted) as well, so the film cannot carry on for whoever puts the headset on next.
            if ($S.headset) { $S.goneSince = $null } elseif (-not $S.goneSince) { $S.goneSince = $now }
            if ($S.headset -and $S.worn -eq $false) { if (-not $S.offSince) { $S.offSince = $now } } else { $S.offSince = $null }
            $endsVisit = $OffEndsVisit -or $OffRestartsApp
            $offLimit = if ($S.filmStarted -and -not $endsVisit) { $FilmOffFallback } else { $OffReset }
            $timeFrom = if ($S.filmSince) { $S.filmSince } else { $S.since }
            if ($S.goneSince -and ($now - $S.goneSince).TotalSeconds -ge $OffReset) { Log "headset unplugged or switched off for $OffReset s"; Enter-State "Waiting" }
            elseif ($S.offSince -and ($now - $S.offSince).TotalSeconds -ge $offLimit) {
                Log "headset off for $offLimit s"
                Enter-State "Waiting"
                if ($OffRestartsApp -and $PcApp) { Restart-PcApp "headset taken off" }
                elseif ($endsVisit) { Send-AppCommand "reset" "headset taken off" }
            }
            elseif (($now - $timeFrom).TotalSeconds -ge $MirrorTimeout) { Log "mirror timeout"; Enter-State "Waiting" }
        }
    }
  } catch {
    Log "error (station keeps running): $($_.Exception.Message)"
  }
})

$media.Add_MediaOpened({
    Log ("intro loaded ({0:N0} s, {1}x{2})" -f $media.NaturalDuration.TimeSpan.TotalSeconds, $media.NaturalVideoWidth, $media.NaturalVideoHeight)
    if ($S.warming -and -not $S.warmOpenedAt) { $S.warmOpenedAt = [DateTime]::Now }
})
$media.Add_MediaEnded({
    if ($S.warming) { Finish-WarmUp }
    elseif ($S.state -eq "Intro") { Enter-State "Wear" }
})
# Event parameters must not be called $s: PowerShell names ignore case, so $s would hide the station state $S.
$media.Add_MediaFailed({
    param($src, $e)
    Log "intro failed: $($e.ErrorException.Message)"
    $S.warming = $false
    if ($S.state -eq "Intro") { Enter-State "Wear" }
})
# The first warm-up waits until the window is really on screen: the video has to be drawn to warm up.
$window.Add_ContentRendered({ $S.rendered = $true; if ($S.state -eq "Waiting" -and -not $S.warming) { Start-WarmUp } })
# A kiosk: Alt+F4 (or the window menu) does not close it. Staff close it with Ctrl+Shift+Q or the "Stop VR Station"
# icon; Windows shutting down closes it too.
$window.Add_Closing({
    param($src, $e)
    # The small test window (-Windowed) closes like any window; full screen only closes on Ctrl+Shift+Q.
    if (-not $S.allowClose -and -not $Windowed) { $e.Cancel = $true; Log "Alt+F4 ignored (Ctrl+Shift+Q closes the station)" }
})
$window.Add_Closed({
    $timer.Stop(); $S.watcher.Stop(); $S.serial.Close()
    if ($S.poller) { $S.poller.Stop() }
    if ($S.prox) { $S.prox.Stop() }
    if ($S.scrcpy -and -not $S.scrcpy.HasExited) { $S.scrcpy.Kill() }
})

# From here on the station must keep running: adb and friends print harmless notes on stderr, and any
# unexpected error is logged instead of closing the kiosk.
$ErrorActionPreference = "Continue"

Log ("VR screen: " + (Screen-Text))
Log "button: serial $SerialPort @ $BaudRate ('$SerialCommand' from $ButtonSource) + key $TriggerKey   intro: $Intro   scrcpy: $Scrcpy"
if ($PcApp) { Log $(if ($SteamVrLog) { "SteamVR state from $SteamVrLog" } else { "SteamVR state not used (-NoSteamVr)" }) }
Enter-State "Waiting"
[MoiKeys]::Watch($vk)
# The headset is read over USB on its own thread (not for the PC demo or a simulated headset).
if (-not $PcApp -and -not $SimulateHeadset) { $S.poller = New-Object MoiHeadsetPoller($Adb, $AppPackage, $Serial); $S.poller.Start() }
# PC demo: the headset's proximity sensor, also on its own thread.
if ($PcApp -and -not $NoProximity -and -not $SimulateHeadset) {
    $proxAdb = Find-ProximityAdb
    if ($proxAdb) { $S.prox = New-Object MoiProximityPoller($proxAdb); $S.proxStarted = [DateTime]::Now; $S.prox.Start(); Log "headset proximity sensor: read over USB with $proxAdb" }
    else { Log "headset proximity sensor: no adb on this PC (VIVE Hub not installed?) - the app's sensor and SteamVR decide" }
}
elseif ($PcApp) { Log "headset proximity sensor: not used (-NoProximity) - the app's sensor and SteamVR decide" }
$timer.Start()
$app = New-Object System.Windows.Application
$app.ShutdownMode = "OnMainWindowClose"
$app.Add_SessionEnding({ $S.allowClose = $true })
[void]$app.Run($window)
