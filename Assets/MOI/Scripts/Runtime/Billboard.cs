using UnityEngine;

namespace MOI
{
    /// <summary>Keeps a quad facing the viewer (halos, motes).</summary>
    public class Billboard : MonoBehaviour
    {
        Transform m_Head;

        void LateUpdate()
        {
            if (m_Head == null)
            {
                var cam = Camera.main;
                if (cam == null) return;
                m_Head = cam.transform;
            }
            transform.rotation = Quaternion.LookRotation(transform.position - m_Head.position, Vector3.up);
        }
    }
}
