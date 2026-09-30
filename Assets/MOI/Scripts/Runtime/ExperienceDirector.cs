using System;
using System.Collections;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;
using UnityEngine.Video;

namespace MOI
{
    /// <summary>
    /// Runs "The Promise of Safety" off a single master clock. Everything on screen is evaluated as a
    /// function of that clock (museum state, crystal, fades, beat behaviours), so the three minutes
    /// play identically every time and can be skipped through during reviews.
    ///
    /// Museum flow: Idle (room lit, crystal waiting) -> Playing -> Outro hold -> Idle.
    /// The visitor starts it with the in-world Start button (VRButton -> Begin); A/X and Space also work,
    /// and it can optionally start by itself when the headset is put on.
    ///
    /// Two ways to deliver the journey, chosen by the sequence asset:
    /// - master video: one finished film (flat or 360) plays from start to end, or
    /// - real-time beats: each beat is a live set / 360 clip / previs frame on the shared clock.
    /// </summary>
    public class ExperienceDirector : MonoBehaviour
    {
        public enum State { Idle, Playing, Outro }

        [Header("Content")]
        public ExperienceSequence sequence;
        [Tooltip("Only matters for the real-time beats (which voice clip / subtitle text). The film is single-language.")]
        public Language language = Language.Arabic;

        [Header("Scene")]
        public XRRig rig;
        public EnvironmentManager environments;
        [Tooltip("Optional. Film downloaded from the LAN content server wins over anything on the sequence asset.")]
        public ContentManager content;
        public MuseumRoom museum;
        public CrystalGuide crystal;
        public ScreenFader fader;
        public AudioSource voiceSource;
        public AudioSource musicSource;
        public string idleEnvironmentId = "museum";

        [Header("Kiosk behaviour")]
        public bool autoStartWhenWorn = false;
        public float wornStartDelay = 2.5f;
        [Tooltip("Headset taken off mid-journey for this long returns to Idle for the next visitor.")]
        public float removedResetDelay = 8f;
        public float outroHold = 6f;

        [Header("Hidden operator reset")]
        [Tooltip("Hold the left Menu button, or squeeze both grips, this long to return to the START screen from anywhere.")]
        public float resetHoldSeconds = 2f;
        [Tooltip("Keep holding this long for a full reload of the app (re-reads config, re-syncs content).")]
        public float reloadHoldSeconds = 6f;

        /// <summary>0..1 while staff are holding the reset combo; the HUD shows a hint past the halfway mark.</summary>
        public float ResetHoldProgress => Mathf.Clamp01(m_ResetHold / resetHoldSeconds);

        // State changes are logged as "[MOI] STATE x" so a PC watching logcat (Deploy/visitor-station.ps1)
        // can follow the visitor: switch its screen to the mirror, and back when the film is over.
        public State CurrentState
        {
            get => m_State;
            private set
            {
                if (m_State == value) return;
                m_State = value;
                Debug.Log("[MOI] STATE " + value);
                if (value == State.Playing) m_FilmsStarted++;
                WriteStatus();
            }
        }
        State m_State = State.Idle;
        bool? m_LastWorn;

        // One-line status file for the PC station (read over USB every second). The headset's own log is a
        // 1 MB ring buffer that HTC services fill within minutes, so it can't be relied on for this.
        //   state=Idle worn=True paused=False films=3
        // "films" counts film starts, so the PC can't miss a film even if it began and ended between reads.
        int m_FilmsStarted;
        bool m_Paused;
        bool? m_LastWornForStatus;

        void WriteStatus()
        {
            try
            {
                string worn = m_LastWornForStatus.HasValue ? m_LastWornForStatus.Value.ToString() : "Unknown";
                string line = $"state={m_State} worn={worn} paused={m_Paused} films={m_FilmsStarted}";
                string path = System.IO.Path.Combine(Application.persistentDataPath, "status.txt");
                System.IO.File.WriteAllText(path + ".tmp", line);
                if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
                System.IO.File.Move(path + ".tmp", path);
            }
            catch (Exception e) { Debug.LogWarning("[MOI] status file: " + e.Message); }
        }

        // Commands from the station: one word in <persistentDataPath>/command.txt, read and deleted every 0.5 s.
        //   reset  -> back to the START screen (sent when the headset has been off for a few seconds)
        //   reload -> reload the whole app
        string m_CommandPath;
        float m_NextCommandCheck;

