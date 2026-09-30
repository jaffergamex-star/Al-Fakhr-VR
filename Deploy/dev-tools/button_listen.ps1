# Plain listener on the button box (no station): prints every line it sends, and every time it drops off USB.
# Opens the port without DTR/RTS, so opening it does not restart the board (the station's open does).
param([string]$Com = "COM8", [int]$Seconds = 150)
function Say($m) { "{0:HH:mm:ss.fff}  {1}" -f (Get-Date), $m }
function Arrival { $d = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_2341' } | Select-Object -First 1; if ($d) { (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_LastArrivalDate -ErrorAction SilentlyContinue).Data } }
function Open-Port { $p = New-Object System.IO.Ports.SerialPort $Com, 9600; $p.DtrEnable = $false; $p.RtsEnable = $false; $p.ReadTimeout = 200; $p.Open(); return $p }
$port = $null; $buf = ""; $arr = Arrival; $end = (Get-Date).AddSeconds($Seconds); $lines = 0; $drops = 0
while ((Get-Date) -lt $end) {
    if (-not $port -or -not $port.IsOpen) {
        try { $port = Open-Port; if ($opened) { Say "!! the box dropped off - connected again"; $drops++ } else { Say "listening on $Com - press the play button now" }; $opened = $true } catch { $port = $null; Start-Sleep -Milliseconds 500; continue }
    }
    try {
        $t = $port.ReadExisting()
        if ($t) {
            $buf += $t
            while ($buf -match "^(.*?)[\r\n]+") { $line = $Matches[1]; $buf = $buf.Substring($Matches[0].Length); if ($line.Trim()) { Say "box sent: $($line.Trim())"; $lines++ } }
        }
    } catch { Say "!! port lost ($($_.Exception.Message))"; $drops++; try { $port.Close() } catch { }; $port = $null }
    $a = Arrival
    if ($a -and $arr -and $a -ne $arr) { Say ("!! the box dropped off USB and came back (Windows: arrived {0:HH:mm:ss})" -f ([DateTime]$a).ToLocalTime()); $arr = $a; $drops++ }
    Start-Sleep -Milliseconds 100
}
if ($buf.Trim()) { Say "box sent (no line end): $($buf.Trim())" }
try { $port.Close() } catch { }
""
"lines received: $lines, USB drops: $drops"
