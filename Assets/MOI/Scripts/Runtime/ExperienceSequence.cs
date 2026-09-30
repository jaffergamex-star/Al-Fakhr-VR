using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Serialization;
using UnityEngine.Video;

namespace MOI
{
    public enum Language { English, Arabic }
    public enum VideoLayout { FlatScreen, Mono360, TopBottom360, SideBySide360 }
    public enum TransitionKind { Cut, FadeBlack, FadeWhite }
    public enum CrystalMode { OnPodium, Floating, Hidden }

    /// <summary>Zoom over the film: 1, eased to <c>to</c> between <c>at</c> and <c>at + over</c> seconds, then held.</summary>
    [Serializable]
    public struct FilmZoom
    {
        public float at;
        public float over;
        public float to;

        public float ValueAt(float seconds)
        {
            if (to <= 0f || Mathf.Approximately(to, 1f) || seconds <= at) return 1f;
            if (over <= 0f || seconds >= at + over) return to;
            return Mathf.Lerp(1f, to, Mathf.SmoothStep(0f, 1f, (seconds - at) / over));
        }

        public override string ToString() => Mathf.Approximately(to, 1f) || to <= 0f ? "no zoom"
            : to < 1f ? $"zoom out 1 -> {1f / to:0.##} (everything {1f / to:0.##} times farther) at {at:0.#}-{at + over:0.#} s"
            : $"zoom in 1 -> {to:0.##} at {at:0.#}-{at + over:0.#} s";
    }

    /// <summary>
    /// Where START is drawn in the START screen video, in degrees from the viewer (yaw 0 = the video's centre, which
    /// faces the visitor at START; pitch up). The START button becomes an invisible hotspot of this size, kept this
    /// far in front of the head so it stays exactly over the drawn button. Width or height 0 = the normal, visible
    /// START button instead.
    /// </summary>
    [Serializable]
    public struct StartHotspot
    {
        public float yaw;
        public float pitch;
        public float width;
        public float height;
        public float distance;

        public bool Enabled => width > 0f && height > 0f && distance > 0f;
    }

    /// <summary>One storyboard beat. Times are seconds on the master clock.</summary>
    [Serializable]
    public class Beat
    {
        public string id;
        public string title;
        public float start;
        public float end;
        [TextArea(2, 4)] public string direction;

        [Header("Voice over")]
        [TextArea(2, 5)] public string voiceOverEn;
        [TextArea(2, 5)] public string voiceOverAr;
        public AudioClip voiceClipEn;
        public AudioClip voiceClipAr;

        [Header("Picture")]
        [Tooltip("Id of an entry in EnvironmentManager.")]
        public string environmentId;
        [Tooltip("How we arrive in this beat. The fade straddles the cut: half before, half after.")]
        public TransitionKind transitionIn = TransitionKind.Cut;
        public float transitionDuration = 1f;
        [Tooltip("Museum state across the beat: 0 dark, ~0.45 blue outlines, 1 fully lit.")]
        public float revealFrom = 1f;
        public float revealTo = 1f;

        [Header("Crystal")]
        public CrystalMode crystal = CrystalMode.OnPodium;
        [Tooltip("Floating position relative to the visitor's start spot (x right, y up, z forward), metres.")]
        public Vector3 crystalOffset = new Vector3(0.8f, 1.5f, 3f);
        public float glowFrom = 1f;
        public float glowTo = 1f;

        public float Duration => Mathf.Max(0.01f, end - start);
    }

    [CreateAssetMenu(menuName = "MOI/Experience Sequence", fileName = "PromiseOfSafety")]
    public class ExperienceSequence : ScriptableObject
    {
        public List<Beat> beats = new List<Beat>();
        [Tooltip("Optional score/ambience bed, started at 00:00.")]
        public AudioClip music;

        [Header("Single-video delivery")]
        [Tooltip("If set, pressing Start plays this one film (with its own soundtrack) instead of the real-time beats. Beats are still used for subtitles and the review timecode.")]
        public VideoClip masterVideo;
        [Tooltip("Alternative to the clip for big files: path under StreamingAssets, an absolute path on the headset (e.g. /sdcard/MOI/journey.mp4), or a URL.")]
        [FormerlySerializedAs("masterVideoPathAr")]
        public string masterVideoPath;
        public VideoLayout masterVideoLayout = VideoLayout.Mono360;
        [Tooltip("Degrees to turn the 360 film so its intended 'front' lands where the visitor faces at START.")]
        [Range(-180f, 180f)] public float masterVideoYaw;
        [Tooltip("Zoom during the film: 1 from the start, eased to 'to' between 'at' and 'at + over' seconds, then held to the end. Below 1 = zoomed out (0.8 = everything 1.25 times farther away), above 1 = zoomed in. A film.json next to the film can override it.")]
        public FilmZoom filmZoom = new FilmZoom { at = 35f, over = 1f, to = 0.8f };

        [Header("START screen")]
        [Tooltip("360 video looping (with its sound) behind START instead of the museum room: a path under StreamingAssets. Empty = the museum room.")]
        public string startScreenVideoPath = "StartScreen360.mp4";
        [Tooltip("The START button drawn in that video: an invisible START hotspot goes over it. Width/height 0 = visible START button.")]
        public StartHotspot startHotspot = new StartHotspot { yaw = 0f, pitch = 1.85f, width = 27f, height = 11f, distance = 8f };

        [Header("LAN content server")]
        [Tooltip("Default manifest URL, e.g. http://192.168.1.20:8080/moi/manifest.json. moi-config.json on the headset overrides it. Film from the server wins over the fields above.")]
        public string contentManifestUrl;

        public bool HasMasterVideo => masterVideo != null || !string.IsNullOrEmpty(masterVideoPath);

        public float TotalDuration => beats.Count == 0 ? 0f : beats[beats.Count - 1].end;

        public int IndexAt(float time)
        {
            for (int i = beats.Count - 1; i >= 0; i--)
                if (time >= beats[i].start) return i;
            return 0;
        }
    }
}
