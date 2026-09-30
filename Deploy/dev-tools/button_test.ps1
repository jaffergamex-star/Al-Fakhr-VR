$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Arduino button test: the station in a small window (no headset, intro shortened) reads the button box and should
# start the intro on each press. Follows the station log until two presses started the intro, or 4 minutes pass.
$dir = "$MoiRoot\Delivery\MOI_PC_Demo"
$log = "$dir\logs\station-{0:yyyy-MM-dd}.log" -f (Get-Date)
$pos = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$lnk = Join-Path $env:TEMP "moi_button_test.lnk"
$sh = New-Object -ComObject WScript.Shell; $l = $sh.CreateShortcut($lnk)
$l.TargetPath = "powershell.exe"
$l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dir\visitor-station.ps1`" -Windowed -Serial NOHEADSET -NoLaunchApp -IntroSkip 110 -QuitAfter 240"
$l.WorkingDirectory = $dir; $l.Save()
Start-Process $lnk
$t0 = Get-Date; $intros = 0
while (((Get-Date) - $t0).TotalMinutes -lt 4 -and $intros -lt 2) {
    Start-Sleep -Milliseconds 500
    try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($pos, 'Begin'); $t = (New-Object IO.StreamReader($fs)).ReadToEnd(); $pos = $fs.Position; $fs.Close() } catch { $t = "" }
    foreach ($line in ($t -split "`r?`n" | Where-Object { $_ })) {
        if ($line -match 'serial|button|-> |intro playing') { $line }
        if ($line -match '-> Intro') { $intros++ }
    }
}
Start-Sleep 12
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'visitor-station\.ps1' -and $_.CommandLine -match 'NOHEADSET' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
"--- button presses that started the intro: $intros"
