using UnityEngine;

namespace MOI
{
    /// <summary>Head-locked fade. The director sets colour and amount every frame from the master clock.</summary>
    [RequireComponent(typeof(MeshRenderer))]
    public class ScreenFader : MonoBehaviour
    {
        static readonly int ColorId = Shader.PropertyToID("_Color");

        MeshRenderer m_Renderer;
        MaterialPropertyBlock m_Block;

        void Awake()
        {
            m_Renderer = GetComponent<MeshRenderer>();
            m_Block = new MaterialPropertyBlock();
            Set(Color.black, 0f);
        }

        public void Set(Color color, float amount)
        {
            amount = Mathf.Clamp01(amount);
            // Skip the full-screen overdraw entirely when there's nothing to draw.
            m_Renderer.enabled = amount > 0.002f;
            if (!m_Renderer.enabled) return;
            color.a = amount;
            m_Block.SetColor(ColorId, color);
            m_Renderer.SetPropertyBlock(m_Block);
        }
    }
}
