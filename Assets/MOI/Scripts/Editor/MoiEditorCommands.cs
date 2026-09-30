using System.IO;
using UnityEditor;
using UnityEngine;

namespace MOI.EditorTools
{
    /// <summary>
    /// Deferred editor commands via a one-line file in Temp/. Two uses:
    /// - work that has to continue after a domain reload (switching platform recompiles everything and
    ///   kills whatever was running), and
    /// - driving the open editor from a terminal / script: echo build-scene > Temp/moi-command.txt
    /// Only the fixed commands below are accepted.
    /// </summary>
    [InitializeOnLoad]
    public static class MoiEditorCommands
    {
        public const string BuildScene = "build-scene";
        public const string Configure = "configure";
        public const string BuildApk = "build-apk";
        public const string BuildWindows = "build-windows";
        public const string CaptureStills = "capture-stills";
        public const string EncodeTestFilm = "encode-test-film";
        const string CommandFile = "Temp/moi-command.txt";

        static double s_NextPoll;

        static MoiEditorCommands()
        {
            EditorApplication.update += Poll;
        }

        public static void Queue(string command) => File.WriteAllText(CommandFile, command);

        static void Poll()
        {
            if (EditorApplication.timeSinceStartup < s_NextPoll) return;
            s_NextPoll = EditorApplication.timeSinceStartup + 1.0;
            if (!File.Exists(CommandFile)) return;
            if (EditorApplication.isCompiling || EditorApplication.isUpdating || EditorApplication.isPlayingOrWillChangePlaymode) return;

            string command = File.ReadAllText(CommandFile).Trim();
            File.Delete(CommandFile);
            switch (command)
            {
                case BuildScene: MoiSceneBuilder.Build(); break;
                case Configure: MoiProjectSetup.ConfigureProject(); break;
                case BuildApk: MoiBuild.BuildApk(); break;
                case BuildWindows: MoiBuild.BuildWindows(); break;
                case CaptureStills: MoiReviewCapture.Run(); break;
                case EncodeTestFilm: MoiTestVideo.Encode(); break;
                default: Debug.LogWarning("[MOI] Unknown editor command '" + command + "'."); break;
            }
        }
    }
}
