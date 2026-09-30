using UnityEngine;

namespace MOI
{
    /// <summary>
    /// The crystal is one persistent object for the whole journey: it rests on the museum podium,
    /// lifts off to guide the visitor through the future scenes, and settles back at the end.
    /// </summary>
    public class CrystalGuide : MonoBehaviour
    {
        static readonly int GlowId = Shader.PropertyToID("_Glow");
        static readonly int ColorId = Shader.PropertyToID("_Color");

        public Transform podiumAnchor;
        [Tooltip("Floating offsets are measured from here (the visitor's start spot).")]
        public Transform visitorOrigin;
        public Renderer body;
        public Renderer halo;
        public float podiumScale = 0.75f;
        public float floatingScale = 1.5f;
        public float moveSmoothTime = 1.2f;
        public float spinDegreesPerSecond = 12f;
        public Color haloColor = new Color(0.25f, 0.5f, 1f, 1f);

        CrystalMode m_Mode = CrystalMode.OnPodium;
        Vector3 m_FloatOffset;
        Vector3 m_Velocity;
        float m_ScaleVelocity;
        float m_Glow = 1f;
        MaterialPropertyBlock m_Block;
        Renderer[] m_Renderers;

        void Awake()
        {
            m_Block = new MaterialPropertyBlock();
            m_Renderers = GetComponentsInChildren<Renderer>(true);
            SnapToTarget();
        }

        public void SetState(CrystalMode mode, Vector3 floatOffset, float glow)
        {
            bool wasHidden = m_Mode == CrystalMode.Hidden;
            m_Mode = mode;
            m_FloatOffset = floatOffset;
            m_Glow = glow;

            bool visible = mode != CrystalMode.Hidden;
            if (body.enabled != visible)
                foreach (var r in m_Renderers) r.enabled = visible;
            // Coming back from hidden: arrive from above rather than popping in place.
            if (wasHidden && visible)
            {
                transform.position = TargetPosition() + Vector3.up * 1.2f;
                m_Velocity = Vector3.zero;
            }
        }

        public void SnapToTarget()
        {
            transform.position = TargetPosition();
            transform.localScale = Vector3.one * TargetScale();
            m_Velocity = Vector3.zero;
        }

        Vector3 TargetPosition()
        {
            if (m_Mode == CrystalMode.Floating && visitorOrigin != null)
                return visitorOrigin.TransformPoint(m_FloatOffset);
            return podiumAnchor != null ? podiumAnchor.position : transform.position;
        }

        float TargetScale() => m_Mode == CrystalMode.Floating ? floatingScale : podiumScale;

        void Update()
        {
            var target = TargetPosition();
            if (m_Mode == CrystalMode.Floating)
                target.y += Mathf.Sin(Time.time * 0.9f) * 0.06f;

            transform.position = Vector3.SmoothDamp(transform.position, target, ref m_Velocity, moveSmoothTime);
            float scale = Mathf.SmoothDamp(transform.localScale.x, TargetScale(), ref m_ScaleVelocity, moveSmoothTime);
            transform.localScale = Vector3.one * scale;
            transform.Rotate(Vector3.up, spinDegreesPerSecond * Time.deltaTime, Space.World);

            // A slow heartbeat on top of whatever level the director asked for.
            float pulse = m_Glow * (1f + 0.18f * Mathf.Sin(Time.time * 2.1f));
            body.GetPropertyBlock(m_Block);
            m_Block.SetFloat(GlowId, pulse);
            body.SetPropertyBlock(m_Block);

            halo.GetPropertyBlock(m_Block);
            var glow = haloColor * Mathf.Clamp(pulse * 1.6f, 0f, 8f);
            glow.a = 1f;
            m_Block.SetColor(ColorId, glow);
            halo.SetPropertyBlock(m_Block);
            halo.transform.localScale = Vector3.one * (1.6f + pulse * 0.5f);
        }
    }
}
