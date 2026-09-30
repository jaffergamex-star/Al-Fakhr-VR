using System.IO;
using UnityEditor;
using UnityEngine;

namespace MOI.EditorTools
{
    /// <summary>
    /// Plays the experience in the editor, jumps to a set of timecodes and writes a still of the
    /// visitor's forward view for each into Review/. Quick way to check every beat after a change,
    /// and a contact sheet for client reviews without handing over a headset.
    /// </summary>
    [InitializeOnLoad]
    public static class MoiReviewCapture
    {
        const string PendingKey = "MOI.CapturePending";
        const string OutputFolder = "Review";
        const int Width = 1600, Height = 900;
        const double SettleSeconds = 0.7;

        // One per distinct look: lit museum, outlines, last light, gallery early/late, white-out,
        // a spread of previs beats, tunnel, Qasr Al Hosn, return, final.
        static readonly float[] Times = { 4f, 13.5f, 21f, 26f, 32f, 40.8f, 47f, 60f, 96f, 131f, 153f, 163f, 174.5f, 179.5f };

        static ExperienceDirector s_Director;
        static int s_Index;
        static bool s_FilmStarted;
        static int s_ResetCheck;
        static double s_NextStep;

        static MoiReviewCapture()
        {
            EditorApplication.playModeStateChanged += OnPlayModeChanged;
        }

        [MenuItem("MOI/Review/Capture Stills", priority = 60)]
        public static void Run()
        {
            if (EditorApplication.isPlaying) return;
            SessionState.SetBool(PendingKey, true);
            EditorApplication.EnterPlaymode();
        }

        static void OnPlayModeChanged(PlayModeStateChange change)
        {
            if (change != PlayModeStateChange.EnteredPlayMode || !SessionState.GetBool(PendingKey, false)) return;
            SessionState.SetBool(PendingKey, false);
            // Keep ticking if the editor loses focus mid-capture.
            Application.runInBackground = true;
            s_Director = null;
            s_ResetCheck = 0;
            s_Index = -1;
            // Long enough for the content manager to sync a small test film from a local server.
            s_NextStep = EditorApplication.timeSinceStartup + 6.0;
            EditorApplication.update += Step;
        }

        static void Step()
        {
            if (!EditorApplication.isPlaying) { EditorApplication.update -= Step; return; }
            if (EditorApplication.timeSinceStartup < s_NextStep) return;

            if (s_Director == null)
            {
                s_Director = Object.FindFirstObjectByType<ExperienceDirector>();
                if (s_Director == null)
                {
                    Debug.LogError("[MOI] No ExperienceDirector in the open scene.");
                    Finish();
                    return;
                }
                Directory.CreateDirectory(OutputFolder);
                Capture("00_idle");
                s_Director.Begin();
                if (s_Director.WillPlayFilm)
                {
                    // Fade out, prepare, fade in.
                    s_NextStep = EditorApplication.timeSinceStartup + 4.0;
                    s_Index = -1;
                    s_FilmStarted = true;
                    return;
                }
            }
            else if (s_FilmStarted)
            {
                s_FilmStarted = false;
            }
            else if (s_Index >= 0 && s_ResetCheck == 0)
            {
                var beat = s_Director.CurrentBeat;
                string prefix = s_Director.WillPlayFilm ? "film_" : "";
                Capture($"{prefix}{s_Director.BeatIndex + 1:00}_{beat.id}_t{Times[s_Index]:000.0}");
            }

            s_Index++;
            if (s_Index >= Times.Length)
            {
                // Epilogue: prove the hidden operator reset works from the middle of the journey.
                switch (s_ResetCheck++)
                {
                    case 0: s_Director.Seek(60f); s_NextStep = EditorApplication.timeSinceStartup + 1.6; s_Index = Times.Length - 1; return;
                    case 1: s_Director.ResetToStart(); s_NextStep = EditorApplication.timeSinceStartup + 1.0; s_Index = Times.Length - 1; return;
                    default: Capture("99_after_operator_reset_" + s_Director.CurrentState); Finish(); return;
                }
            }
            s_Director.Seek(Times[s_Index]);
            bool film = s_Director.WillPlayFilm;
            if (!film) s_Director.crystal.SnapToTarget();
            s_NextStep = EditorApplication.timeSinceStartup + (film ? 1.6 : SettleSeconds);
        }

        static void Capture(string name)
        {
            var cam = Camera.main;
            var target = new RenderTexture(Width, Height, 24, RenderTextureFormat.ARGB32) { antiAliasing = 4 };
            cam.targetTexture = target;
            cam.Render();
            cam.targetTexture = null;

            var previous = RenderTexture.active;
            RenderTexture.active = target;
            var still = new Texture2D(Width, Height, TextureFormat.RGB24, false);
            still.ReadPixels(new Rect(0, 0, Width, Height), 0, 0);
            still.Apply();
            RenderTexture.active = previous;

            File.WriteAllBytes(Path.Combine(OutputFolder, name + ".png"), still.EncodeToPNG());
            Object.Destroy(still);
            target.Release();
            Object.Destroy(target);
        }

        static void Finish()
        {
            EditorApplication.update -= Step;
            Debug.Log("[MOI] Review stills written to " + Path.GetFullPath(OutputFolder));
            EditorApplication.ExitPlaymode();
        }
    }
}
