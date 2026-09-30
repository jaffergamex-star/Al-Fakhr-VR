using System;
using System.Collections;
using System.IO;
using System.Security.Cryptography;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;

namespace MOI
{
    /// <summary>
    /// Pulls the film from outside the app: a content server / CMS on the museum LAN publishes a small
    /// JSON manifest, the headset downloads whatever it names into local storage and always plays from
    /// that local copy. Streaming a 4K 360 film over Wi-Fi is what makes kiosks stutter; download-then-play
    /// doesn't, and it keeps working when the server or network is down.
    ///
    /// Manifest (any static web server or CMS endpoint can serve this):
    /// {
    ///   "version": "2026-10-01",
    ///   "layout": "Mono360",              FlatScreen | Mono360 | TopBottom360 | SideBySide360
    ///   "yaw": 0,
    ///   "video": { "url": "journey.mp4", "bytes": 734003200, "sha256": "" }
    /// }
    /// "url" may be absolute or relative to the manifest. "bytes" and "sha256" are optional integrity checks.
    ///
    /// Where the manifest lives is itself editable without a rebuild: moi-config.json in the app's data
    /// folder on the headset (Android/data/[package]/files/), written with defaults on first run.
    /// </summary>
    public class ContentManager : MonoBehaviour
    {
#pragma warning disable 0649 // filled in by JsonUtility
        [Serializable]
        class Config
        {
            public string manifestUrl = "";
            public float recheckMinutes = 10f;
        }

        [Serializable]
        class VideoEntry
        {
            public string url;
            public long bytes;
            public string sha256;
        }

        [Serializable]
        class Manifest
        {
            public string version;
            public string layout = "Mono360";
            public float yaw;
            public VideoEntry video;
        }

        // Optional film.json next to a film copied onto the headset: { "layout": "TopBottom360", "yaw": 0 }
        // plus the zoom, e.g. { "zoomAt": 32, "zoomOver": 1, "zoomTo": 1.25 } ("zoomTo": 1 = no zoom). Missing = the
        // sequence asset's values.
        [Serializable]
        class LocalFilmInfo
        {
            public string layout = "";
            public float yaw;
            public float zoomAt = -1f;
            public float zoomOver = -1f;
            public float zoomTo = -1f;
        }
#pragma warning restore 0649

        /// <summary>
        /// A film copied straight onto the headset (adb push / USB file transfer), checked in this order:
        /// the app's own folder (Android/data/[package]/files, no permission needed), then /sdcard/MOI
        /// (needs storage permission, which "adb install -g" grants).
        /// The Windows (PC VR) build first looks in a "content" folder next to its .exe, so the demo folder
        /// carries its own film.
        /// </summary>
        public const string LocalFilmName = "journey.mp4";
        public static string[] LocalFilmCandidates => Application.platform == RuntimePlatform.WindowsPlayer
            ? new[]
            {
                Path.Combine(Path.GetDirectoryName(Application.dataPath), "content", LocalFilmName),
                Path.Combine(Application.persistentDataPath, LocalFilmName),
            }
            : new[]
            {
                Path.Combine(Application.persistentDataPath, LocalFilmName),
                "/sdcard/MOI/" + LocalFilmName,
            };

        public struct Film
        {
            public string path;
            public VideoLayout layout;
            public float yaw;
            public FilmZoom zoom;
            public string version;
        }

        FilmZoom DefaultZoom => director != null && director.sequence != null ? director.sequence.filmZoom : default;

        public ExperienceDirector director;

        /// <summary>One line for the idle screen so staff can see what the headset is holding.</summary>
        public string Status { get; private set; } = "";

        /// <summary>
        /// Whether there is a film to play. There is no built-in stand-in: without a film the START screen says so
        /// and START does nothing. Re-checked every 2 s, so a film copied on while the app runs is picked up.
        /// </summary>
        public bool HasFilm { get; private set; }

        Config m_Config;
        Manifest m_Active;
        string m_CommandLineFilm;
        float m_NextFilmCheck;

        string Root => Path.Combine(Application.persistentDataPath, "Content");
        string ConfigPath => Path.Combine(Application.persistentDataPath, "moi-config.json");
        string ManifestPath => Path.Combine(Root, "manifest.json");

        void Awake()
        {
            Directory.CreateDirectory(Root);

            m_Config = ReadJson<Config>(ConfigPath);
            if (m_Config == null)
            {
                m_Config = new Config { manifestUrl = director != null && director.sequence != null ? director.sequence.contentManifestUrl ?? "" : "" };
                File.WriteAllText(ConfigPath, JsonUtility.ToJson(m_Config, true));
            }
            m_Active = ReadJson<Manifest>(ManifestPath);
            m_CommandLineFilm = CommandLineFilmPath();
            HasFilm = TryGetFilm(out _);
            Status = m_Active != null ? "Content " + m_Active.version + " (cached)" : LocalStatus();
            Debug.Log($"[MOI] Content folder: {Root}\n[MOI] Manifest URL: {(string.IsNullOrEmpty(m_Config.manifestUrl) ? "(none - edit " + ConfigPath + ")" : m_Config.manifestUrl)}");
            if (!HasFilm) Debug.LogWarning("[MOI] No film on this device: " + LocalStatus());
        }

