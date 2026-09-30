using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.XR;

namespace MOI
{
    /// <summary>
    /// PC VR build: what the wall screen shows. Unity's default is a copy of the left eye, whose picture is off-centre
    /// (the lens sits towards the nose), so the wall looked turned to the right. Instead a plain extra camera renders the
    /// visitor's view straight ahead, centred, with a symmetric field of view at the window's own shape (3096x1290 at
    /// the museum). Horizontal field of view: -wallfov N on the command line (default 75, close to the headset mirror).
    /// Only while the VR runtime is active; without it the normal window stays as it is.
    /// </summary>
    public class WallView : MonoBehaviour
    {
        const float DefaultHorizontalFov = 75f;

        Camera m_Head, m_Wall;
        float m_HorizontalFov = DefaultHorizontalFov;
        bool m_Active;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Install()
        {
            if (Application.platform != RuntimePlatform.WindowsPlayer) return;
            var go = new GameObject("MOI wall view");
            DontDestroyOnLoad(go);
            go.AddComponent<WallView>();
        }

        void Start()
        {
            string[] args = System.Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length - 1; i++)
                if (string.Equals(args[i], "-wallfov", System.StringComparison.OrdinalIgnoreCase) && float.TryParse(args[i + 1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float fov))
                    m_HorizontalFov = Mathf.Clamp(fov, 30f, 120f);

            m_Head = Camera.main;
            if (m_Head == null) { Debug.LogWarning("[MOI] Wall view: no main camera"); return; }

            var go = new GameObject("Wall Camera");
            go.transform.SetParent(transform, false);
            m_Wall = go.AddComponent<Camera>();
            m_Wall.stereoTargetEye = StereoTargetEyeMask.None;
            m_Wall.targetDisplay = 0;
            m_Wall.depth = m_Head.depth + 1;
            m_Wall.nearClipPlane = m_Head.nearClipPlane;
            m_Wall.farClipPlane = m_Head.farClipPlane;
            m_Wall.cullingMask = m_Head.cullingMask;
            m_Wall.backgroundColor = m_Head.backgroundColor;
            var data = go.AddComponent<UniversalAdditionalCameraData>();
            data.renderPostProcessing = false;
            data.renderShadows = false;
            // URP decides by this flag, not by stereoTargetEye: off = this camera draws to the window, not into the headset.
            data.allowXRRendering = false;
            m_Wall.enabled = false;
            Debug.Log($"[MOI] Wall view ready: {m_HorizontalFov:F0} degrees wide, centred on the visitor's view");
        }

        void LateUpdate()
        {
            if (m_Wall == null) return;
            bool active = XRSettings.isDeviceActive;
            if (active != m_Active)
            {
                m_Active = active;
                m_Wall.enabled = active;
                // With the wall camera drawing the window, the left-eye copy must not draw over it.
                XRSettings.gameViewRenderMode = active ? GameViewRenderMode.None : GameViewRenderMode.LeftEye;
                Debug.Log(active ? "[MOI] Wall view on: the window shows the visitor's view straight ahead" : "[MOI] Wall view off: VR runtime not active");
            }
            if (!active) return;
            m_Wall.transform.SetPositionAndRotation(m_Head.transform.position, m_Head.transform.rotation);
            m_Wall.clearFlags = m_Head.clearFlags;
            m_Wall.backgroundColor = m_Head.backgroundColor;
            // Symmetric field of view: the given width, the height from the window's shape.
            float aspect = (float)Screen.width / Mathf.Max(1, Screen.height);
            float halfWidthTan = Mathf.Tan(m_HorizontalFov * 0.5f * Mathf.Deg2Rad);
            m_Wall.fieldOfView = 2f * Mathf.Atan(halfWidthTan / aspect) * Mathf.Rad2Deg;
        }
    }
}
