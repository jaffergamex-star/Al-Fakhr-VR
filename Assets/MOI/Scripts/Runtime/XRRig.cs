using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.XR;
using UnityEngine.XR;

namespace MOI
{
    /// <summary>
    /// Minimal head-tracked rig for a passive, standing experience: floor-level tracking origin, head
    /// pose on the camera, and a recentre that puts the visitor on the start spot facing the crystal.
    /// In the editor without a headset it falls back to eye height plus right-mouse look.
    /// </summary>
    public class XRRig : MonoBehaviour
    {
        public Transform cameraOffset;
        public Camera head;
        [Tooltip("Where the visitor should stand and face when the journey begins.")]
        public Transform startSpot;
        public float desktopEyeHeight = 1.6f;

        static readonly List<XRInputSubsystem> s_InputSubsystems = new List<XRInputSubsystem>();
        TrackedPoseDriver m_Driver;
        bool m_FloorOriginSet;
        Vector2 m_DesktopLook;

        public bool HeadsetActive => XRSettings.isDeviceActive;

        void Awake()
        {
            var driver = m_Driver = head.gameObject.AddComponent<TrackedPoseDriver>();
            driver.trackingType = TrackedPoseDriver.TrackingType.RotationAndPosition;
            driver.updateType = TrackedPoseDriver.UpdateType.UpdateAndBeforeRender;
            driver.positionInput = new InputActionProperty(new InputAction("Head Position", InputActionType.Value, "<XRHMD>/centerEyePosition", expectedControlType: "Vector3"));
            driver.rotationInput = new InputActionProperty(new InputAction("Head Rotation", InputActionType.Value, "<XRHMD>/centerEyeRotation", expectedControlType: "Quaternion"));
        }

        void Update()
        {
            if (!m_FloorOriginSet) TrySetFloorOrigin();
            // With no headset the driver would keep writing an identity pose over the desktop camera.
            m_Driver.enabled = HeadsetActive;
            if (!HeadsetActive) DesktopFallback();
        }

        void TrySetFloorOrigin()
        {
            SubsystemManager.GetSubsystems(s_InputSubsystems);
            foreach (var subsystem in s_InputSubsystems)
                if (subsystem.TrySetTrackingOriginMode(TrackingOriginModeFlags.Floor))
                    m_FloorOriginSet = true;
        }

        void DesktopFallback()
        {
            var mouse = Mouse.current;
            if (mouse != null && mouse.rightButton.isPressed)
            {
                var delta = mouse.delta.ReadValue() * 0.15f;
                m_DesktopLook.x = Mathf.Clamp(m_DesktopLook.x - delta.y, -80f, 80f);
                m_DesktopLook.y += delta.x;
            }
            head.transform.localPosition = new Vector3(0f, desktopEyeHeight, 0f);
            head.transform.localRotation = Quaternion.Euler(m_DesktopLook.x, m_DesktopLook.y, 0f);
        }

        /// <summary>
        /// Yaw and slide the rig so the head sits above the start spot looking down its forward axis.
        /// Height is left alone so the floor stays the real floor.
        /// </summary>
        public void Recenter()
        {
            if (startSpot == null) return;
            m_DesktopLook = Vector2.zero;

            var headForward = Vector3.ProjectOnPlane(head.transform.forward, Vector3.up);
            var targetForward = Vector3.ProjectOnPlane(startSpot.forward, Vector3.up);
            if (headForward.sqrMagnitude > 0.0001f && targetForward.sqrMagnitude > 0.0001f)
            {
                float yaw = Vector3.SignedAngle(headForward, targetForward, Vector3.up);
                transform.RotateAround(head.transform.position, Vector3.up, yaw);
            }

            var offset = startSpot.position - head.transform.position;
            offset.y = 0f;
            transform.position += offset;
        }
    }
}
