using System;
using System.Collections.Generic;
using System.IO;
using TMPro;
using UnityEditor;
using UnityEditor.Events;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Video;

namespace MOI.EditorTools
{
    /// <summary>
    /// Generates the whole experience scene from code so the blockout is reproducible and diffable.
    /// Re-running rebuilds the scene and generated meshes/materials, but never touches an existing
    /// sequence asset - voice-over clips and timing tweaks made there survive.
    /// </summary>
    public static class MoiSceneBuilder
    {
        public const string Root = "Assets/MOI";
        public const string ScenePath = Root + "/Scenes/PromiseOfSafety.unity";
        public const string SequencePath = Root + "/Data/PromiseOfSafety.asset";
        const string Generated = Root + "/Generated";
        const string TmpSettingsPath = "Assets/TextMesh Pro/Resources/TMP Settings.asset";

        static readonly Vector3 RoomCentre = new Vector3(0f, 0f, 2.5f);
        static readonly Vector3 PodiumPosition = new Vector3(0f, 0f, 3.2f);
        const float EyeHeight = 1.6f;

        [MenuItem("MOI/2. Build Experience Scene", priority = 2)]
        public static void BuildFromMenu()
        {
            if (File.Exists(ScenePath) && !EditorUtility.DisplayDialog("Rebuild experience scene?",
                    "This regenerates " + ScenePath + " and discards manual edits made inside it.\n\nThe sequence asset (timings, voice-over clips) is kept.",
                    "Rebuild", "Cancel"))
                return;
            Build();
        }

        [MenuItem("MOI/Reset Sequence From Storyboard", priority = 40)]
        public static void ResetSequence()
        {
            var sequence = AssetDatabase.LoadAssetAtPath<ExperienceSequence>(SequencePath);
            if (sequence == null) { LoadOrCreateSequence(); return; }
            if (!EditorUtility.DisplayDialog("Reset sequence?", "Overwrites every beat with the storyboard values. Assigned voice-over clips are re-attached by beat id.", "Reset", "Cancel"))
                return;

            var clips = new Dictionary<string, (AudioClip en, AudioClip ar)>();
            foreach (var b in sequence.beats) clips[b.id] = (b.voiceClipEn, b.voiceClipAr);
            sequence.beats = StoryboardData.CreateBeats();
            foreach (var b in sequence.beats)
                if (clips.TryGetValue(b.id, out var c)) { b.voiceClipEn = c.en; b.voiceClipAr = c.ar; }
            EditorUtility.SetDirty(sequence);
            AssetDatabase.SaveAssets();
        }

        public static void Build()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            AssetDatabase.Refresh();

            if (!File.Exists(TmpSettingsPath))
            {
                TMP_PackageResourceImporter.ImportResources(true, false, false);
                AssetDatabase.Refresh();
                if (!File.Exists(TmpSettingsPath))
                {
                    EditorUtility.DisplayDialog("TextMeshPro resources", "TMP Essential Resources are being imported. Run MOI > 2. Build Experience Scene again when the import finishes.", "OK");
                    return;
                }
            }

            foreach (var folder in new[] { "Scenes", "Data", "Generated", "Generated/Meshes", "Generated/Materials" })
                Directory.CreateDirectory(Path.Combine(Root, folder));
            AssetDatabase.Refresh();

            var sequence = LoadOrCreateSequence();
            var mats = CreateMaterials();

            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            RenderSettings.skybox = null;
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = Color.black;
            RenderSettings.fog = false;

            var startSpot = new GameObject("Start Spot").transform;

            // --- Rig -------------------------------------------------------------------------
            var rigGo = new GameObject("XR Rig");
            var offset = Child("Camera Offset", rigGo.transform);
            var camGo = Child("Main Camera", offset).gameObject;
            camGo.tag = "MainCamera";
            camGo.transform.localPosition = new Vector3(0f, EyeHeight, 0f);
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = Color.black;
            cam.nearClipPlane = 0.05f;
            cam.farClipPlane = 200f;
            camGo.AddComponent<AudioListener>();
            var camData = camGo.AddComponent<UniversalAdditionalCameraData>();
            camData.renderPostProcessing = false;
            camData.renderShadows = false;

            var faderGo = MeshObject("Screen Fader", camGo.transform, Builtin("Sphere.fbx"), mats.fader, Vector3.zero);
            faderGo.transform.localScale = Vector3.one * 0.4f;
            var fader = faderGo.AddComponent<ScreenFader>();

