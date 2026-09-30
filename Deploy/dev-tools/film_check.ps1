$MoiRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the project folder (this file is in Deploy\dev-tools)
# Looks at the 8K original and measures how close the existing 4K 8-bit conversion is to it.
$ff = "C:\Program Files\Derivative\TouchDesigner\bin\ffmpeg.exe"
$src = "$env:USERPROFILE\Downloads\AlFakher_Mono360_8K.mp4"
$old = "$MoiRoot\Delivery\MOI_VR_Station\content\journey.mp4"
$out = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "film"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Add-Type -AssemblyName System.Drawing

# 1. Contact sheet of the original, 8 moments.
$times = 1, 9, 18, 27, 36, 45, 54, 64
foreach ($t in $times) { & $ff -v error -y -ss $t -i $src -frames:v 1 -vf "zscale=w=960:h=480:filter=lanczos,format=rgb24" "$out\src_$t.png" }
$sheet = New-Object System.Drawing.Bitmap 1920, 1960
$g = [System.Drawing.Graphics]::FromImage($sheet); $g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $times.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile("$out\src_$($times[$i]).png")
    $x = ($i % 2) * 960; $y = [Math]::Floor($i / 2) * 490
    $g.DrawImage($img, $x, $y, 960, 480); $img.Dispose()
    $g.DrawString("$($times[$i]) s", $font, [System.Drawing.Brushes]::Yellow, $x + 8, $y + 6)
}
$g.Dispose(); $sheet.Save("$out\contact_sheet.png", [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
"contact sheet written"

# 2. Existing 4K conversion against the original scaled to 4K (SSIM 1.0 = identical; PSNR in dB, 40+ = excellent).
foreach ($t in 3, 15, 30, 45, 60) {
    $r = & $ff -hide_banner -ss $t -i $old -ss $t -i $src -filter_complex "[1:v]zscale=w=4096:h=2048:filter=lanczos:dither=error_diffusion,format=yuv420p[ref];[0:v]format=yuv420p[dut];[dut]split[a][b];[ref]split[c][d];[a][c]ssim;[b][d]psnr" -frames:v 1 -f null - 2>&1 | Where-Object { $_ -match "SSIM|PSNR" }
    $ssim = if (($r -join " ") -match "All:([\d.]+)") { $Matches[1] } else { "?" }
    $psnr = if (($r -join " ") -match "average:([\d.inf]+)") { $Matches[1] } else { "?" }
    "t=$t s: SSIM $ssim  PSNR $psnr dB"
}

# 3. Darkest moment, 1:1 crops (original 10-bit shown on an 8-bit screen vs existing 8-bit file), contrast-stretched
#    x4 so any banding in the dark gradients becomes visible.
$lumas = foreach ($t in $times) { $b = [System.Drawing.Bitmap]::FromFile("$out\src_$t.png"); $s = 0; for ($y = 0; $y -lt 480; $y += 8) { for ($x = 0; $x -lt 960; $x += 8) { $c = $b.GetPixel($x, $y); $s += $c.R + $c.G + $c.B } }; $b.Dispose(); [pscustomobject]@{ t = $t; l = $s } }
$dark = ($lumas | Sort-Object l | Select-Object -First 1).t
"darkest sampled moment: $dark s"
& $ff -v error -y -ss $dark -i $src -frames:v 1 -vf "zscale=w=4096:h=2048:filter=lanczos:dither=error_diffusion,format=rgb24,crop=1024:512:1536:0,lutrgb=r=val*4:g=val*4:b=val*4" "$out\dark_original.png"
& $ff -v error -y -ss $dark -i $old -frames:v 1 -vf "format=rgb24,crop=1024:512:1536:0,lutrgb=r=val*4:g=val*4:b=val*4" "$out\dark_existing4k.png"
"crops written"
