using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Networking;
using UnityEngine.Video;

namespace MOI
{
    public enum EnvironmentKind
    {
        /// <summary>Real-time geometry under <c>root</c>.</summary>
        Set,
        /// <summary>Flat storyboard frame on the curved previs screen. Stand-in until the beat is produced.</summary>
        PrevisFrame,
        /// <summary>Equirectangular still on the skybox.</summary>
        Panorama360,
        /// <summary>Equirectangular video on the skybox (pre-rendered beats).</summary>
        Video360,
    }

    public enum StereoLayout { Mono, TopBottom, SideBySide }

    [Serializable]
    public class EnvironmentEntry
    {
        public string id;
        public EnvironmentKind kind;
        [Tooltip("Optional for every kind: extra objects that belong to this environment.")]
        public GameObject root;
        public Texture texture;
        public VideoClip video;
        public StereoLayout stereo = StereoLayout.Mono;
    }

    /// <summary>
    /// Swaps what surrounds the visitor. Each beat names an environment; how that environment is
    /// delivered (live set, 360 video, previs frame) can change per beat without touching the timeline.
    /// </summary>
    public class EnvironmentManager : MonoBehaviour
    {
        static readonly int MainTexId = Shader.PropertyToID("_MainTex");
        static readonly int LayoutId = Shader.PropertyToID("_Layout");
        static readonly int RotationId = Shader.PropertyToID("_Rotation");
        static readonly int ZoomId = Shader.PropertyToID("_Zoom");
        public const string StartScreenId = "start-screen";
        // Skybox/Panoramic maps the centre of an equirectangular image to +X. Films are authored with
        // their centre as "front", so turn it to +Z, where the visitor faces after the recentre.
        const float FrontIsForward = 90f;

        public List<EnvironmentEntry> environments = new List<EnvironmentEntry>();
        public Camera head;
        public Renderer previsScreen;
        [Tooltip("Material using MOI/Panorama360 (Skybox/Panoramic plus zoom). Instanced at runtime.")]
        public Material panoramaSkybox;
        public VideoPlayer videoPlayer;
        [Tooltip("Shown instead if the START screen video cannot be played.")]
        public string startScreenFallbackId = "museum";

        bool m_StartScreenPending;
        string m_StartScreenPath;

        // Stall watch: a video that is "playing" but whose frame has not moved for StallSeconds while the app is awake. After
        // the headset slept (taken off and left) Android can take the decoder away and the player stays stuck on one frame
        // with its sound hanging (user, 2026-10-02). The START video is then opened again; for the film FilmStalled is raised.
        const float StallSeconds = 3f;
        const float FirstFrameSeconds = 10f;
        bool m_Watching;
        long m_WatchFrame;
        float m_WatchAt;
        public event System.Action FilmStalled;

        /// <summary>Forget the stall watch (after a pause: the frames did not move because nothing ran).</summary>
        public void ResetStallWatch() => m_Watching = false;

        Material m_Skybox;
        RenderTexture m_VideoTarget;
        MaterialPropertyBlock m_Block;
        public string CurrentId { get; private set; }

        // Playback check for the log (Player.log on a PC, logcat on the headset): every 5 s while the film plays,
        // how fast it really advances and how many frames the player had to drop. A machine that can't decode
        // the film in time shows up as dropped frames.
        bool m_FilmShowing;
        long m_RateFrame;
        float m_RateAt;
        int m_Dropped;

        public bool VideoReady => videoPlayer != null && videoPlayer.isPrepared;
        public bool VideoFinished { get; private set; }
        public double VideoTime => videoPlayer != null ? videoPlayer.time : 0.0;

        void Awake()
        {
            m_Block = new MaterialPropertyBlock();
            if (panoramaSkybox != null) m_Skybox = new Material(panoramaSkybox);
            foreach (var e in environments)
                if (e.root != null) e.root.SetActive(false);
            if (previsScreen != null) previsScreen.gameObject.SetActive(false);
            if (videoPlayer != null)
            {
                videoPlayer.loopPointReached += _ => VideoFinished = true;
                videoPlayer.errorReceived += (_, message) =>
                {
                    Debug.LogError("[MOI] Video: " + message, this);
                    VideoFinished = true;
                    if (CurrentId == StartScreenId) { Debug.LogError("[MOI] START screen video failed - showing " + startScreenFallbackId, this); Show(startScreenFallbackId); }
                };
                videoPlayer.frameDropped += _ => m_Dropped++;
            }
        }

