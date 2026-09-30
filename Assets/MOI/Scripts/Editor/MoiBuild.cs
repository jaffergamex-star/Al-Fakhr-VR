using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace MOI.EditorTools
{
    public static class MoiBuild
    {
        const string ApkPath = "Builds/MOI_PromiseOfSafety.apk";
        const string WindowsExePath = "Builds/Windows/MOI_PromiseOfSafety.exe";

        [MenuItem("MOI/3. Build APK", priority = 3)]
        public static void BuildApk() => Build(BuildOptions.None);

        [MenuItem("MOI/3b. Build APK and Run on Headset (dev build)", priority = 4)]
        public static void BuildAndRun() => Build(BuildOptions.AutoRunPlayer | BuildOptions.Development);

        /// <summary>
        /// PC VR build: runs on the Windows PC and streams to the headset through VIVE Streaming Hub or SteamVR
        /// (whichever is the PC's OpenXR runtime). Its window on the PC screen shows the headset view.
        /// CI entry point: Unity -batchmode -quit -buildTarget Win64 -executeMethod MOI.EditorTools.MoiBuild.BuildWindows
        /// </summary>
        [MenuItem("MOI/4. Build Windows (PC VR via VIVE Streaming / SteamVR)", priority = 5)]
        public static void BuildWindows()
        {
            if (!File.Exists(MoiSceneBuilder.ScenePath))
            {
                Debug.LogError("[MOI] No scene yet - run MOI > 2. Build Experience Scene first.");
                return;
            }
            // The visitor looks into the headset, not at the PC window: keep running when the window has no focus.
            PlayerSettings.runInBackground = true;
            PlayerSettings.visibleInBackground = true;
            PlayerSettings.fullScreenMode = FullScreenMode.FullScreenWindow;
            // DirectX 11: every PC OpenXR runtime supports it (SteamVR, VIVE), and the video player decodes the
            // film on the graphics card. On DirectX 12 (Unity 6's default) the video player needs a second device
            // for that, which failed on test PCs and fell back to decoding 4K HEVC on the CPU.
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.StandaloneWindows64, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.StandaloneWindows64, new[] { UnityEngine.Rendering.GraphicsDeviceType.Direct3D11 });
            AssetDatabase.SaveAssets();

            Directory.CreateDirectory(Path.GetDirectoryName(WindowsExePath));
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { MoiSceneBuilder.ScenePath },
                locationPathName = WindowsExePath,
                target = BuildTarget.StandaloneWindows64,
                targetGroup = BuildTargetGroup.Standalone,
                options = BuildOptions.None,
            });
            var summary = report.summary;
            if (summary.result == BuildResult.Succeeded)
                Debug.Log($"[MOI] Built {WindowsExePath} ({summary.totalSize / (1024UL * 1024UL)} MB). Film: put journey.mp4 in a 'content' folder next to the .exe.");
            else
                Debug.LogError($"[MOI] Windows build {summary.result}: {summary.totalErrors} error(s).");
            if (Application.isBatchMode && summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }

        /// <summary>CI entry point: Unity -batchmode -quit -executeMethod MOI.EditorTools.MoiBuild.BuildApk</summary>
        static void Build(BuildOptions options)
        {
            if (!File.Exists(MoiSceneBuilder.ScenePath))
            {
                Debug.LogError("[MOI] No scene yet - run MOI > 2. Build Experience Scene first.");
                return;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(ApkPath));
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { MoiSceneBuilder.ScenePath },
                locationPathName = ApkPath,
                target = BuildTarget.Android,
                targetGroup = BuildTargetGroup.Android,
                options = options,
            });

            var summary = report.summary;
            if (summary.result == BuildResult.Succeeded)
                Debug.Log($"[MOI] Built {ApkPath} ({new FileInfo(ApkPath).Length / (1024 * 1024)} MB). Sideload with: adb install -r {ApkPath}");
            else
                Debug.LogError($"[MOI] Build {summary.result}: {summary.totalErrors} error(s).");
            if (Application.isBatchMode && summary.result != BuildResult.Succeeded) EditorApplication.Exit(1);
        }
    }
}
