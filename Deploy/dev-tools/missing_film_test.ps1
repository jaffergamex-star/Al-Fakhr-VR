$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Windows build without the test film: (1) film present -> plays the 8K; (2) film taken away -> START screen says the
# film is missing and START does nothing; film put back while the app runs -> picked up by itself.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class MF {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
[void][MF]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$sp = Split-Path $MyInvocation.MyCommand.Path
$dir = "$MoiRoot\Builds\Windows"
$film = "$dir\content\journey.mp4"
$log = Join-Path $env:USERPROFILE "AppData\LocalLow\GameX\MOI Promise of Safety\Player.log"
function Start-App { $t0 = Get-Date; $p = Start-Process "$dir\MOI_PromiseOfSafety.exe" -WorkingDirectory $dir -PassThru; $u = (Get-Date).AddSeconds(40); while ((Get-Date) -lt $u -and -not ((Test-Path $log) -and (Get-Item $log).LastWriteTime -gt $t0 -and (Get-Content $log -Raw) -match '\[MOI\] STATE Idle')) { Start-Sleep 1 }; Start-Sleep 2; $p.Refresh(); return $p }
function Press-Space($p) { for ($i = 0; $i -lt 3 -and [MF]::GetForegroundWindow() -ne $p.MainWindowHandle; $i++) { [MF]::keybd_event(0x12, 0x38, 0, [UIntPtr]::Zero); [MF]::keybd_event(0x12, 0x38, 2, [UIntPtr]::Zero); [void][MF]::SetForegroundWindow($p.MainWindowHandle); Start-Sleep -Milliseconds 400 }; [MF]::keybd_event(0x20, 0x39, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [MF]::keybd_event(0x20, 0x39, 2, [UIntPtr]::Zero) }
function MoiLines { Get-Content $log | Where-Object { $_ -match '\[MOI\] (No film|Film|Playing film|START pressed|STATE)' } | ForEach-Object { "    $_" } }
function Stop-App($p) { [void]$p.CloseMainWindow(); Start-Sleep 2; if (-not $p.HasExited) { $p.Kill() } }

"=== 1. film present"
$p = Start-App; Press-Space $p
$u = (Get-Date).AddSeconds(25); while ((Get-Date) -lt $u -and -not ((Get-Content $log -Raw) -match 'Film 7680x3840 at')) { Start-Sleep 1 }
MoiLines; Stop-App $p

"=== 2. film taken away"
Rename-Item $film "journey.mp4.away"
try {
    $p = Start-App
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size); $g.Dispose()
    $small = New-Object System.Drawing.Bitmap $bmp, ([int]($b.Width / 2)), ([int]($b.Height / 2)); $bmp.Dispose(); $small.Save("$sp\film_missing_screen.png"); $small.Dispose()
    "    (screenshot film_missing_screen.png)"
    Press-Space $p; Start-Sleep 3
    "  --- log after START with no film:"; MoiLines
    "=== 3. film put back while the app runs"
    Rename-Item "$film.away" "journey.mp4"
    Start-Sleep 4
    "  --- log:"; Get-Content $log | Where-Object { $_ -match '\[MOI\] Film found' } | ForEach-Object { "    $_" }
    Stop-App $p
} finally {
    if (Test-Path "$film.away") { Rename-Item "$film.away" "journey.mp4" }
    "film back in place: " + (Test-Path $film)
}
