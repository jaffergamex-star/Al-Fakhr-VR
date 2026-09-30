using System.Collections;
using UnityEngine;
using UnityEngine.XR.Management;
using UnityEngine.XR.OpenXR;

namespace MOI
{
    /// <summary>
    /// PC VR build only (the app runs on the PC and is streamed to the headset by VIVE Streaming / SteamVR). The app
    /// can start before the headset is connected; then there is no VR runtime and it runs as a plain window. Two
    /// things for that case:
    /// - it is capped at 60 fps: uncapped it takes the whole graphics card, which starved the visitor station
    ///   running next to it;
    /// - it keeps looking for the VR runtime every 10 s and goes into VR as soon as it is there, turned to face the
    ///   visitor - no restart needed.
    /// </summary>
    public class PcVrRuntime : MonoBehaviour
    {
        const float RetrySeconds = 10f;

        /// <summary>
        /// Whether the PC's VR runtime reports if the headset is worn (XR_EXT_user_presence). null until the runtime is
        /// up. Without it the station gets no worn/not-worn signal and falls back to its timers.
        /// </summary>
        public static bool? PresenceSupported { get; private set; }

        static void NotePresence()
        {
            PresenceSupported = OpenXRRuntime.IsExtensionEnabled("XR_EXT_user_presence");
            Debug.Log(PresenceSupported == true
                ? "[MOI] VR runtime reports whether the headset is worn (user presence supported)"
                : "[MOI] VR runtime does NOT report whether the headset is worn (no XR_EXT_user_presence) - the station works on timers");
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Install()
        {
            if (Application.platform != RuntimePlatform.WindowsPlayer) return;
            var go = new GameObject("MOI PC VR runtime");
            DontDestroyOnLoad(go);
            go.AddComponent<PcVrRuntime>();
        }

        IEnumerator Start()
        {
            var manager = XRGeneralSettings.Instance != null ? XRGeneralSettings.Instance.Manager : null;
            if (manager == null) yield break;
            if (manager.activeLoader != null)
            {
                Debug.Log("[MOI] VR runtime active: " + manager.activeLoader.name);
                NotePresence();
                yield break;
            }

            Application.targetFrameRate = 60;
            Debug.Log($"[MOI] No VR runtime yet (headset not connected in VIVE Hub / SteamVR?) - running in a window at 60 fps, looking again every {RetrySeconds:F0} s");
            while (manager.activeLoader == null)
            {
                yield return new WaitForSecondsRealtime(RetrySeconds);
                yield return manager.InitializeLoader();
            }
            manager.StartSubsystems();
            Application.targetFrameRate = -1;
            Debug.Log("[MOI] VR runtime found - now running in the headset: " + manager.activeLoader.name);
            NotePresence();

            // Face START once the head pose has settled.
            yield return new WaitForSecondsRealtime(1f);
            var director = FindAnyObjectByType<ExperienceDirector>();
            if (director != null) director.RequestRecenter();
        }
    }
}
