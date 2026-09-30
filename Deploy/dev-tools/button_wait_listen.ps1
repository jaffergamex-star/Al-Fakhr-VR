# Waits (up to 6 minutes) for the button box to appear on USB, then listens to it for 90 seconds.
function Say($m) { "{0:HH:mm:ss}  {1}" -f (Get-Date), $m }
$until = (Get-Date).AddMinutes(6); $com = $null
Say "waiting for the button box on USB..."
while ((Get-Date) -lt $until -and -not $com) {
    $d = Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -match 'VID_(2341|2A03|1A86|10C4|0403)' -and $_.Name -match '\((COM\d+)\)' } | Select-Object -First 1
    if ($d -and $d.Name -match '\((COM\d+)\)') { $com = $Matches[1]; Say "button box found: $($d.Name)" } else { Start-Sleep 1 }
}
if (-not $com) { Say "the button box did not appear on USB within 6 minutes"; return }
Start-Sleep 2
& "$PSScriptRoot\button_listen.ps1" -Com $com -Seconds 90
