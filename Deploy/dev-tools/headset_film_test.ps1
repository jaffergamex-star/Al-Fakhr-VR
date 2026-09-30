$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Headset film test: the visitor presses START three times; run 1 plays the 8K film, run 2 the 5.7K, run 3 the 4K.
# Between runs (back at START) the next film is renamed to journey.mp4, which is what the app plays.
# Reads the app's own playback log live: real frame rate and dropped frames every 5 s.
$adb = "$MoiRoot\Delivery\MOI_VR_Station\tools\scrcpy\adb.exe"; $h = "FA66C3N00269"
$dir = "/sdcard/Android/data/com.gamex.moi.promiseofsafety/files"
$sp = Split-Path $MyInvocation.MyCommand.Path
$cat = Join-Path $sp "headset_logcat.txt"
$runs = @(@{ name = "8K 7680x3840"; file = "journey_8k.mp4" }, @{ name = "5.7K 5760x2880"; file = "journey_57k.mp4" }, @{ name = "4K 4096x2048"; file = "journey_4k.mp4" })
function Status { $r = ((& $adb -s $h shell cat "$dir/status.txt" 2>$null) -join " "); if ($r -match "state=(\w+) worn=(\w+) paused=(\w+) films=(\d+)") { @{ state = $Matches[1]; worn = $Matches[2]; paused = $Matches[3]; films = [int]$Matches[4] } } }
function Temp { $t = (& $adb -s $h shell dumpsys battery 2>$null | Select-String "temperature:") -replace '\D', ''; if ($t) { "{0:N1} C" -f ([int]$t / 10) } else { "?" } }
function Say($m) { "{0:HH:mm:ss}  {1}" -f (Get-Date), $m }

& $adb -s $h logcat -c
$lc = Start-Process $adb -ArgumentList "-s $h logcat -v time -s Unity:I" -RedirectStandardOutput $cat -NoNewWindow -PassThru
$s = Status; $base = $s.films
Say "ready: journey.mp4 = $($runs[0].name); app status: state=$($s.state) worn=$($s.worn) films=$($s.films); headset $(Temp)"
$run = 0; $playing = $false; $until = (Get-Date).AddMinutes(14)
while ((Get-Date) -lt $until -and $run -lt $runs.Count) {
    Start-Sleep 1
    $s = Status; if (-not $s) { continue }
    if (-not $playing -and $s.films -gt $base + $run) {
        $playing = $true; $runs[$run].start = Get-Date
        Say "run $($run + 1) started: $($runs[$run].name) (headset $(Temp))"
    }
    elseif ($playing -and $s.state -eq "Idle") {
        $playing = $false; $runs[$run].end = Get-Date
        Say ("run {0} ended after {1:N0} s (headset {2})" -f ($run + 1), ($runs[$run].end - $runs[$run].start).TotalSeconds, (Temp))
        $run++
        if ($run -lt $runs.Count) {
            # Put the film that just played back under its own name, and the next one in place.
            & $adb -s $h shell "cd $dir && mv journey.mp4 $($runs[$run - 1].file) && mv $($runs[$run].file) journey.mp4"
            Say "journey.mp4 is now $($runs[$run].name) - press START again"
        }
    }
}
Start-Sleep 2
Stop-Process -Id $lc.Id -Force -ErrorAction SilentlyContinue
# Leave the headset as it was: the 4K film as journey.mp4 (the others stay on it under their own names).
$now = & $adb -s $h shell "ls $dir"
if ($run -lt $runs.Count) { & $adb -s $h shell "cd $dir && mv journey.mp4 $($runs[$run].file)" | Out-Null }
& $adb -s $h shell "cd $dir && mv journey_4k.mp4 journey.mp4" 2>$null | Out-Null
Say ("headset left with: " + ((& $adb -s $h shell "ls -l $dir | grep mp4") -join " | "))

""
"=== playback log from the app (frame rate every 5 s) ==="
$lines = Get-Content $cat -ErrorAction SilentlyContinue | Where-Object { $_ -match '\[MOI\] (Film|Playing film|STATE)|Video:' }
$lines | ForEach-Object { ($_ -replace '^\S+\s+(\S+)\s+\S+\s+', '$1  ') }
""
"=== summary per run ==="
$i = 0
foreach ($r in $runs) {
    $i++
    if (-not $r.start) { "run {0} ({1}): not played" -f $i, $r.name; continue }
    $w = $r.name.Split(' ')[1]
    $mine = $lines | Where-Object { $_ -match "Film $w at" }
    $fps = $mine | ForEach-Object { if ($_ -match ': ([\d.]+) fps, (\d+) frame') { [pscustomobject]@{ fps = [double]$Matches[1]; drop = [int]$Matches[2] } } }
    if ($fps) { "run {0} ({1}): {2} samples, frame rate {3:N1}-{4:N1} fps, {5} frame(s) dropped in total" -f $i, $r.name, @($fps).Count, ($fps | Measure-Object fps -Minimum).Minimum, ($fps | Measure-Object fps -Maximum).Maximum, ($fps | Measure-Object drop -Sum).Sum }
    else { "run {0} ({1}): no frame-rate lines (film may not have played - check the log above)" -f $i, $r.name }
}