        void Update()
        {
            if (m_StartScreenPending && videoPlayer != null && videoPlayer.isPrepared)
            {
                m_StartScreenPending = false;
                EnsureVideoTarget((int)videoPlayer.width, (int)videoPlayer.height);
                videoPlayer.targetTexture = m_VideoTarget;
                m_Skybox.SetTexture(MainTexId, m_VideoTarget);
                videoPlayer.Play();
                Debug.Log($"[MOI] START screen video: {videoPlayer.width}x{videoPlayer.height}, {videoPlayer.length:F1} s, looping");
            }
            WatchForStall();
            if (!m_FilmShowing || videoPlayer == null || !videoPlayer.isPlaying) return;
            if (m_RateFrame < 0) { m_RateFrame = videoPlayer.frame; m_RateAt = Time.unscaledTime; m_Dropped = 0; return; }
            float span = Time.unscaledTime - m_RateAt;
            if (span < 5f) return;
            double fps = (videoPlayer.frame - m_RateFrame) / span;
            Debug.Log($"[MOI] Film {videoPlayer.width}x{videoPlayer.height} at {videoPlayer.time:F0} s: {fps:F1} fps, {m_Dropped} frame(s) dropped in the last {span:F0} s");
            m_RateFrame = videoPlayer.frame; m_RateAt = Time.unscaledTime; m_Dropped = 0;
        }

        /// <summary>Starts buffering the master film. Poll <see cref="VideoReady"/>, then call <see cref="ShowPreparedVideo"/>.</summary>
        public void PrepareVideo(VideoClip clip, string path)
        {
            VideoFinished = false;
            m_StartScreenPending = false;
            videoPlayer.Stop();
            if (clip != null)
            {
                videoPlayer.source = VideoSource.VideoClip;
                videoPlayer.clip = clip;
            }
            else
            {
                videoPlayer.source = VideoSource.Url;
                bool absolute = path.Contains("://") || System.IO.Path.IsPathRooted(path);
                videoPlayer.url = absolute ? path : Application.streamingAssetsPath + "/" + path;
            }
            // The film carries its own voice-over and score.
            videoPlayer.audioOutputMode = VideoAudioOutputMode.Direct;
            videoPlayer.isLooping = false;
            videoPlayer.Prepare();
        }

        /// <summary>True for a path that resolves into StreamingAssets (i.e. inside the APK on Android).</summary>
        public static bool IsBundledPath(string path)
        {
            return !string.IsNullOrEmpty(path) && !path.Contains("://") && !System.IO.Path.IsPathRooted(path);
        }

        /// <summary>
        /// On Android, StreamingAssets live inside the APK, not on the file system. VideoPlayer can normally
        /// read them in place (the file is stored uncompressed), but if a device refuses, this copies the
        /// film out to app storage once so it can be played as an ordinary file.
        /// </summary>
        public System.Collections.IEnumerator ExtractBundledVideo(string relativePath, System.Action<string> done)
        {
            string target = System.IO.Path.Combine(Application.persistentDataPath, "Bundled", relativePath);
            if (!System.IO.File.Exists(target))
            {
                System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(target));
                using (var request = new UnityWebRequest(Application.streamingAssetsPath + "/" + relativePath, UnityWebRequest.kHttpVerbGET))
                {
                    request.downloadHandler = new DownloadHandlerFile(target + ".part") { removeFileOnAbort = true };
                    yield return request.SendWebRequest();
                    if (request.result != UnityWebRequest.Result.Success)
                    {
                        Debug.LogError("[MOI] Could not extract bundled film: " + request.error, this);
                        done(null);
                        yield break;
                    }
                }
                System.IO.File.Move(target + ".part", target);
                Debug.Log("[MOI] Bundled film extracted to " + target);
            }
            done(target);
        }