            var rig = rigGo.AddComponent<XRRig>();
            rig.cameraOffset = offset;
            rig.head = cam;
            rig.startSpot = startSpot;
            rig.desktopEyeHeight = EyeHeight;

            var pointer = rigGo.AddComponent<VRPointer>();
            pointer.trackingSpace = offset;
            pointer.head = cam;
            pointer.leftRay = Ray("Left Ray", offset, mats.ray);
            pointer.rightRay = Ray("Right Ray", offset, mats.ray);

            // --- Museum ----------------------------------------------------------------------
            var museumGo = new GameObject("Museum");
            var museum = museumGo.AddComponent<MuseumRoom>();
            var room = Child("Room", museumGo.transform);
            room.localPosition = RoomCentre;

            MeshObject("Floor", room, SaveMesh(ProcMesh.Disc(7.5f, 64), "Floor"), mats.floor, Vector3.zero);
            MeshObject("LED Wall", room, SaveMesh(ProcMesh.CylinderArc(7f, 1.25f, 4.6f, 220f, 72), "LedWall"), mats.ledWall, Vector3.zero);
            MeshObject("Parapet", room, SaveMesh(ProcMesh.CylinderArc(6.95f, 0f, 1.15f, 360f, 96), "Parapet"), mats.parapet, Vector3.zero);
            var strip = SaveMesh(ProcMesh.CylinderArc(6.9f, -0.04f, 0.04f, 360f, 96), "WallStrip");
            MeshObject("Strip Floor", room, strip, mats.strip, new Vector3(0f, 0.06f, 0f));
            MeshObject("Strip Parapet", room, strip, mats.strip, new Vector3(0f, 1.2f, 0f));
            MeshObject("Strip Ceiling", room, strip, mats.strip, new Vector3(0f, 4.68f, 0f));
            MeshObject("Ceiling Ring", room, SaveMesh(ProcMesh.Annulus(5.5f, 5.8f, 96), "CeilingRing"), mats.strip, new Vector3(0f, 5.1f, 0f));

            var podium = Child("Podium", museumGo.transform);
            podium.localPosition = PodiumPosition;
            // Squat dark plinth, lit plate, open glass tube with a bright lip - as in storyboard frame 1.
            const float baseTop = 0.3f, glassTop = 1.3f;
            MeshObject("Base", podium, SaveMesh(ProcMesh.Cylinder(0.62f, 0f, baseTop, 64, true), "PodiumBase"), mats.podium, Vector3.zero);
            MeshObject("Light Plate", podium, SaveMesh(ProcMesh.Disc(0.34f, 48), "PodiumPlate"), mats.plate, new Vector3(0f, baseTop + 0.004f, 0f));
            MeshObject("Glass", podium, SaveMesh(ProcMesh.Cylinder(0.4f, baseTop, glassTop, 64, false), "PodiumGlass"), mats.glass, Vector3.zero);
            MeshObject("Glass Lip", podium, SaveMesh(ProcMesh.Annulus(0.375f, 0.425f, 64), "PodiumGlassLip"), mats.lip, new Vector3(0f, glassTop, 0f));
            MeshObject("Floor Ring", podium, SaveMesh(ProcMesh.Annulus(0.93f, 1.09f, 64), "FloorRing"), mats.ring, new Vector3(0f, 0.01f, 0f));
            var reflection = MeshObject("Floor Reflection", podium, Builtin("Quad.fbx"), mats.reflection, new Vector3(0f, 0.012f, -1.3f));
            reflection.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);
            reflection.transform.localScale = new Vector3(1.3f, 3.2f, 1f);
            var podiumAnchor = Child("Crystal Anchor", podium);
            podiumAnchor.localPosition = new Vector3(0f, (baseTop + glassTop) * 0.5f, 0f);

            // --- Idle UI: title over the crystal, Start + language buttons on a tilted kiosk ---
            // Not part of the museum: it also stands over the START screen video, with the museum switched off.
            var idleUi = Child("Idle UI", null);
            // The LED wall behind is busy, so the title sits on its own dark plate.
            var prompt = Text("Title", idleUi, 1.35f, new Vector2(2.7f, 0.8f));
            prompt.transform.localPosition = PodiumPosition + new Vector3(0f, 1.95f, -0.2f);
            prompt.color = new Color(0.85f, 0.92f, 1f);
            prompt.text = "THE PROMISE OF SAFETY\n<size=42%>Point at START and pull the trigger, or simply look at it";
            var backing = MeshObject("Backing", prompt.transform, Builtin("Quad.fbx"), mats.promptBack, new Vector3(0f, 0f, 0.02f));
            backing.transform.localScale = new Vector3(2.8f, 0.95f, 1f);