        void Update()
        {
            if (Time.unscaledTime < m_NextFilmCheck) return;
            m_NextFilmCheck = Time.unscaledTime + 2f;
            bool has = TryGetFilm(out _);
            if (has == HasFilm) return;
            HasFilm = has;
            if (m_Active == null) Status = LocalStatus();
            Debug.Log(has ? "[MOI] Film found: " + LocalStatus() : "[MOI] Film gone: " + LocalStatus());
        }

        IEnumerator Start()
        {
            if (string.IsNullOrEmpty(m_Config.manifestUrl)) yield break;
            while (true)
            {
                // Never pull gigabytes while someone is inside the film.
                while (director != null && director.CurrentState != ExperienceDirector.State.Idle) yield return null;
                yield return Sync();
                yield return new WaitForSecondsRealtime(Mathf.Max(1f, m_Config.recheckMinutes) * 60f);
            }
        }

        /// <summary>
        /// A film named on the command line (-film path, relative to the .exe folder or absolute), else the server
        /// film if one has been downloaded, else a film copied onto the headset / next to the .exe.
        /// </summary>
        public bool TryGetFilm(out Film film) => TryGetCommandLineFilm(out film) || TryGetServerFilm(out film) || TryGetLocalFilm(out film);

        static string CommandLineFilmPath()
        {
            string[] args = System.Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length - 1; i++)
            {
                if (!string.Equals(args[i], "-film", StringComparison.OrdinalIgnoreCase)) continue;
                string path = Path.IsPathRooted(args[i + 1]) ? args[i + 1] : Path.Combine(Path.GetDirectoryName(Application.dataPath), args[i + 1]);
                if (!File.Exists(path)) Debug.LogWarning("[MOI] -film: no file at " + path);
                return path;
            }
            return null;
        }

        bool TryGetCommandLineFilm(out Film film)
        {
            film = default;
            if (m_CommandLineFilm == null || !File.Exists(m_CommandLineFilm)) return false;
            film = LocalFilm(m_CommandLineFilm);
            return true;
        }

        public bool TryGetLocalFilm(out Film film)
        {
            film = default;
            foreach (var path in LocalFilmCandidates)
            {
                if (!File.Exists(path)) continue;
                film = LocalFilm(path);
                return true;
            }
            return false;
        }

        // Layout and yaw from the sequence, or from a film.json next to the film.
        Film LocalFilm(string path)
        {
            var layout = director != null && director.sequence != null ? director.sequence.masterVideoLayout : VideoLayout.Mono360;
            float yaw = director != null && director.sequence != null ? director.sequence.masterVideoYaw : 0f;
            var zoom = DefaultZoom;
            var info = ReadJson<LocalFilmInfo>(Path.Combine(Path.GetDirectoryName(path), "film.json"));
            if (info != null)
            {
                if (Enum.TryParse(info.layout, true, out VideoLayout parsed)) layout = parsed;
                yaw = info.yaw;
                if (info.zoomAt >= 0f) zoom.at = info.zoomAt;
                if (info.zoomOver >= 0f) zoom.over = info.zoomOver;
                if (info.zoomTo >= 0f) zoom.to = info.zoomTo;
            }
            return new Film { path = path, layout = layout, yaw = yaw, zoom = zoom, version = "local" };
        }

        string LocalStatus()
        {
            if (TryGetCommandLineFilm(out var film) || TryGetLocalFilm(out film)) return $"Film: {Path.GetFileName(film.path)} ({film.layout})";
            return Application.platform == RuntimePlatform.WindowsPlayer
                ? "Film missing: put journey.mp4 in the app's content folder"
                : "Film missing: copy it with 'Replace headset film' on the station computer";
        }

        bool TryGetServerFilm(out Film film)
        {
            film = default;
            if (m_Active == null) return false;
            string path = LocalPath(m_Active.video);
            if (path == null) return false;

            if (!Enum.TryParse(m_Active.layout, true, out VideoLayout layout)) layout = VideoLayout.Mono360;
            film = new Film { path = path, layout = layout, yaw = m_Active.yaw, zoom = DefaultZoom, version = m_Active.version };
            return true;
        }