        public void SeekVideo(double seconds)
        {
            if (videoPlayer == null || !videoPlayer.canSetTime) return;
            VideoFinished = false;
            videoPlayer.time = System.Math.Max(0.0, System.Math.Min(seconds, videoPlayer.length - 0.1));
        }

        public void ShowPreparedVideo(VideoLayout layout, float yawDegrees)
        {
            CurrentId = null;
            foreach (var e in environments)
                if (e.root != null) e.root.SetActive(false);

            EnsureVideoTarget((int)videoPlayer.width, (int)videoPlayer.height);
            videoPlayer.targetTexture = m_VideoTarget;

            bool flat = layout == VideoLayout.FlatScreen || m_Skybox == null;
            previsScreen.gameObject.SetActive(flat);
            head.clearFlags = flat ? CameraClearFlags.SolidColor : CameraClearFlags.Skybox;
            if (flat)
            {
                previsScreen.GetPropertyBlock(m_Block);
                m_Block.SetTexture(MainTexId, m_VideoTarget);
                previsScreen.SetPropertyBlock(m_Block);
            }
            else
            {
                m_Skybox.SetFloat(LayoutId, layout == VideoLayout.Mono360 ? 0f : layout == VideoLayout.SideBySide360 ? 1f : 2f);
                m_Skybox.SetFloat(RotationId, Mathf.Repeat(yawDegrees + FrontIsForward, 360f));
                m_Skybox.SetTexture(MainTexId, m_VideoTarget);
                RenderSettings.skybox = m_Skybox;
            }
            Debug.Log($"[MOI] Film ready: {videoPlayer.width}x{videoPlayer.height}, {videoPlayer.frameRate:F0} fps, {videoPlayer.length:F1} s");
            SetZoom(1f);
            m_FilmShowing = true; m_RateFrame = -1;
            videoPlayer.Play();
        }

        public void StopVideo()
        {
            m_FilmShowing = false;
            m_StartScreenPending = false;
            if (videoPlayer != null) videoPlayer.Stop();
        }

        /// <summary>1 = as filmed; above 1 the front of the picture is bigger, below 1 smaller / farther away (MOI/Panorama360).</summary>
        public void SetZoom(float zoom)
        {
            if (m_Skybox != null) m_Skybox.SetFloat(ZoomId, Mathf.Clamp(zoom, 0.6f, 2f));
        }

        /// <summary>
        /// The START screen: a 360 video looping with its sound on the sky, every environment object off (the START
        /// button belongs to the HUD). The sky stays black until the player has opened the file.
        /// </summary>
        public void ShowStartScreen(string path, bool reopen = false)
        {
            if (m_Skybox == null || videoPlayer == null) { Debug.LogWarning("[MOI] No sky material / video player for the START screen.", this); Show(startScreenFallbackId); return; }
            if (!reopen && CurrentId == StartScreenId && (m_StartScreenPending || videoPlayer.isPlaying)) return;
            m_StartScreenPath = path;
            m_Watching = false;
            CurrentId = StartScreenId;
            foreach (var e in environments)
                if (e.root != null) e.root.SetActive(false);
            if (previsScreen != null) previsScreen.gameObject.SetActive(false);
            m_FilmShowing = false;
            videoPlayer.Stop();

            head.clearFlags = CameraClearFlags.Skybox;
            m_Skybox.SetFloat(LayoutId, 0f);
            m_Skybox.SetFloat(RotationId, Mathf.Repeat(FrontIsForward, 360f));
            SetZoom(1f);
            m_Skybox.SetTexture(MainTexId, Texture2D.blackTexture);
            RenderSettings.skybox = m_Skybox;

            VideoFinished = false;
            videoPlayer.source = VideoSource.Url;
            videoPlayer.url = IsBundledPath(path) ? Application.streamingAssetsPath + "/" + path : path;
            videoPlayer.audioOutputMode = VideoAudioOutputMode.Direct;
            videoPlayer.isLooping = true;
            videoPlayer.Prepare();
            m_StartScreenPending = true;
        }

