using UnityEngine;
using UnityEngine.InputSystem;

namespace MOI
{
    /// <summary>
    /// Laser pointers for both controllers plus a gaze ray, aimed at VRButtons. Deliberately tiny:
    /// the experience has two buttons, so this avoids pulling a full interaction framework into the scene.
    /// </summary>
    public class VRPointer : MonoBehaviour
    {
        [Tooltip("Controller poses are reported in this space (the rig's camera offset).")]
        public Transform trackingSpace;
        public Camera head;
        public LineRenderer leftRay;
        public LineRenderer rightRay;
        public float maxDistance = 12f;
        public LayerMask buttonLayers = ~0;
        [Tooltip("Set false while nobody is wearing the headset, so a headset lying on a desk 'looking' at START can't press it.")]
        public bool gazeEnabled = true;

        class Hand
        {
            public InputAction aimPosition, aimRotation, gripPosition, gripRotation, trigger;
            public LineRenderer ray;
        }

        Hand[] m_Hands;
        VRButton m_LastHovered;

        void Awake()
        {
            m_Hands = new[] { MakeHand("{LeftHand}", leftRay), MakeHand("{RightHand}", rightRay) };
        }

        static Hand MakeHand(string usage, LineRenderer ray)
        {
            string device = "<XRController>" + usage + "/";
            return new Hand
            {
                // Aim pose where the profile provides one, grip pose otherwise.
                aimPosition = new InputAction(binding: device + "pointerPosition", expectedControlType: "Vector3"),
                aimRotation = new InputAction(binding: device + "pointerRotation", expectedControlType: "Quaternion"),
                gripPosition = new InputAction(binding: device + "devicePosition", expectedControlType: "Vector3"),
                gripRotation = new InputAction(binding: device + "deviceRotation", expectedControlType: "Quaternion"),
                trigger = new InputAction(type: InputActionType.Button, binding: device + "{TriggerButton}"),
                ray = ray,
            };
        }

        void OnEnable()
        {
            foreach (var h in m_Hands) { h.aimPosition.Enable(); h.aimRotation.Enable(); h.gripPosition.Enable(); h.gripRotation.Enable(); h.trigger.Enable(); }
        }

        void OnDisable()
        {
            foreach (var h in m_Hands) { h.aimPosition.Disable(); h.aimRotation.Disable(); h.gripPosition.Disable(); h.gripRotation.Disable(); h.trigger.Disable(); }
            if (leftRay != null) leftRay.enabled = false;
            if (rightRay != null) rightRay.enabled = false;
        }

        void Update()
        {
            VRButton hovered = null;
            bool clicked = false;
            bool handAiming = false;

            foreach (var hand in m_Hands)
            {
                if (!TryGetRay(hand, out var ray))
                {
                    hand.ray.enabled = false;
                    continue;
                }
                var button = Cast(ray, out float distance);
                hand.ray.enabled = true;
                hand.ray.SetPosition(0, ray.origin);
                hand.ray.SetPosition(1, ray.GetPoint(button != null ? distance : 2.5f));
                if (button == null) continue;
                hovered = button;
                handAiming = true;
                clicked |= hand.trigger.WasPressedThisFrame();
            }

            var mouse = Mouse.current;
            if (hovered == null && mouse != null && Application.isEditor)
            {
                var button = Cast(head.ScreenPointToRay(mouse.position.ReadValue()), out _);
                if (button != null && mouse.leftButton.wasPressedThisFrame) { hovered = button; handAiming = true; clicked = true; }
            }

            if (hovered == null && gazeEnabled)
                hovered = Cast(new Ray(head.transform.position, head.transform.forward), out _);

            if (m_LastHovered != null && m_LastHovered != hovered) m_LastHovered.SetHover(false, false);
            m_LastHovered = hovered;
            if (hovered == null) return;
            hovered.SetHover(true, !handAiming);
            if (clicked) hovered.Click();
        }

        bool TryGetRay(Hand hand, out Ray ray)
        {
            bool aim = hand.aimPosition.controls.Count > 0 && hand.aimRotation.controls.Count > 0;
            var position = (aim ? hand.aimPosition : hand.gripPosition).ReadValue<Vector3>();
            var rotation = (aim ? hand.aimRotation : hand.gripRotation).ReadValue<Quaternion>();
            // An untracked or absent controller reports a zero pose.
            if (position == Vector3.zero || rotation.x == 0f && rotation.y == 0f && rotation.z == 0f && rotation.w == 0f)
            {
                ray = default;
                return false;
            }
            ray = new Ray(trackingSpace.TransformPoint(position), trackingSpace.rotation * rotation * Vector3.forward);
            return true;
        }

        VRButton Cast(Ray ray, out float distance)
        {
            distance = maxDistance;
            if (!Physics.Raycast(ray, out var hit, maxDistance, buttonLayers, QueryTriggerInteraction.Collide)) return null;
            distance = hit.distance;
            return hit.collider.GetComponentInParent<VRButton>();
        }
    }
}