        void PollCommands()
        {
            if (Time.unscaledTime < m_NextCommandCheck) return;
            m_NextCommandCheck = Time.unscaledTime + 0.5f;
            if (m_CommandPath == null) m_CommandPath = System.IO.Path.Combine(Application.persistentDataPath, "command.txt");
            if (!System.IO.File.Exists(m_CommandPath)) return;
            string command;
            try { command = System.IO.File.ReadAllText(m_CommandPath).Trim().ToLowerInvariant(); System.IO.File.Delete(m_CommandPath); }
            catch { return; }   // being written right now: next time
            Debug.Log("[MOI] Command from the station: " + command);
            switch (command)
            {
                case "reset": ResetToStart(); break;
                case "reload": SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex); break;
                default: Debug.LogWarning("[MOI] Unknown command: " + command); break;
            }
        }

        /// <summary>True/false once the runtime has reported presence at least once; null if it never has.</summary>
        public bool? IsWorn => m_LastWorn;
        public float Clock { get; private set; }
        public int BeatIndex { get; private set; } = -1;
        public Beat CurrentBeat => sequence != null && BeatIndex >= 0 ? sequence.beats[BeatIndex] : null;
        public event Action<Beat> BeatEntered;

        InputAction m_Start, m_Stop, m_Next, m_Previous, m_Presence, m_GripLeft, m_GripRight, m_StopNow;
        float m_ResetHold;
        bool m_ResetFired;
        BeatBehaviour[] m_Behaviours;
        double m_DspStart;
        float m_WornTimer, m_RemovedTimer, m_OutroTimer;
        bool m_Armed = true;
        bool m_PresenceSeen;
        Coroutine m_VideoRoutine;

        void Awake()
        {
            // The trigger belongs to the laser pointer (VRPointer); A/X is the no-aim shortcut.
            m_Start = Action("Start", "<XRController>/{PrimaryButton}", "<Keyboard>/space");
            // Deliberately awkward: nothing a visitor does by accident should end the journey.
            m_Stop = Action("Operator Reset (hold)", "<XRController>/{MenuButton}", "<Keyboard>/backspace");
            m_GripLeft = Action("Grip Left", "<XRController>{LeftHand}/{GripButton}");
            m_GripRight = Action("Grip Right", "<XRController>{RightHand}/{GripButton}");
            m_StopNow = Action("Editor Reset", "<Keyboard>/escape");
            m_Next = Action("Next Beat", "<Keyboard>/rightArrow");
            m_Previous = Action("Previous Beat", "<Keyboard>/leftArrow");
            m_Presence = Action("Presence", "<XRHMD>/userPresence");
            m_Behaviours = FindObjectsByType<BeatBehaviour>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        }

        static InputAction Action(string name, params string[] bindings)
        {
            var action = new InputAction(name, InputActionType.Button);
            foreach (var b in bindings) action.AddBinding(b);
            return action;
        }

        void OnEnable()
        {
            foreach (var a in new[] { m_Start, m_Stop, m_Next, m_Previous, m_Presence, m_GripLeft, m_GripRight, m_StopNow }) a.Enable();
        }

        void OnDisable()
        {
            foreach (var a in new[] { m_Start, m_Stop, m_Next, m_Previous, m_Presence, m_GripLeft, m_GripRight, m_StopNow }) a.Disable();
        }

        void Start()
        {
            EnterIdle();
            Debug.Log("[MOI] STATE Idle");
            WriteStatus();
        }

        // On standalone headsets taking the headset off usually pauses the app (proximity sensor), even
        // where the runtime doesn't report user presence. Logged as a second "is it being worn" signal.
        void OnApplicationPause(bool paused)
        {
            Debug.Log("[MOI] PAUSED " + paused);
            m_Paused = paused;
            WriteStatus();
            if (!paused) m_RecenterAt = Time.unscaledTime + 0.5f;
        }

        // While waiting at START, turn the museum so the podium and START are straight ahead of whoever
        // just put the headset on. Delayed a moment so the head pose has settled after the headset wakes.
        float m_RecenterAt = 1f;

        void UpdateAutoRecenter()
        {
            if (m_RecenterAt <= 0f || Time.unscaledTime < m_RecenterAt) return;
            m_RecenterAt = 0f;
            if (CurrentState != State.Idle) return;
            rig.Recenter();
            Debug.Log("[MOI] RECENTER");
        }

