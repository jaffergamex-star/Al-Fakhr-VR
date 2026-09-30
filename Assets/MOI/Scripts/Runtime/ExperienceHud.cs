using TMPro;
using UnityEngine;

namespace MOI
{
    /// <summary>
    /// In-headset text: the idle prompt by the podium, optional subtitles, and a review timecode.
    /// Subtitles are English only for now: TextMeshPro does not shape Arabic (joining / RTL), so
    /// Arabic subtitles need an RTL shaping pass and an Arabic font asset before they can be shown.
    /// </summary>
    public class ExperienceHud : MonoBehaviour
    {
        public ExperienceDirector director;
        public Transform head;
        [Tooltip("Everything the waiting visitor sees: title, Start and language buttons.")]
        public GameObject idleRoot;
        public VRPointer pointer;
        public TextMeshPro prompt;
        public ContentManager content;
        public TextMeshPro statusLabel;
        public TextMeshPro subtitle;
        public TextMeshPro timecode;
        [Tooltip("Real-time beats only, English text. Off by default: the film carries its own voice-over.")]
        public bool showSubtitles = false;
        [Tooltip("Beat number / title / clock. Forced off in release builds.")]
        public bool showTimecode = true;
        [Tooltip("Looking at START for a moment presses it. Off (client's choice, 2026-09-29): only a controller starts - point + trigger, or A/X.")]
        public bool gazeStart = false;
        public float followDistance = 1.8f;
        public float followSmoothTime = 0.35f;

        Vector3 m_Velocity;
        string m_PromptText;

        // Headset and PC builds: no film on the device -> the title above the podium says so, big enough to read in
        // the headset and on the station's mirror. (The editor keeps its real-time review journey instead.)
        const string FilmMissingPrompt = "THE PROMISE OF SAFETY\n<size=42%><color=#FFB38A>The film is missing on this device.\nPlease call a member of staff.</color>";

        VRButton m_Start;
        BoxCollider m_StartCollider;
        Renderer[] m_StartRenderers;
        Vector3 m_StartLocalPosition, m_StartColliderSize;
        Quaternion m_StartLocalRotation;
        bool m_Hotspot;

        void Start()
        {
            m_PromptText = prompt.text;
            m_Start = idleRoot.GetComponentInChildren<VRButton>(true);
            if (m_Start == null) return;
            m_StartCollider = m_Start.GetComponent<BoxCollider>();
            m_StartRenderers = m_Start.GetComponentsInChildren<Renderer>(true);
            m_StartLocalPosition = m_Start.transform.localPosition;
            m_StartLocalRotation = m_Start.transform.localRotation;
            if (m_StartCollider != null) m_StartColliderSize = m_StartCollider.size;
        }

        // START screen video with START drawn in it: the START button becomes an invisible hotspot over the drawn one.
        // The video is drawn at infinity, so the hotspot moves with the head to stay exactly on it.
        void UpdateStartButton(bool startScreen)
        {
            if (m_Start == null) return;
            var area = director.sequence != null ? director.sequence.startHotspot : default;
            bool hotspot = startScreen && area.Enabled;
            if (hotspot)
            {
                var direction = Quaternion.Euler(-area.pitch, area.yaw, 0f) * Vector3.forward;
                m_Start.transform.SetPositionAndRotation(head.position + direction * area.distance, Quaternion.LookRotation(direction, Vector3.up));
            }
            if (hotspot == m_Hotspot) return;
            m_Hotspot = hotspot;
            foreach (var r in m_StartRenderers) r.enabled = !hotspot;
            if (hotspot)
            {
                if (m_StartCollider != null)
                    m_StartCollider.size = new Vector3(2f * area.distance * Mathf.Tan(area.width * 0.5f * Mathf.Deg2Rad),
                                                       2f * area.distance * Mathf.Tan(area.height * 0.5f * Mathf.Deg2Rad), 0.05f);
            }
            else
            {
                m_Start.transform.localPosition = m_StartLocalPosition;
                m_Start.transform.localRotation = m_StartLocalRotation;
                if (m_StartCollider != null) m_StartCollider.size = m_StartColliderSize;
            }
        }

        void LateUpdate()
        {
            bool idle = director.CurrentState == ExperienceDirector.State.Idle;
            if (idleRoot.activeSelf != idle) idleRoot.SetActive(idle);
            // Lasers only while there is something to point at.
            if (pointer.enabled != idle) pointer.enabled = idle;
            pointer.gazeEnabled = gazeStart && director.IsWorn != false;
            if (idle)
            {
                statusLabel.text = content != null ? content.Status : string.Empty;
                bool missing = content != null && !content.HasFilm && !Application.isEditor;
                string want = missing ? FilmMissingPrompt : m_PromptText;
                if (m_PromptText != null && prompt.text != want) prompt.text = want;
                // START screen video: nothing but the START button over it - the title only comes back to say the film
                // is missing.
                bool startScreen = director.UsesStartScreen;
                bool showPrompt = !startScreen || missing;
                if (prompt.gameObject.activeSelf != showPrompt) prompt.gameObject.SetActive(showPrompt);
                // Content status is a staff/debug line: only in the Unity editor, never in a build.
                bool showStatus = Application.isEditor && !startScreen;
                if (statusLabel.gameObject.activeSelf != showStatus) statusLabel.gameObject.SetActive(showStatus);
                UpdateStartButton(startScreen);
            }

            var beat = director.CurrentBeat;
            bool playing = director.CurrentState == ExperienceDirector.State.Playing && beat != null;

            bool sub = showSubtitles && playing && director.language == Language.English
                       && director.Clock > beat.start + 0.3f && director.Clock < beat.end - 0.2f;
            // Feedback for staff holding the hidden reset; invisible otherwise.
            bool resetting = !idle && director.ResetHoldProgress > 0.4f;
            subtitle.enabled = sub || resetting;
            if (resetting) subtitle.text = "Hold to return to START...";
            else if (sub) subtitle.text = beat.voiceOverEn;

            // Review timecode: Unity editor only - never in a build, not even a development build.
            bool tc = showTimecode && Application.isEditor && playing;
            timecode.enabled = tc;
            if (tc)
            {
                int s = Mathf.FloorToInt(director.Clock);
                timecode.text = $"{director.BeatIndex + 1:00} {beat.title}   {s / 60:00}:{s % 60:00}   [{beat.environmentId}]";
            }

            Follow();
        }

        // Lazy follow: text trails the gaze instead of being glued to the face.
        void Follow()
        {
            var forward = Vector3.ProjectOnPlane(head.forward, Vector3.up);
            if (forward.sqrMagnitude < 0.0001f) return;
            forward.Normalize();
            var target = head.position + forward * followDistance + Vector3.down * 0.55f;
            transform.position = Vector3.SmoothDamp(transform.position, target, ref m_Velocity, followSmoothTime);
            transform.rotation = Quaternion.LookRotation(transform.position - head.position, Vector3.up);
        }
    }
}