        string LocalPath(VideoEntry entry)
        {
            if (entry == null || string.IsNullOrEmpty(entry.url)) return null;
            string path = Path.Combine(Root, LocalName(entry));
            return File.Exists(path) ? path : null;
        }

        // The name changes whenever the entry does, so a new film never overwrites the one in use.
        static string LocalName(VideoEntry entry)
        {
            string extension = Path.GetExtension(entry.url.Split('?')[0]);
            if (string.IsNullOrEmpty(extension)) extension = ".mp4";
            return Hash128.Compute(entry.url + "|" + entry.bytes + "|" + entry.sha256) + extension;
        }

        IEnumerator Sync()
        {
            string manifestText;
            using (var request = UnityWebRequest.Get(m_Config.manifestUrl))
            {
                request.timeout = 8;
                yield return request.SendWebRequest();
                if (request.result != UnityWebRequest.Result.Success)
                {
                    Status = m_Active != null ? "Content " + m_Active.version + " (server offline - using cached copy)"
                           : TryGetLocalFilm(out _) ? LocalStatus() + " (server offline)" : "Content server offline";
                    Debug.LogWarning("[MOI] Manifest fetch failed: " + request.error);
                    yield break;
                }
                manifestText = request.downloadHandler.text;
            }

            Manifest incoming;
            try { incoming = JsonUtility.FromJson<Manifest>(manifestText); }
            catch (Exception e) { Status = "Manifest unreadable"; Debug.LogError("[MOI] Manifest JSON: " + e.Message); yield break; }

            var entry = incoming.video;
            if (entry == null || string.IsNullOrEmpty(entry.url))
            {
                Status = "Manifest has no video";
                Debug.LogError("[MOI] Manifest has no \"video\" entry.");
                yield break;
            }
            if (LocalPath(entry) == null)
            {
                bool ok = false;
                yield return Download(entry, result => ok = result);
                if (!ok) yield break; // keep playing the previous content
            }

            File.WriteAllText(ManifestPath, manifestText);
            m_Active = incoming;
            Status = "Content " + incoming.version + " ready";
            RemoveUnreferenced();
        }

        IEnumerator Download(VideoEntry entry, Action<bool> done)
        {
            string url = new Uri(new Uri(m_Config.manifestUrl), entry.url).AbsoluteUri;
            string target = Path.Combine(Root, LocalName(entry));
            string partial = target + ".part";

            using (var request = new UnityWebRequest(url, UnityWebRequest.kHttpVerbGET))
            {
                request.downloadHandler = new DownloadHandlerFile(partial) { removeFileOnAbort = true };
                var operation = request.SendWebRequest();
                while (!operation.isDone)
                {
                    Status = $"Downloading new content {request.downloadProgress * 100f:0}%";
                    yield return null;
                }
                if (request.result != UnityWebRequest.Result.Success)
                {
                    Status = "Download failed - using previous content";
                    Debug.LogWarning($"[MOI] Download failed: {url}: {request.error}");
                    done(false);
                    yield break;
                }
            }

            long size = new FileInfo(partial).Length;
            if (entry.bytes > 0 && size != entry.bytes)
            {
                Fail(partial, $"size {size} != manifest {entry.bytes}");
                done(false);
                yield break;
            }
            if (!string.IsNullOrEmpty(entry.sha256))
            {
                Status = "Verifying new content";
                var hashing = Task.Run(() => Sha256(partial));
                while (!hashing.IsCompleted) yield return null;
                if (!string.Equals(hashing.Result, entry.sha256, StringComparison.OrdinalIgnoreCase))
                {
                    Fail(partial, "sha256 mismatch");
                    done(false);
                    yield break;
                }
            }

            if (File.Exists(target)) File.Delete(target);
            File.Move(partial, target);
            Debug.Log($"[MOI] Content downloaded: {url} -> {target} ({size / (1024 * 1024)} MB)");
            done(true);
        }

        void Fail(string partial, string reason)
        {
            File.Delete(partial);
            Status = "New content rejected (" + reason + ")";
            Debug.LogError("[MOI] Download rejected: " + reason);
        }

        static string Sha256(string path)
        {
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
        }

        void RemoveUnreferenced()
        {
            foreach (var file in Directory.GetFiles(Root))
            {
                string name = Path.GetFileName(file);
                if (name == "manifest.json") continue;
                bool used = name == LocalName(m_Active.video);
                // A superseded film may still be open in the player; it gets swept on the next sync.
                if (!used) try { File.Delete(file); } catch (IOException) { }
            }
        }

        static T ReadJson<T>(string path) where T : class
        {
            try { return File.Exists(path) ? JsonUtility.FromJson<T>(File.ReadAllText(path)) : null; }
            catch (Exception e) { Debug.LogWarning($"[MOI] Could not read {path}: {e.Message}"); return null; }
        }
    }
}