        // The userPresence control exists on every OpenXR HMD layout, but a runtime that doesn't
        // implement it just leaves it at "not worn" forever. So presence is only believed once it has
        // been seen true; until then the answer is null, "don't know".
        bool? Worn
        {
            get
            {
                // PC VR build: without the runtime's real user-presence support the plugin substitutes "app has
                // focus", which would read as "always worn". Then better no answer at all (PcVrRuntime decides).
                // With support, ask the runtime for the current state each time: the input control below only
                // changes on events, and on SteamVR the first one (headset already worn when the app starts) came
                // before the control existed - the app then never learnt the headset was on.
                if (Application.platform == RuntimePlatform.WindowsPlayer)
                {
                    if (PcVrRuntime.PresenceSupported != true) return null;
                    return UnityEngine.XR.OpenXR.OpenXRUtility.IsUserPresent;
                }
                // Headset: the same, when its runtime reports presence (the Focus Vision does). The input control alone
                // never learnt about a headset that was already worn when the app started (2026-09-29).
                if (HeadsetReportsPresence()) return UnityEngine.XR.OpenXR.OpenXRUtility.IsUserPresent;
                bool pressed = m_Presence.controls.Count > 0 && m_Presence.IsPressed();
                m_PresenceSeen |= pressed;
                return m_PresenceSeen ? pressed : (bool?)null;
            }
        }

        // Asked once the XR runtime is up: does it report whether the headset is worn (XR_EXT_user_presence)?
        static bool? s_HeadsetPresence;

        static bool HeadsetReportsPresence()
        {
            if (s_HeadsetPresence.HasValue) return s_HeadsetPresence.Value;
            var settings = UnityEngine.XR.Management.XRGeneralSettings.Instance;
            if (settings == null || settings.Manager == null || settings.Manager.activeLoader == null) return false;
            s_HeadsetPresence = UnityEngine.XR.OpenXR.OpenXRRuntime.IsExtensionEnabled("XR_EXT_user_presence");
            Debug.Log(s_HeadsetPresence.Value
                ? "[MOI] Headset reports whether it is worn (user presence) - read directly"
                : "[MOI] Headset does not report user presence - using the input control");
            return s_HeadsetPresence.Value;
        }

        void Update()
        {
            if (sequence == null || sequence.beats.Count == 0) return;
            var worn = Worn;
            if (worn != m_LastWorn && worn.HasValue)
            {
                Debug.Log("[MOI] WORN " + worn.Value);
                m_LastWornForStatus = worn;
                WriteStatus();
                if (worn.Value) m_RecenterAt = Time.unscaledTime + 0.5f;
            }
            UpdateAutoRecenter();
            m_LastWorn = worn;
            PollCommands();
            if (UpdateOperatorReset()) return;

            switch (CurrentState)
            {
                case State.Idle: UpdateIdle(); break;
                case State.Playing: UpdatePlaying(); break;
                case State.Outro:
                    m_OutroTimer += Time.deltaTime;
                    if (m_OutroTimer >= outroHold) EnterIdle();
                    break;
            }
        }

