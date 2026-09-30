using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.XR.Management;
using UnityEditor.XR.Management.Metadata;
using UnityEditor.XR.OpenXR.Features;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.XR.Management;
using UnityEngine.XR.OpenXR;

namespace MOI.EditorTools
{
    /// <summary>
    /// One-click project configuration for VIVE Focus 3 / Focus Vision / XR Elite (the OpenXR-based
    /// VIVE standalone line). Everything here is also reachable by hand under Project Settings; this
    /// just makes a fresh clone build-ready without a checklist.
    /// </summary>
    [InitializeOnLoad]
    public static class MoiProjectSetup
    {
        const string PromptedKey = "MOI.SetupPrompted";
        const string MobilePipelineAsset = "Assets/Settings/Mobile_RPAsset.asset";
        const string OpenXRLoader = "UnityEngine.XR.OpenXR.OpenXRLoader";

        static MoiProjectSetup()
        {
            EditorApplication.delayCall += OfferFirstTimeSetup;
        }

        static void OfferFirstTimeSetup()
        {
            if (Application.isBatchMode || SessionState.GetBool(PromptedKey, false)) return;
            if (File.Exists(MoiSceneBuilder.ScenePath)) return;
            if (EditorApplication.isCompiling || EditorApplication.isUpdating)
            {
                EditorApplication.delayCall += OfferFirstTimeSetup;
                return;
            }
            SessionState.SetBool(PromptedKey, true);

            if (EditorUtility.DisplayDialog("MOI - The Promise of Safety",
                    "Set this project up for VIVE Focus now?\n\n" +
                    "- switches the platform to Android (reimports assets, takes a few minutes)\n" +
                    "- enables OpenXR with VIVE XR Support\n" +
                    "- generates the experience scene from the storyboard\n\n" +
                    "You can run these later from the MOI menu.",
                    "Set up", "Not now"))
            {
                // Queued rather than called: switching platform triggers a domain reload that would
                // abort a scene build chained directly after it.
                MoiEditorCommands.Queue(MoiEditorCommands.BuildScene);
                ConfigureProject();
            }
        }

        [MenuItem("MOI/1. Configure Project for VIVE Focus", priority = 1)]
        public static void ConfigureProject()
        {
            if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android &&
                !EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android))
            {
                EditorUtility.DisplayDialog("Android module missing", "Could not switch to Android. Install Android Build Support (with SDK/NDK and OpenJDK) for this editor from Unity Hub.", "OK");
                return;
            }

            ConfigurePlayer();
            ConfigurePipeline();
            string xrReport = ConfigureXR();

