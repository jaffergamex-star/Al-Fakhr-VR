using UnityEngine;

namespace MOI
{
    /// <summary>
    /// Beat 4, "Preserving the Legacy": archive photographs and documents surface out of the dark
    /// around the crystal, then give up motes of light that stream into it.
    /// Panels and motes are pre-built children (see MoiSceneBuilder) so nothing is allocated at runtime.
    /// Drop the museum's real archive images into <see cref="photos"/>; blank cards are used until then.
    /// </summary>
    public class MemoryGallery : BeatBehaviour
    {
        static readonly int FadeId = Shader.PropertyToID("_Fade");
        static readonly int MainTexId = Shader.PropertyToID("_MainTex");

        public Transform crystal;
        public Renderer[] panels;
        public Renderer[] motes;
        public Texture[] photos;
        [Tooltip("Fraction of the beat over which panels stagger in.")]
        public float staggerWindow = 0.45f;
        public float moteCycleSeconds = 2.4f;

        Vector3[] m_Home;
        MaterialPropertyBlock m_Block;
        bool m_WasActive;

        void Awake()
        {
            m_Block = new MaterialPropertyBlock();
            m_Home = new Vector3[panels.Length];
            for (int i = 0; i < panels.Length; i++)
            {
                m_Home[i] = panels[i].transform.position;
                if (photos != null && photos.Length > 0)
                {
                    panels[i].GetPropertyBlock(m_Block);
                    m_Block.SetTexture(MainTexId, photos[i % photos.Length]);
                    panels[i].SetPropertyBlock(m_Block);
                }
            }
            SetVisible(false);
        }

        public override void Evaluate(bool active, float t)
        {
            if (active != m_WasActive)
            {
                m_WasActive = active;
                SetVisible(active);
            }
            if (!active || crystal == null) return;

            // Everything has dissolved into the crystal by the end of the beat.
            float exit = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.85f, 1f, t));
            for (int i = 0; i < panels.Length; i++)
            {
                float delay = staggerWindow * i / Mathf.Max(1, panels.Length - 1);
                float appear = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(delay, delay + 0.18f, t));
                var p = panels[i];
                // Panels drift out from the crystal to their resting place.
                p.transform.position = Vector3.Lerp(crystal.position, m_Home[i], 0.35f + 0.65f * appear);
                SetFade(p, appear * exit);

                int perPanel = motes.Length / Mathf.Max(1, panels.Length);
                for (int m = 0; m < perPanel; m++)
                {
                    var mote = motes[i * perPanel + m];
                    float phase = Mathf.Repeat(Time.time / moteCycleSeconds + (i * 0.37f + m * 0.5f), 1f);
                    var from = m_Home[i];
                    var mid = Vector3.Lerp(from, crystal.position, 0.5f) + Vector3.up * (0.4f + 0.2f * m);
                    mote.transform.position = Bezier(from, mid, crystal.position, phase);
                    SetFade(mote, appear * exit * Mathf.Sin(phase * Mathf.PI));
                }
            }
        }

        static Vector3 Bezier(Vector3 a, Vector3 b, Vector3 c, float t)
        {
            return Vector3.Lerp(Vector3.Lerp(a, b, t), Vector3.Lerp(b, c, t), t);
        }

        void SetFade(Renderer r, float fade)
        {
            r.GetPropertyBlock(m_Block);
            m_Block.SetFloat(FadeId, fade);
            r.SetPropertyBlock(m_Block);
        }

        void SetVisible(bool visible)
        {
            foreach (var p in panels) p.enabled = visible;
            foreach (var m in motes) m.enabled = visible;
        }
    }
}
