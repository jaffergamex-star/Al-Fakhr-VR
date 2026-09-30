using UnityEngine;

namespace MOI
{
    /// <summary>
    /// Owns the museum's lit / outline / dark state. It's a shader global rather than per-material
    /// so every surface in the room (wall, parapet, strips, floor) follows one value.
    /// </summary>
    [ExecuteAlways]
    public class MuseumRoom : MonoBehaviour
    {
        static readonly int RevealId = Shader.PropertyToID("_MOI_Reveal");

        [Range(0f, 1f)] public float reveal = 1f;

        void OnEnable() => Apply();
        void OnValidate() => Apply();

        public void SetReveal(float value)
        {
            reveal = Mathf.Clamp01(value);
            Apply();
        }

        void Apply() => Shader.SetGlobalFloat(RevealId, reveal);
    }
}