            // Below the natural gaze line on purpose: nobody should gaze-start by accident while settling in.
            var kiosk = Child("Kiosk", idleUi);
            kiosk.localPosition = new Vector3(0f, 1.02f, 1.45f);
            kiosk.localRotation = Quaternion.Euler(38f, 0f, 0f);
            var startButton = Button("Start Button", kiosk, mats.button, "START", 0.62f, new Vector2(0.5f, 0.17f), Vector3.zero);
            var status = Text("Content Status", kiosk, 0.17f, new Vector2(0.9f, 0.05f));
            status.transform.localPosition = new Vector3(0f, 0.125f, 0f); // above START: the bottom of the kiosk is out of the natural view
            status.color = new Color(0.6f, 0.75f, 1f, 0.8f);

            // --- Crystal ---------------------------------------------------------------------
            var crystalGo = MeshObject("Crystal", null, SaveMesh(ProcMesh.Crystal(), "Crystal"), mats.crystal, podiumAnchor.position);
            // A brighter inner gem gives the body some depth without refraction.
            var core = MeshObject("Core", crystalGo.transform, crystalGo.GetComponent<MeshFilter>().sharedMesh, mats.crystalCore, Vector3.zero);
            core.transform.localScale = new Vector3(0.5f, 0.72f, 0.5f);
            core.transform.localRotation = Quaternion.Euler(0f, 30f, 0f);
            var haloGo = MeshObject("Halo", crystalGo.transform, Builtin("Quad.fbx"), mats.glow, Vector3.zero);
            haloGo.AddComponent<Billboard>();
            var crystal = crystalGo.AddComponent<CrystalGuide>();
            crystal.podiumAnchor = podiumAnchor;
            crystal.visitorOrigin = startSpot;
            crystal.body = crystalGo.GetComponent<Renderer>();
            crystal.halo = haloGo.GetComponent<Renderer>();

            // --- Beat 4 gallery ---------------------------------------------------------------
            BuildGallery(mats, crystalGo.transform);

            // --- Previs screen ---------------------------------------------------------------
            // 120 degrees of a 4 m cylinder is 8.38 m of arc; 16:9 makes it 4.71 m tall.
            var previs = MeshObject("Previs Screen", null, SaveMesh(ProcMesh.CylinderArc(4f, -0.35f, 4.36f, 120f, 48), "PrevisScreen"), mats.previs, Vector3.zero);

            // --- Director --------------------------------------------------------------------
            var directorGo = new GameObject("Experience Director");
            var voice = AudioSource2D(Child("Voice Over", directorGo.transform).gameObject);
            var music = AudioSource2D(Child("Music", directorGo.transform).gameObject);
            music.volume = 0.6f;

            var video = directorGo.AddComponent<VideoPlayer>();
            video.playOnAwake = false;
            video.renderMode = VideoRenderMode.RenderTexture;
            video.audioOutputMode = VideoAudioOutputMode.None;

            var environments = directorGo.AddComponent<EnvironmentManager>();
            environments.head = cam;
            environments.previsScreen = previs.GetComponent<Renderer>();
            environments.panoramaSkybox = mats.panorama;
            environments.videoPlayer = video;
            environments.environments.Add(new EnvironmentEntry { id = StoryboardData.Museum, kind = EnvironmentKind.Set, root = museumGo });
            for (int n = 6; n <= 16; n++)
            {
                environments.environments.Add(new EnvironmentEntry
                {
                    id = StoryboardData.PrevisId(n),
                    kind = EnvironmentKind.PrevisFrame,
                    texture = AssetDatabase.LoadAssetAtPath<Texture2D>($"{Root}/Previs/Frames/beat{n:00}.jpg"),
                });
            }

            var content = directorGo.AddComponent<ContentManager>();
            var director = directorGo.AddComponent<ExperienceDirector>();
            content.director = director;
            director.content = content;
            director.sequence = sequence;
            director.rig = rig;
            director.environments = environments;
            director.museum = museum;
            director.crystal = crystal;
            director.fader = fader;
            director.voiceSource = voice;
            director.musicSource = music;
            UnityEventTools.AddPersistentListener(startButton.onClick, director.Begin);

