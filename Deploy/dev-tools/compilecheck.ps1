# Offline compile check of Assets/MOI scripts with the Roslyn that ships with the Unity editor.
# Same as compilecheck.py, for PCs without Python (the ASUS PC). Runtime part must be "clean"; the Editor part
# prints known false CS0012 mscorlib errors - look for any OTHER error code.
param([string[]]$SkipEditor = @())

$ed   = 'C:\Program Files\Unity\Hub\Editor\6000.1.4f1\Editor\Data'
$proj = Split-Path (Split-Path $PSScriptRoot)
$out  = Join-Path $proj 'Temp\compilecheck'
New-Item -ItemType Directory -Force $out | Out-Null

$refs = @(Join-Path $ed 'NetStandard\ref\2.1.0\netstandard.dll')
$refs += (Get-ChildItem (Join-Path $ed 'Managed\UnityEngine') -Filter *.dll).FullName
foreach ($n in 'Unity.XR.Management','Unity.XR.Management.Editor','Unity.XR.OpenXR','Unity.XR.OpenXR.Editor','UnityEngine.UI','Unity.InputSystem','Unity.TextMeshPro','Unity.TextMeshPro.Editor','Unity.RenderPipelines.Universal.Runtime','Unity.RenderPipelines.Core.Runtime') {
    $refs += Join-Path $proj "Library\ScriptAssemblies\$n.dll"
}

function Compile($name, $sources, $extraRefs = @()) {
    $lines = @('-target:library -nostdlib -nologo -langversion:9.0 -nowarn:CS1701,CS1702', "-out:`"$out\$name.dll`"", '-define:UNITY_EDITOR')
    foreach ($r in ($refs + $extraRefs)) { $lines += "-r:`"$r`"" }
    foreach ($s in $sources) { $lines += "`"$s`"" }
    $rsp = Join-Path $out "$name.rsp"
    Set-Content -Path $rsp -Value $lines -Encoding UTF8
    $text = & (Join-Path $ed 'NetCoreRuntime\dotnet.exe') (Join-Path $ed 'DotNetSdkRoslyn\csc.dll') "@$rsp" | Out-String
    Write-Host "== ${name}: exit $LASTEXITCODE"
    if ($text.Trim()) { Write-Host $text.Trim() } else { Write-Host 'clean' }
    return $LASTEXITCODE
}

$runtime = (Get-ChildItem (Join-Path $proj 'Assets\MOI\Scripts\Runtime') -Filter *.cs).FullName
$rc = Compile 'MOI.Runtime' $runtime
if ($rc -eq 0) {
    $editor = (Get-ChildItem (Join-Path $proj 'Assets\MOI\Scripts\Editor') -Filter *.cs | Where-Object { $SkipEditor -notcontains $_.Name }).FullName
    Compile 'MOI.Editor' $editor @((Join-Path $out 'MOI.Runtime.dll')) | Out-Null
}
