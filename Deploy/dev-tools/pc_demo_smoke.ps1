$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Starts the PC demo .exe on this laptop (no VR runtime: plain window mode), checks its log and status file,
# presses START (Space) if the gaze didn't, and takes screenshots of the room and of the film.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class PD {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
[void][PD]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$sp = Split-Path $MyInvocation.MyCommand.Path
$dir = "$MoiRoot\Delivery\MOI_PC_Demo"
$data = Join-Path $env:USERPROFILE "AppData\LocalLow\GameX\MOI Promise of Safety"
$log = Join-Path $data "Player.log"; $status = Join-Path $data "status.txt"
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
function Shot($name) {
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $g.Dispose()
    $small = New-Object System.Drawing.Bitmap $bmp, ([int]($b.Width / 2)), ([int]($b.Height / 2)); $bmp.Dispose()
    $small.Save((Join-Path $sp "pcdemo_$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $small.Dispose(); "screenshot pcdemo_$name.png"
}
function Status { if (Test-Path $status) { (Get-Content $status -Raw).Trim() } else { "(no status file)" } }

"--- launcher check"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\start-pc-demo.ps1" -Check 2>&1 | ForEach-Object { "  $_" }

"--- start"
$t0 = Get-Date
$p = Start-Process "$dir\MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe" -WorkingDirectory "$dir\MOI_PromiseOfSafety" -PassThru
$until = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $until -and -not ((Test-Path $log) -and (Get-Item $log).LastWriteTime -gt $t0 -and (Get-Content $log -Raw) -match '\[MOI\] STATE Idle')) { Start-Sleep 1 }
"app up after {0:N0} s, status: {1}" -f ((Get-Date) - $t0).TotalSeconds, (Status)
Start-Sleep 3
Shot "room"

# START: the gaze press may already have fired (no headset: the camera looks straight at START). Else Space.
Start-Sleep 3
if ((Status) -notmatch 'state=Playing') {
    # Windows only lets a background process bring a window forward right after it sent input: tap Alt first.
    $p.Refresh()
    for ($try = 0; $try -lt 3 -and [PD]::GetForegroundWindow() -ne $p.MainWindowHandle; $try++) {
        [PD]::keybd_event(0x12, 0x38, 0, [UIntPtr]::Zero); [PD]::keybd_event(0x12, 0x38, 2, [UIntPtr]::Zero)
        [void][PD]::SetForegroundWindow($p.MainWindowHandle); Start-Sleep -Milliseconds 500
    }
    $front = [PD]::GetForegroundWindow() -eq $p.MainWindowHandle
    "foreground is the app: $front"
    # Unity's Input System identifies keys by scan code (Space = 0x39), like a real keyboard sends.
    if ($front) { [PD]::keybd_event(0x20, 0x39, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [PD]::keybd_event(0x20, 0x39, 2, [UIntPtr]::Zero); "pressed Space" }
    else { "app not in front - Space not sent" }
}
$until = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $until -and -not ((Get-Content $log -Raw) -match 'Playing film')) { Start-Sleep 1 }
Start-Sleep 8
"status: " + (Status)
Shot "film"
# Is the film moving, and who decodes it? (Hardware decoding keeps the CPU low.)
function Tiny { $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $g.Dispose(); $s = New-Object System.Drawing.Bitmap $bmp, 64, 40; $bmp.Dispose(); $v = foreach ($y in 0..39) { foreach ($x in 0..63) { $c = $s.GetPixel($x, $y); $c.R + $c.G + $c.B } }; $s.Dispose(); ,$v }
$p.Refresh(); $cpu0 = $p.TotalProcessorTime; $w0 = Get-Date
$prev = Tiny; $moving = 0
for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 400; $cur = Tiny; $d = 0; for ($k = 0; $k -lt $cur.Count; $k++) { $d += [Math]::Abs($cur[$k] - $prev[$k]) }; if ($d -gt 2000) { $moving++ }; $prev = $cur }
$p.Refresh(); $cpu = ($p.TotalProcessorTime - $cpu0).TotalSeconds / ((Get-Date) - $w0).TotalSeconds / [Environment]::ProcessorCount * 100
"film picture changed in $moving of 10 samples (0.4 s apart); app CPU {0:N0}% of the whole CPU ({1} cores)" -f $cpu, [Environment]::ProcessorCount
Shot "film2"

"--- Player.log (MOI lines, XR, video, errors)"
Get-Content $log | Where-Object { $_ -match '\[MOI\]|XR|OpenXR|[Vv]ideo|[Ee]rror|[Ee]xception|Failed' -and $_ -notmatch '^\s*$' } | Select-Object -First 60 | ForEach-Object { "  " + $_.Substring(0, [Math]::Min(200, $_.Length)) }

$p.Refresh(); "still running: " + (-not $p.HasExited) + ", memory {0:N0} MB" -f ($p.WorkingSet64 / 1MB)
[void]$p.CloseMainWindow(); Start-Sleep 3; if (-not $p.HasExited) { $p.Kill() }
"closed"
