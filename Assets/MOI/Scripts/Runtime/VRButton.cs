using TMPro;
using UnityEngine;
using UnityEngine.Events;

namespace MOI
{
    /// <summary>
    /// A world-space button. Pressed by a controller ray + trigger, by looking at it for a moment
    /// (visitors often aren't holding controllers), or by mouse in the editor. See VRPointer.
    /// </summary>
    [RequireComponent(typeof(Collider))]
    public class VRButton : MonoBehaviour
    {
        static readonly int ColorId = Shader.PropertyToID("_Color");

        public Renderer plate;
        public TextMeshPro label;
        public Color normalColor = new Color(0.04f, 0.14f, 0.38f, 0.96f);
        public Color hoverColor = new Color(0.15f, 0.45f, 1f, 1f);
        [Tooltip("Seconds of steady gaze that count as a press. 0 disables gaze pressing.")]
        public float gazeDwellSeconds = 2f;
        public UnityEvent onClick = new UnityEvent();

        MaterialPropertyBlock m_Block;
        bool m_Hovered;
        float m_Dwell;

        void Awake() => m_Block = new MaterialPropertyBlock();

        void OnEnable()
        {
            m_Hovered = false;
            m_Dwell = 0f;
            Paint(0f);
        }

        /// <summary>Called every frame by VRPointer. <paramref name="gazeOnly"/>: nothing but the head is aiming here.</summary>
        public void SetHover(bool hovered, bool gazeOnly)
        {
            m_Hovered = hovered;
            m_Dwell = hovered && gazeOnly && gazeDwellSeconds > 0f ? m_Dwell + Time.deltaTime : 0f;
            Paint(hovered ? Mathf.Max(0.5f, gazeDwellSeconds > 0f ? m_Dwell / gazeDwellSeconds : 0f) : 0f);
            if (gazeDwellSeconds > 0f && m_Dwell >= gazeDwellSeconds) Click();
        }

        public void Click()
        {
            m_Dwell = 0f;
            onClick.Invoke();
        }

        void Paint(float amount)
        {
            if (plate == null) return;
            plate.GetPropertyBlock(m_Block);
            m_Block.SetColor(ColorId, Color.Lerp(normalColor, hoverColor, amount));
            plate.SetPropertyBlock(m_Block);
        }
    }
}