            AssetDatabase.SaveAssets();
            Debug.Log("[MOI] Project configured for VIVE Focus.\n" + xrReport);
        }

        static void ConfigurePlayer()
        {
            var android = NamedBuildTarget.Android;
            PlayerSettings.companyName = "GameX";
            PlayerSettings.productName = "MOI Promise of Safety";
            PlayerSettings.SetApplicationIdentifier(android, "com.gamex.moi.promiseofsafety");
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            // Focus 3 ships Android 10.
            PlayerSettings.Android.minSdkVersion = (AndroidSdkVersions)29;
            PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
            PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.Vulkan, GraphicsDeviceType.OpenGLES3 });
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.stripEngineCode = true;
            // The content server is plain HTTP on the museum LAN; Android blocks cleartext unless told otherwise.
            PlayerSettings.insecureHttpOption = InsecureHttpOption.AlwaysAllowed;
            PlayerSettings.Android.forceInternetPermission = true;
            // Lets the app read a film copied to /sdcard/MOI (the app's own folder needs no permission).
            PlayerSettings.Android.forceSDCardPermission = true;
            EditorUserBuildSettings.androidBuildSubtarget = MobileTextureSubtarget.ASTC;
        }

        // Every surface in the experience is unlit, so the pipeline is stripped down to what a
        // 90 Hz mobile XR2 budget wants: MSAA for edges, no HDR / shadows / depth or colour copies.
        static void ConfigurePipeline()
        {
            var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(MobilePipelineAsset);
            if (pipeline == null)
            {
                Debug.LogWarning("[MOI] " + MobilePipelineAsset + " not found - URP settings left unchanged.");
                return;
            }
            pipeline.msaaSampleCount = 4;
            pipeline.supportsHDR = false;
            pipeline.renderScale = 1f;
            pipeline.shadowDistance = 0f;
            pipeline.supportsCameraDepthTexture = false;
            pipeline.supportsCameraOpaqueTexture = false;
            EditorUtility.SetDirty(pipeline);
        }

        static string ConfigureXR()
        {
            // Windows too, so Play mode streams to the headset through VIVE Streaming Hub (SteamVR-style
            // iteration). The shipped product is the standalone Android build.
            string pc = ConfigureXR(BuildTargetGroup.Standalone);
            return ConfigureXR(BuildTargetGroup.Android) + "\nWindows (Play mode via VIVE Streaming Hub): " + pc;
        }

        static string ConfigureXR(BuildTargetGroup group)
        {

            if (!EditorBuildSettings.TryGetConfigObject(XRGeneralSettings.k_SettingsKey, out XRGeneralSettingsPerBuildTarget perTarget) || perTarget == null)
            {
                Directory.CreateDirectory("Assets/XR");
                perTarget = ScriptableObject.CreateInstance<XRGeneralSettingsPerBuildTarget>();
                AssetDatabase.CreateAsset(perTarget, "Assets/XR/XRGeneralSettingsPerBuildTarget.asset");
                EditorBuildSettings.AddConfigObject(XRGeneralSettings.k_SettingsKey, perTarget, true);
            }
            if (!perTarget.HasSettingsForBuildTarget(group)) perTarget.CreateDefaultSettingsForBuildTarget(group);
            if (!perTarget.HasManagerSettingsForBuildTarget(group)) perTarget.CreateDefaultManagerSettingsForBuildTarget(group);

            var general = perTarget.SettingsForBuildTarget(group);
            general.InitManagerOnStart = true;
            if (!XRPackageMetadataStore.AssignLoader(general.Manager, OpenXRLoader, group))
                return "OpenXR loader could not be assigned - enable it under Project Settings > XR Plug-in Management > " + group + ".";
            EditorUtility.SetDirty(general);
            EditorUtility.SetDirty(perTarget);

            var openXR = OpenXRSettings.GetSettingsForBuildTargetGroup(group);
            if (openXR == null)
                return "OpenXR settings not created yet - open Project Settings > XR Plug-in Management > OpenXR once, then run this again.";
            openXR.renderMode = OpenXRSettings.RenderMode.SinglePassInstanced;

            // Matched by display name so this file has no compile-time dependency on the VIVE package.
            FeatureHelpers.RefreshFeatures(group);
            bool support = false, controller = false;
            foreach (var feature in openXR.GetFeatures())
            {
                var info = (OpenXRFeatureAttribute)Attribute.GetCustomAttribute(feature.GetType(), typeof(OpenXRFeatureAttribute));
                if (info == null) continue;
                bool isSupport = info.UiName == "VIVE XR Support";
                bool isController = info.UiName == "VIVE Focus 3 Controller Interaction";
                // Streamed through SteamVR / VIVE Streaming Hub the controllers can show up under a
                // generic profile, so on Windows enable the usual suspects too. Our bindings only use
                // generic usages (TriggerButton, GripButton, PrimaryButton, MenuButton) so any of them works.
                bool isPcProfile = group == BuildTargetGroup.Standalone && (
                    info.UiName == "HTC Vive Controller Profile" || info.UiName == "Valve Index Controller Profile" ||
                    info.UiName == "Oculus Touch Controller Profile" || info.UiName == "Khronos Simple Controller Profile");
                if (!isSupport && !isController && !isPcProfile) continue;
                feature.enabled = true;
                EditorUtility.SetDirty(feature);
                support |= isSupport;
                controller |= isController;
            }
            EditorUtility.SetDirty(openXR);

            if (group == BuildTargetGroup.Standalone)
                return controller ? "OpenXR on, VIVE Focus 3 Controller Interaction enabled." : "OpenXR on, but the VIVE Focus 3 controller profile was not found.";
            return support && controller
                ? "OpenXR: single-pass instanced, VIVE XR Support + VIVE Focus 3 Controller Interaction enabled."
                : "OpenXR is on, but VIVE features were not found (support=" + support + ", controller=" + controller + "). " +
                  "Check that the VIVE OpenXR Plugin resolved in Package Manager, then run this again.";
        }
    }
}
