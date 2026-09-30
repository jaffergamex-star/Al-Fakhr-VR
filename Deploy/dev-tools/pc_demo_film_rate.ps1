param([string[]]$Films = @("", "content\journey_4k.mp4"))
$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Plays films in the PC demo on this laptop ("" = the default content\journey.mp4, else passed with -film) and
# reports the app's own playback log: real frame rate and dropped frames every 5 s, plus CPU use.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class PR {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@
$dir = "$MoiRoot\Delivery\MOI_PC_Demo\MOI_PromiseOfSafety"
$data = Join-Path $env:USERPROFILE "AppData\LocalLow\GameX\MOI Promise of Safety"
$log = Join-Path $data "Player.log"
$m = Join-Path $data "Content\manifest.json"; $hold = "$m.pcdemo-test-hold"
Rename-Item $m (Split-Path $hold -Leaf)
try {
    foreach ($f in $Films) {
        "=== " + $(if ($f) { $f } else { "default film (content\journey.mp4)" })
        $t0 = Get-Date
        $sp = @{ FilePath = "$dir\MOI_PromiseOfSafety.exe"; WorkingDirectory = $dir; PassThru = $true }
        if ($f) { $sp.ArgumentList = @("-film", "`"$f`"") }
        $p = Start-Process @sp
        $until = (Get-Date).AddSeconds(40)
        while ((Get-Date) -lt $until -and -not ((Test-Path $log) -and (Get-Item $log).LastWriteTime -gt $t0 -and (Get-Content $log -Raw) -match '\[MOI\] STATE Idle')) { Start-Sleep 1 }
        Start-Sleep 3; $p.Refresh()
        for ($try = 0; $try -lt 3 -and [PR]::GetForegroundWindow() -ne $p.MainWindowHandle; $try++) {
            [PR]::keybd_event(0x12, 0x38, 0, [UIntPtr]::Zero); [PR]::keybd_event(0x12, 0x38, 2, [UIntPtr]::Zero)
            [void][PR]::SetForegroundWindow($p.MainWindowHandle); Start-Sleep -Milliseconds 500
        }
        if ([PR]::GetForegroundWindow() -ne $p.MainWindowHandle) { "  app not in front - skipped"; $p.Kill(); continue }
        [PR]::keybd_event(0x20, 0x39, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [PR]::keybd_event(0x20, 0x39, 2, [UIntPtr]::Zero)
        $until = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $until -and -not ((Get-Content $log -Raw) -match 'Film ready')) { Start-Sleep 1 }
        $p.Refresh(); $cpu0 = $p.TotalProcessorTime; $w0 = Get-Date
        Start-Sleep 17
        $p.Refresh(); $cpu = ($p.TotalProcessorTime - $cpu0).TotalSeconds / ((Get-Date) - $w0).TotalSeconds / [Environment]::ProcessorCount * 100
        Get-Content $log | Where-Object { $_ -match '\[MOI\] (Playing film|Film|-film)|Video:' } | ForEach-Object { "  $_" }
        "  app CPU during playback: {0:N0}% of the whole CPU, memory {1:N0} MB" -f $cpu, ($p.WorkingSet64 / 1MB)
        [void]$p.CloseMainWindow(); Start-Sleep 3; if (-not $p.HasExited) { $p.Kill() }
        Start-Sleep 2
    }
} finally {
    Rename-Item $hold (Split-Path $m -Leaf)
    "cached manifest restored: " + (Test-Path $m)
}