            // --- HUD -------------------------------------------------------------------------
            var hudGo = new GameObject("HUD");
            hudGo.transform.position = new Vector3(0f, EyeHeight - 0.55f, 1.8f);
            var hud = hudGo.AddComponent<ExperienceHud>();
            hud.director = director;
            hud.head = camGo.transform;
            hud.idleRoot = idleUi.gameObject;
            hud.pointer = pointer;
            hud.prompt = prompt;
            hud.content = content;
            hud.statusLabel = status;
            hud.subtitle = Text("Subtitle", hudGo.transform, 0.42f, new Vector2(1.7f, 0.5f));
            hud.timecode = Text("Timecode", hudGo.transform, 0.28f, new Vector2(1.7f, 0.1f));
            hud.timecode.transform.localPosition = new Vector3(0f, -0.3f, 0f);
            hud.timecode.color = new Color(1f, 0.8f, 0.3f);

            EditorSceneManager.SaveScene(scene, ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            AssetDatabase.SaveAssets();
            Debug.Log("[MOI] Scene built: " + ScenePath + ". Press Play: Space starts, arrows skip beats, right-mouse looks around.");
        }

        static void BuildGallery(Materials mats, Transform crystal)
        {
            var galleryGo = new GameObject("Legacy Gallery");
            var gallery = galleryGo.AddComponent<MemoryGallery>();
            gallery.beatId = "legacy";
            gallery.crystal = crystal;

            var quad = Builtin("Quad.fbx");
            var eye = new Vector3(0f, EyeHeight, 0f);
            var random = new System.Random(7);
            var panels = new List<Renderer>();
            var motes = new List<Renderer>();
            const int count = 14;
            for (int i = 0; i < count; i++)
            {
                // Fan across the visitor's forward view, leaving a gap where the crystal stands.
                float side = i % 2 == 0 ? -1f : 1f;
                float angle = side * Mathf.Lerp(14f, 78f, (i / 2) / (count / 2f - 1f));
                float radius = Mathf.Lerp(3.4f, 5.6f, (float)random.NextDouble());
                float height = Mathf.Lerp(0.8f, 3.4f, (float)random.NextDouble());
                var position = Quaternion.Euler(0f, angle, 0f) * Vector3.forward * radius + Vector3.up * height;

                var panel = MeshObject($"Panel {i:00}", galleryGo.transform, quad, mats.card, position);
                float width = Mathf.Lerp(0.9f, 1.7f, (float)random.NextDouble());
                panel.transform.localScale = new Vector3(width, width * 0.72f, 1f);
                panel.transform.rotation = Quaternion.LookRotation(position - eye) * Quaternion.Euler(0f, 0f, Mathf.Lerp(-6f, 6f, (float)random.NextDouble()));
                panels.Add(panel.GetComponent<Renderer>());

                for (int m = 0; m < 2; m++)
                {
                    var mote = MeshObject($"Mote {i:00}.{m}", galleryGo.transform, quad, mats.mote, position);
                    mote.transform.localScale = Vector3.one * 0.14f;
                    mote.AddComponent<Billboard>();
                    motes.Add(mote.GetComponent<Renderer>());
                }
            }
            gallery.panels = panels.ToArray();
            gallery.motes = motes.ToArray();
        }

        static ExperienceSequence LoadOrCreateSequence()
        {
            var sequence = AssetDatabase.LoadAssetAtPath<ExperienceSequence>(SequencePath);
            if (sequence != null) return sequence;
            Directory.CreateDirectory(Path.GetDirectoryName(SequencePath));
            sequence = ScriptableObject.CreateInstance<ExperienceSequence>();
            sequence.beats = StoryboardData.CreateBeats();
            AssetDatabase.CreateAsset(sequence, SequencePath);
            return sequence;
        }

        // ------------------------------------------------------------------------------------

        class Materials
        {
            public Material button, ray;
            public Material floor, parapet, ledWall, strip, podium, plate, glass, lip, ring, reflection, crystal, crystalCore, glow, previs, fader, card, mote, promptBack, panorama;
        }

