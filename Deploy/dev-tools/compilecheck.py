"""Offline compile check of Assets/MOI scripts using the Roslyn that ships with the Unity editor."""
import glob, os, subprocess, sys

ED = r'C:\Program Files\Unity\Hub\Editor\6000.1.4f1\Editor\Data'
PROJ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(PROJ, 'Temp', 'compilecheck')
os.makedirs(OUT, exist_ok=True)

refs = [os.path.join(ED, r'NetStandard\ref\2.1.0\netstandard.dll')]
refs += glob.glob(os.path.join(ED, r'Managed\UnityEngine\*.dll'))
for name in ['Unity.XR.Management', 'Unity.XR.Management.Editor', 'Unity.XR.OpenXR', 'Unity.XR.OpenXR.Editor', 'UnityEngine.UI', 'Unity.InputSystem', 'Unity.TextMeshPro', 'Unity.TextMeshPro.Editor',
             'Unity.RenderPipelines.Universal.Runtime', 'Unity.RenderPipelines.Core.Runtime']:
    refs.append(os.path.join(PROJ, 'Library', 'ScriptAssemblies', name + '.dll'))

def compile(name, sources, extra_refs=(), defines=('UNITY_EDITOR',)):
    rsp = os.path.join(OUT, name + '.rsp')
    with open(rsp, 'w', encoding='utf-8') as f:
        f.write('-target:library -nostdlib -nologo -langversion:9.0 -nowarn:CS1701,CS1702\n')
        f.write('-out:"%s"\n' % os.path.join(OUT, name + '.dll'))
        for d in defines: f.write('-define:%s\n' % d)
        for r in list(refs) + list(extra_refs): f.write('-r:"%s"\n' % r)
        for s in sources: f.write('"%s"\n' % s)
    p = subprocess.run([os.path.join(ED, r'NetCoreRuntime\dotnet.exe'), os.path.join(ED, r'DotNetSdkRoslyn\csc.dll'), '@' + rsp],
                       capture_output=True, text=True)
    print('== %s: exit %d' % (name, p.returncode))
    print((p.stdout + p.stderr).strip() or 'clean')
    return p.returncode

runtime = glob.glob(os.path.join(PROJ, r'Assets\MOI\Scripts\Runtime\*.cs'))
rc = compile('MOI.Runtime', runtime)
if rc == 0:
    skip = set(sys.argv[1:])
    editor = [s for s in glob.glob(os.path.join(PROJ, r'Assets\MOI\Scripts\Editor\*.cs')) if os.path.basename(s) not in skip]
    compile('MOI.Editor', editor, extra_refs=[os.path.join(OUT, 'MOI.Runtime.dll')])