        bool UpdateOperatorReset()
        {
            if (m_StopNow.WasPressedThisFrame() && Application.isEditor) { ResetToStart(); return true; }

            bool held = m_Stop.IsPressed() || m_GripLeft.IsPressed() && m_GripRight.IsPressed();
            if (!held)
            {
                m_ResetHold = 0f;
                m_ResetFired = false;
                return false;
            }
            m_ResetHold += Time.unscaledDeltaTime;
            if (m_ResetHold >= reloadHoldSeconds)
            {
                Debug.Log("[MOI] Operator reload");
                SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex);
                return true;
            }
            if (m_ResetHold >= resetHoldSeconds && !m_ResetFired)
            {
                m_ResetFired = true;
                ResetToStart();
                return true;
            }
            return false;
        }

        /// <summary>Back to the START screen from any state, mid-film included, turned to face whoever wears the headset.</summary>
        public void ResetToStart()
        {
            Debug.Log("[MOI] Operator reset to START");
            EnterIdle();
            m_Armed = false; // don't auto-start again until the headset has come off
            RequestRecenter();
        }

        /// <summary>Turn the START room to face the visitor in a moment (only while at START).</summary>
        public void RequestRecenter() => m_RecenterAt = Time.unscaledTime + 0.5f;

        void UpdateIdle()
        {
            var worn = Worn;
            if (worn == false) m_Armed = true;
            m_WornTimer = autoStartWhenWorn && m_Armed && worn == true ? m_WornTimer + Time.deltaTime : 0f;

            if (m_Start.WasPressedThisFrame() || m_WornTimer >= wornStartDelay) Begin();
        }

        void UpdatePlaying()
        {
            if (m_VideoRoutine != null) return; // the film coroutine owns the clock
            if (m_Next.WasPressedThisFrame() && BeatIndex + 1 < sequence.beats.Count) Seek(sequence.beats[BeatIndex + 1].start);
            if (m_Previous.WasPressedThisFrame()) Seek(sequence.beats[Mathf.Max(0, BeatIndex - 1)].start);

            m_RemovedTimer = Worn == false ? m_RemovedTimer + Time.deltaTime : 0f;
            if (m_RemovedTimer >= removedResetDelay) { EnterIdle(); return; }

            // The audio clock, not frame time, so picture can never drift from the voice-over.
            Clock = (float)(AudioSettings.dspTime - m_DspStart);
            if (Clock >= sequence.TotalDuration)
            {
                Clock = sequence.TotalDuration;
                Evaluate();
                CurrentState = State.Outro;
                m_OutroTimer = 0f;
                return;
            }
            Evaluate();
        }

        public void Begin()
        {
            if (CurrentState != State.Idle) return;
            if (WillPlayFilm)
            {
                VideoClip clip = null;
                string path;
                var layout = sequence.masterVideoLayout;
                float yaw = sequence.masterVideoYaw;
                var zoom = sequence.filmZoom;
                if (content != null && content.TryGetFilm(out var film))
                {
                    path = film.path;
                    layout = film.layout;
                    yaw = film.yaw;
                    zoom = film.zoom;
                }
                else
                {
                    clip = sequence.masterVideo;
                    path = sequence.masterVideoPath;
                }
                CurrentState = State.Playing;
                m_Armed = false;
                m_VideoRoutine = StartCoroutine(PlayMasterVideo(clip, path, layout, yaw, zoom));
                return;
            }
            // Headset and PC builds only ever play the film. The real-time storyboard journey below is for review
            // in the editor; without a film a build stays at START, which says the film is missing.
            if (!Application.isEditor)
            {
                Debug.Log("[MOI] START pressed, but there is no film on this device - nothing to play");
                return;
            }
            rig.Recenter();
            crystal.SnapToTarget();
            CurrentState = State.Playing;
            m_Armed = false;
            m_WornTimer = m_RemovedTimer = 0f;
            BeatIndex = -1;
            Seek(0f);
        }

        public void Seek(float time)
        {
            if (m_VideoRoutine != null)
            {
                environments.SeekVideo(time);
                return;
            }
            Clock = Mathf.Clamp(time, 0f, sequence.TotalDuration);
            m_DspStart = AudioSettings.dspTime - Clock;
            BeatIndex = -1;
            if (musicSource != null && sequence.music != null)
            {
                musicSource.clip = sequence.music;
                musicSource.time = Mathf.Min(Clock, sequence.music.length - 0.05f);
                musicSource.Play();
            }
            Evaluate();
        }

        /// <summary>True when START will play a finished film (from the content server, or bundled) rather than the real-time beats.</summary>
        public bool WillPlayFilm => sequence.HasMasterVideo || content != null && content.TryGetFilm(out _);

        /// <summary>The waiting visitor sees the START screen video instead of the museum room.</summary>
        public bool UsesStartScreen => sequence != null && !string.IsNullOrEmpty(sequence.startScreenVideoPath);

        IEnumerator PlayMasterVideo(VideoClip clip, string path, VideoLayout layout, float yaw, FilmZoom zoom)
        {
            Debug.Log($"[MOI] Playing film: {(clip != null ? clip.name : path)} [{layout}, yaw {yaw}, {zoom}]");
            yield return Fade(0f, 1f, 0.8f);
            rig.Recenter();
            environments.PrepareVideo(clip, path);
            float patience = 15f;
            while (!environments.VideoReady && !environments.VideoFinished && (patience -= Time.deltaTime) > 0f) yield return null;

            // Film inside the APK would not open in place: copy it out once and play the copy.
            if (!environments.VideoReady && clip == null && EnvironmentManager.IsBundledPath(path))
            {
                Debug.LogWarning("[MOI] Bundled film did not open from the APK - extracting to storage.");
                string extracted = null;
                yield return environments.ExtractBundledVideo(path, result => extracted = result);
                if (extracted != null)
                {
                    path = extracted;
                    environments.PrepareVideo(null, path);
                    patience = 15f;
                    while (!environments.VideoReady && !environments.VideoFinished && (patience -= Time.deltaTime) > 0f) yield return null;
                }
            }

            if (environments.VideoReady)
            {
                crystal.SetState(CrystalMode.Hidden, Vector3.zero, 1f);
                environments.ShowPreparedVideo(layout, yaw);
                yield return Fade(1f, 0f, 1.2f);

                m_RemovedTimer = 0f;
                while (!environments.VideoFinished && m_RemovedTimer < removedResetDelay)
                {
                    Clock = (float)environments.VideoTime;
                    environments.SetZoom(zoom.ValueAt(Clock));
                    BeatIndex = sequence.IndexAt(Clock);
                    if (m_Next.WasPressedThisFrame() && BeatIndex + 1 < sequence.beats.Count) Seek(sequence.beats[BeatIndex + 1].start);
                    if (m_Previous.WasPressedThisFrame()) Seek(sequence.beats[Mathf.Max(0, BeatIndex - 1)].start);
                    m_RemovedTimer = Worn == false ? m_RemovedTimer + Time.deltaTime : 0f;
                    yield return null;
                }
                yield return Fade(0f, 1f, 1.2f);
            }
            else
            {
                Debug.LogError("[MOI] Film did not become ready: " + path, this);
            }

            environments.StopVideo();
            m_VideoRoutine = null;
            EnterIdle();
            yield return Fade(1f, 0f, 1.5f);
        }

        IEnumerator Fade(float from, float to, float seconds)
        {
            for (float t = 0f; t < seconds; t += Time.deltaTime)
            {
                fader.Set(Color.black, Mathf.SmoothStep(from, to, t / seconds));
                yield return null;
            }
            fader.Set(Color.black, to);
        }

        void EnterIdle()
        {
            if (m_VideoRoutine != null)
            {
                StopCoroutine(m_VideoRoutine);
                m_VideoRoutine = null;
                environments.StopVideo();
            }
            CurrentState = State.Idle;
            Clock = 0f;
            BeatIndex = -1;
            m_WornTimer = 0f;
            voiceSource.Stop();
            if (musicSource != null) musicSource.Stop();

            if (UsesStartScreen) environments.ShowStartScreen(sequence.startScreenVideoPath);
            else environments.Show(idleEnvironmentId);
            museum.SetReveal(1f);
            crystal.SetState(UsesStartScreen ? CrystalMode.Hidden : CrystalMode.OnPodium, Vector3.zero, 1f);
            fader.Set(Color.black, 0f);
            foreach (var b in m_Behaviours) b.Evaluate(false, 0f);
        }

        void Evaluate()
        {
            int index = sequence.IndexAt(Clock);
            var beat = sequence.beats[index];
            if (index != BeatIndex) EnterBeat(index, beat);

            float t = Mathf.InverseLerp(beat.start, beat.end, Clock);
            museum.SetReveal(Mathf.Lerp(beat.revealFrom, beat.revealTo, Mathf.SmoothStep(0f, 1f, t)));
            crystal.SetState(beat.crystal, beat.crystalOffset, Mathf.Lerp(beat.glowFrom, beat.glowTo, t * t));
            foreach (var b in m_Behaviours) b.Evaluate(b.beatId == beat.id, t);
            ApplyFade(index, beat);
        }

        void EnterBeat(int index, Beat beat)
        {
            BeatIndex = index;
            environments.Show(beat.environmentId);

            voiceSource.Stop();
            var clip = language == Language.Arabic ? beat.voiceClipAr : beat.voiceClipEn;
            if (clip != null)
            {
                voiceSource.clip = clip;
                voiceSource.Play();
            }
            Debug.Log($"[MOI] Beat {index + 1:00} {beat.title} @ {Clock:0.0}s");
            BeatEntered?.Invoke(beat);
        }

        // A transition straddles its cut: fade out over the tail of the previous beat, back in over
        // the head of the new one. Computed from the clock so it is correct after a seek as well.
        void ApplyFade(int index, Beat beat)
        {
            float amount = 0f;
            var kind = TransitionKind.FadeBlack;

            if (beat.transitionIn != TransitionKind.Cut)
            {
                float half = beat.transitionDuration * 0.5f;
                amount = 1f - Mathf.InverseLerp(beat.start, beat.start + half, Clock);
                kind = beat.transitionIn;
            }
            if (index + 1 < sequence.beats.Count)
            {
                var next = sequence.beats[index + 1];
                if (next.transitionIn != TransitionKind.Cut)
                {
                    float half = next.transitionDuration * 0.5f;
                    float outgoing = Mathf.InverseLerp(next.start - half, next.start, Clock);
                    if (outgoing > amount) { amount = outgoing; kind = next.transitionIn; }
                }
            }
            fader.Set(kind == TransitionKind.FadeWhite ? Color.white : Color.black, Mathf.SmoothStep(0f, 1f, amount));
        }
    }
}