        static Materials CreateMaterials()
        {
            var glowTex = Tex("T_Glow.png");
            var lineTex = Tex("T_SoftLine.png");
            return new Materials
            {
                floor = Mat("M_Floor", "MOI/Unlit", m => { Opaque(m); m.SetColor("_Color", new Color(0.045f, 0.05f, 0.068f)); m.SetFloat("_RevealMode", 1f); }),
                parapet = Mat("M_Parapet", "MOI/Unlit", m => { Opaque(m); m.SetColor("_Color", new Color(0.2f, 0.22f, 0.27f)); m.SetFloat("_FakeLight", 1f); m.SetFloat("_RevealMode", 1f); }),
                ledWall = Mat("M_LedWall", "MOI/LedWall", m => m.SetTexture("_MainTex", Tex("T_MuseumWall_Placeholder.jpg"))),
                strip = Mat("M_LightStrip", "MOI/Unlit", m => { Additive(m); m.SetTexture("_MainTex", lineTex); m.SetColor("_Color", new Color(1f, 0.86f, 0.68f)); m.SetFloat("_Intensity", 1.6f); m.SetFloat("_RevealMode", 2f); }),
                podium = Mat("M_Podium", "MOI/Unlit", m => { Opaque(m); m.SetColor("_Color", new Color(0.07f, 0.072f, 0.085f)); m.SetFloat("_FakeLight", 1f); m.SetFloat("_Rim", 0.12f); m.SetColor("_RimColor", new Color(0.2f, 0.4f, 1f, 0f)); }),
                plate = Mat("M_PodiumPlate", "MOI/Unlit", m => { Additive(m); m.SetColor("_Color", new Color(0.45f, 0.65f, 1f)); m.SetFloat("_Intensity", 1.4f); }),
                glass = Mat("M_Glass", "MOI/Unlit", m => { Alpha(m); m.SetColor("_Color", new Color(0.6f, 0.8f, 1f, 0.015f)); m.SetFloat("_Rim", 0.55f); m.SetColor("_RimColor", new Color(0.7f, 0.85f, 1f, 0.4f)); }),
                lip = Mat("M_GlassLip", "MOI/Unlit", m => { Additive(m); m.SetTexture("_MainTex", lineTex); m.SetColor("_Color", new Color(0.8f, 0.9f, 1f)); m.SetFloat("_Intensity", 1.2f); }),
                ring = Mat("M_FloorRing", "MOI/Unlit", m => { Additive(m); m.SetTexture("_MainTex", lineTex); m.SetColor("_Color", new Color(1f, 0.93f, 0.85f)); m.SetFloat("_Intensity", 2f); }),
                reflection = Mat("M_FloorReflection", "MOI/Unlit", m => { Additive(m); m.SetTexture("_MainTex", glowTex); m.SetColor("_Color", new Color(0.1f, 0.3f, 1f)); m.SetFloat("_Intensity", 0.7f); }),
                crystal = Mat("M_Crystal", "MOI/Crystal", m => m.renderQueue = 3050),
                crystalCore = Mat("M_CrystalCore", "MOI/Crystal", m => { m.renderQueue = 3045; m.SetColor("_CoreColor", new Color(0.45f, 0.7f, 1f)); m.SetColor("_RimColor", Color.white); m.SetFloat("_Glow", 2.2f); }),
                button = Mat("M_Button", "MOI/Unlit", Opaque), // opaque + depth-writing so the glass and light plate behind the kiosk cannot paint over it
                ray = Mat("M_PointerRay", "MOI/Unlit", m => { Additive(m); m.SetColor("_Color", new Color(0.5f, 0.8f, 1f)); m.SetFloat("_Intensity", 1.5f); }),
                promptBack = Mat("M_PromptBacking", "MOI/Unlit", m => { Alpha(m); m.SetColor("_Color", new Color(0f, 0.01f, 0.03f, 0.72f)); m.renderQueue = 2990; }),
                glow = Mat("M_CrystalHalo", "MOI/Unlit", m => { Additive(m); m.SetTexture("_MainTex", glowTex); m.renderQueue = 3040; }),
                previs = Mat("M_PrevisScreen", "MOI/Unlit", Opaque),
                fader = Mat("M_ScreenFade", "MOI/ScreenFade", m => { }),
                card = Mat("M_ArchiveCard", "MOI/Unlit", m => { Alpha(m); m.SetTexture("_MainTex", Tex("T_ArchiveCard.png")); }),
                mote = Mat("M_Mote", "MOI/Unlit", m => { Additive(m); m.SetTexture("_MainTex", glowTex); m.SetColor("_Color", new Color(1f, 0.75f, 0.35f)); m.SetFloat("_Intensity", 1.5f); }),
                panorama = Mat("M_PanoramaSkybox", "MOI/Panorama360", m => { }),
            };
        }

