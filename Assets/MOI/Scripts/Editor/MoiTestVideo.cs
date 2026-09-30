using System.IO;
using Unity.Collections;
using UnityEditor;
using UnityEditor.Media;
using UnityEngine;

namespace MOI.EditorTools
{
    /// <summary>
    /// Encodes a stand-in for the final film: a full-length mono equirectangular MP4 built from the
    /// storyboard. It exists to prove the START -> 360 playback -> back-to-museum loop (orientation,
    /// sync, audio, decode performance on the headset) before the real film is delivered.
    ///
    /// Picture: each beat's storyboard frame wrapped onto the same 120 degree curved screen the previs
    /// mode uses, dead ahead. Orientation markers: green bar = left (-90), blue bar = right (+90),
    /// red block = directly behind. Sound: a short beep at the start of every beat.
    /// </summary>
    public static class MoiTestVideo
    {
        public const string FileName = "MOI_TestJourney360.mp4";
        const int Width = 2048, Height = 1024, Fps = 15, SampleRate = 48000;

        // Matches the previs screen built by MoiSceneBuilder.
        const float ScreenArc = 120f, ScreenRadius = 4f, ScreenBottom = -0.35f, ScreenTop = 4.36f, EyeHeight = 1.6f;

        [MenuItem("MOI/Review/Encode 360 Test Film", priority = 61)]
        public static void Encode()
        {
            var sequence = AssetDatabase.LoadAssetAtPath<ExperienceSequence>(MoiSceneBuilder.SequencePath);
            if (sequence == null) { Debug.LogError("[MOI] No sequence asset - build the scene first."); return; }

            Directory.CreateDirectory(Application.streamingAssetsPath);
            string path = Path.Combine(Application.streamingAssetsPath, FileName);

            var video = new VideoTrackAttributes
            {
                frameRate = new MediaRational(Fps),
                width = Width,
                height = Height,
                includeAlpha = false,
                bitRateMode = VideoBitrateMode.Medium,
            };
            var audio = new AudioTrackAttributes { sampleRate = new MediaRational(SampleRate), channelCount = 2, language = "en" };

            var frame = new Texture2D(Width, Height, TextureFormat.RGBA32, false);
            int samplesPerFrame = SampleRate / Fps;
            var samples = new NativeArray<float>(samplesPerFrame * 2, Allocator.Persistent);
            try
            {
                using (var encoder = new MediaEncoder(path, video, audio))
                {
                    int total = Mathf.RoundToInt(sequence.TotalDuration * Fps);
                    int composed = -1;
                    for (int f = 0; f < total; f++)
                    {
                        float time = f / (float)Fps;
                        int index = sequence.IndexAt(time);
                        if (index != composed)
                        {
                            composed = index;
                            Compose(frame, index);
                            if (EditorUtility.DisplayCancelableProgressBar("Encoding 360 test film", sequence.beats[index].title, f / (float)total))
                                return;
                        }
                        encoder.AddFrame(frame);

                        // 0.25 s, 880 Hz beep with a quick decay at the top of each beat.
                        float sinceBeat = time - sequence.beats[index].start;
                        for (int s = 0; s < samplesPerFrame; s++)
                        {
                            float t = sinceBeat + s / (float)SampleRate;
                            float v = t < 0.25f ? Mathf.Sin(t * 880f * 2f * Mathf.PI) * 0.3f * (1f - t / 0.25f) : 0f;
                            samples[s * 2] = v;
                            samples[s * 2 + 1] = v;
                        }
                        encoder.AddSamples(samples);
                    }
                }
            }
            finally
            {
                samples.Dispose();
                Object.DestroyImmediate(frame);
                EditorUtility.ClearProgressBar();
            }

            AssetDatabase.Refresh();
            // Only claim the slots if nothing real has been assigned.
            if (!sequence.HasMasterVideo)
            {
                sequence.masterVideoPath = FileName;
                sequence.masterVideoLayout = VideoLayout.Mono360;
                EditorUtility.SetDirty(sequence);
                AssetDatabase.SaveAssets();
            }
            Debug.Log($"[MOI] 360 test film written: {path} ({new FileInfo(path).Length / (1024 * 1024)} MB)");
        }

        static void Compose(Texture2D target, int beatIndex)
        {
            // Beats 17 and 18 return to the museum: reuse the outline and the lit frames.
            int frameNumber = beatIndex == 16 ? 2 : beatIndex == 17 ? 1 : beatIndex + 1;
            string file = $"{MoiSceneBuilder.Root}/Previs/Frames/beat{frameNumber:00}.jpg";
            Texture2D source = null;
            Color32[] src = null;
            if (File.Exists(file))
            {
                source = new Texture2D(2, 2);
                source.LoadImage(File.ReadAllBytes(file));
                src = source.GetPixels32();
            }

            var pixels = new Color32[Width * Height];
            var background = new Color32(6, 8, 14, 255);
            var grid = new Color32(22, 30, 48, 255);
            for (int y = 0; y < Height; y++)
            {
                float lat = ((y + 0.5f) / Height - 0.5f) * 180f;
                // Height on the curved screen that this latitude looks at.
                float v = Mathf.InverseLerp(ScreenBottom, ScreenTop, EyeHeight + ScreenRadius * Mathf.Tan(lat * Mathf.Deg2Rad));
                bool rowOnScreen = Mathf.Abs(lat) < 80f && v > 0f && v < 1f;
                for (int x = 0; x < Width; x++)
                {
                    float lon = ((x + 0.5f) / Width - 0.5f) * 360f;
                    Color32 c = Mathf.Abs(Mathf.Repeat(lon, 30f) - 15f) > 14.7f || Mathf.Abs(Mathf.Repeat(lat, 30f) - 15f) > 14.7f ? grid : background;

                    if (Mathf.Abs(lon + 90f) < 3f && Mathf.Abs(lat) < 20f) c = new Color32(40, 200, 80, 255);
                    else if (Mathf.Abs(lon - 90f) < 3f && Mathf.Abs(lat) < 20f) c = new Color32(60, 110, 255, 255);
                    else if (Mathf.Abs(lon) > 172f && Mathf.Abs(lat) < 8f) c = new Color32(220, 50, 50, 255);
                    else if (src != null && rowOnScreen && Mathf.Abs(lon) < ScreenArc * 0.5f)
                    {
                        int sx = Mathf.Clamp((int)((lon / ScreenArc + 0.5f) * source.width), 0, source.width - 1);
                        int sy = Mathf.Clamp((int)(v * source.height), 0, source.height - 1);
                        c = src[sy * source.width + sx];
                    }
                    pixels[y * Width + x] = c;
                }
            }
            target.SetPixels32(pixels);
            target.Apply(false);
            if (source != null) Object.DestroyImmediate(source);
        }
    }
}