        void WatchForStall()
        {
            bool watched = videoPlayer != null && videoPlayer.isPlaying && (m_FilmShowing || CurrentId == StartScreenId);
            if (!watched) { m_Watching = false; return; }
            // Only while the app runs normally: a headset lying on the table keeps the app awake but throttled (5 frames a
            // second on FA66C3N00269, 2026-10-03), and then the video does not advance either - not a stuck decoder. Below 10
            // frames a second, or without focus, the watch starts over.
            if (Time.unscaledDeltaTime > 0.1f || !Application.isFocused) { m_Watching = false; return; }
            // A separate flag, not a frame value: a video that has not shown its first frame yet reports frame -1, which once
            // made every fresh START video look stuck at once and reopened it in a loop (black, no sound, 2026-10-02).
            long frame = videoPlayer.frame;
            if (!m_Watching || frame != m_WatchFrame) { m_Watching = true; m_WatchFrame = frame; m_WatchAt = Time.unscaledTime; return; }
            // The first frame of an 8K video can take a while: 10 s before the first frame, 3 s once it is moving.
            if (Time.unscaledTime - m_WatchAt < (frame < 1 ? FirstFrameSeconds : StallSeconds)) return;
            m_Watching = false;
            if (m_FilmShowing)
            {
                Debug.LogWarning($"[MOI] Film stuck at {videoPlayer.time:F1} s for {StallSeconds:F0} s", this);
                FilmStalled?.Invoke();
            }
            else
            {
                Debug.LogWarning($"[MOI] START screen video stuck for {StallSeconds:F0} s - opening it again", this);
                ShowStartScreen(m_StartScreenPath, true);
            }
        }

        void OnDestroy()
        {
            if (m_Skybox != null) Destroy(m_Skybox);
            if (m_VideoTarget != null) m_VideoTarget.Release();
        }

        public void Show(string id)
        {
            if (id == CurrentId) return;
            m_StartScreenPending = false;
            var next = environments.Find(e => e.id == id);
            if (next == null)
            {
                Debug.LogWarning($"[MOI] No environment '{id}'.", this);
                return;
            }
            CurrentId = id;

            foreach (var e in environments)
                if (e.root != null) e.root.SetActive(e == next);

            bool previs = next.kind == EnvironmentKind.PrevisFrame;
            if (previsScreen != null)
            {
                previsScreen.gameObject.SetActive(previs);
                if (previs)
                {
                    previsScreen.GetPropertyBlock(m_Block);
                    m_Block.SetTexture(MainTexId, next.texture != null ? next.texture : Texture2D.blackTexture);
                    previsScreen.SetPropertyBlock(m_Block);
                }
            }

            bool sky = next.kind == EnvironmentKind.Panorama360 || next.kind == EnvironmentKind.Video360;
            head.clearFlags = sky && m_Skybox != null ? CameraClearFlags.Skybox : CameraClearFlags.SolidColor;
            if (videoPlayer != null && videoPlayer.isPlaying) videoPlayer.Stop();
            if (!sky || m_Skybox == null) return;

            m_Skybox.SetFloat(LayoutId, next.stereo == StereoLayout.Mono ? 0f : next.stereo == StereoLayout.SideBySide ? 1f : 2f);
            m_Skybox.SetFloat(RotationId, Mathf.Repeat(FrontIsForward, 360f));
            if (next.kind == EnvironmentKind.Panorama360)
            {
                m_Skybox.SetTexture(MainTexId, next.texture);
            }
            else if (videoPlayer != null && next.video != null)
            {
                EnsureVideoTarget((int)next.video.width, (int)next.video.height);
                // Per-beat clips are picture only; voice-over and music stay on the director's clock.
                videoPlayer.source = VideoSource.VideoClip;
                videoPlayer.audioOutputMode = VideoAudioOutputMode.None;
                videoPlayer.clip = next.video;
                videoPlayer.targetTexture = m_VideoTarget;
                m_Skybox.SetTexture(MainTexId, m_VideoTarget);
                videoPlayer.Play();
            }
            RenderSettings.skybox = m_Skybox;
        }

        void EnsureVideoTarget(int width, int height)
        {
            if (m_VideoTarget != null && m_VideoTarget.width == width && m_VideoTarget.height == height) return;
            if (m_VideoTarget != null) m_VideoTarget.Release();
            m_VideoTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32) { name = "MOI 360 Video" };
        }
    }
}