        static void Opaque(Material m) => Blend(m, BlendMode.One, BlendMode.Zero, true, 2000);
        static void Alpha(Material m) => Blend(m, BlendMode.SrcAlpha, BlendMode.OneMinusSrcAlpha, false, 3000);
        static void Additive(Material m) => Blend(m, BlendMode.SrcAlpha, BlendMode.One, false, 3100);

        static void Blend(Material m, BlendMode src, BlendMode dst, bool zWrite, int queue)
        {
            m.SetFloat("_SrcBlend", (float)src);
            m.SetFloat("_DstBlend", (float)dst);
            m.SetFloat("_ZWrite", zWrite ? 1f : 0f);
            m.renderQueue = queue;
        }

        static Material Mat(string name, string shaderName, Action<Material> setup)
        {
            var shader = Shader.Find(shaderName);
            if (shader == null) throw new InvalidOperationException($"Shader '{shaderName}' not found - has the project finished importing?");
            string path = $"{Generated}/Materials/{name}.mat";
            var material = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (material == null)
            {
                material = new Material(shader) { name = name };
                AssetDatabase.CreateAsset(material, path);
            }
            else
            {
                material.shader = shader;
            }
            setup(material);
            EditorUtility.SetDirty(material);
            return material;
        }

        static Texture2D Tex(string file) => AssetDatabase.LoadAssetAtPath<Texture2D>($"{Root}/Textures/{file}");

        static UnityEngine.Mesh Builtin(string name) => Resources.GetBuiltinResource<UnityEngine.Mesh>(name);

        static UnityEngine.Mesh SaveMesh(UnityEngine.Mesh mesh, string name)
        {
            string path = $"{Generated}/Meshes/{name}.asset";
            var existing = AssetDatabase.LoadAssetAtPath<UnityEngine.Mesh>(path);
            if (existing == null)
            {
                mesh.name = name;
                AssetDatabase.CreateAsset(mesh, path);
                return mesh;
            }
            // Overwrite in place so the asset keeps its GUID.
            existing.Clear();
            EditorUtility.CopySerialized(mesh, existing);
            existing.name = name;
            UnityEngine.Object.DestroyImmediate(mesh);
            EditorUtility.SetDirty(existing);
            return existing;
        }

        static Transform Child(string name, Transform parent)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            return go.transform;
        }

        static GameObject MeshObject(string name, Transform parent, UnityEngine.Mesh mesh, Material material, Vector3 localPosition)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPosition;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var renderer = go.AddComponent<MeshRenderer>();
            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            renderer.lightProbeUsage = LightProbeUsage.Off;
            renderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
            return go;
        }

        static VRButton Button(string name, Transform parent, Material plateMaterial, string caption, float fontSize, Vector2 size, Vector3 localPosition)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPosition;
            go.AddComponent<BoxCollider>().size = new Vector3(size.x, size.y, 0.03f);

            var plate = MeshObject("Plate", go.transform, Builtin("Quad.fbx"), plateMaterial, Vector3.zero);
            plate.transform.localScale = new Vector3(size.x, size.y, 1f);
            var label = Text("Label", go.transform, fontSize, size);
            label.transform.localPosition = new Vector3(0f, 0f, -0.004f);
            label.text = caption;
            label.fontStyle = FontStyles.Bold;

            var button = go.AddComponent<VRButton>();
            button.plate = plate.GetComponent<Renderer>();
            button.label = label;
            return button;
        }

        static LineRenderer Ray(string name, Transform parent, Material material)
        {
            var line = Child(name, parent).gameObject.AddComponent<LineRenderer>();
            line.sharedMaterial = material;
            line.useWorldSpace = true;
            line.positionCount = 2;
            line.widthMultiplier = 0.004f;
            line.shadowCastingMode = ShadowCastingMode.Off;
            line.receiveShadows = false;
            line.enabled = false;
            return line;
        }

        static AudioSource AudioSource2D(GameObject go)
        {
            var source = go.AddComponent<AudioSource>();
            source.playOnAwake = false;
            source.spatialBlend = 0f;
            return source;
        }

        static TextMeshPro Text(string name, Transform parent, float fontSize, Vector2 size)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var text = go.AddComponent<TextMeshPro>();
            text.rectTransform.sizeDelta = size;
            text.fontSize = fontSize;
            text.alignment = TextAlignmentOptions.Center;
            text.textWrappingMode = TextWrappingModes.Normal;
            text.text = string.Empty;
            return text;
        }
    }
}
