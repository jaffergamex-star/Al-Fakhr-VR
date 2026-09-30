using System.Collections.Generic;
using UnityEngine;

namespace MOI.EditorTools
{
    /// <summary>
    /// The approved storyboard ("UAE Ministry of Interior - Museum VR Experience" deck) as data.
    /// Timings, direction and bilingual voice-over are transcribed from the deck. Three places where
    /// the deck contradicts itself are resolved here and called out inline - confirm with the client.
    /// </summary>
    public static class StoryboardData
    {
        public const string Museum = "museum";

        public static string PrevisId(int beatNumber) => $"previs_{beatNumber:00}";

        public static List<Beat> CreateBeats()
        {
            var beats = new List<Beat>
            {
                MuseumBeat("promise-dimension", "The Promise Dimension", 0, 8, 1f, 1f, 1f, 1f,
                    "The VR view matches the physical museum, with the crystal directly ahead.",
                    "For generations, safety has been built through courage, service and trust.",
                    "على امتداد أجيال، بُني الأمان بالشجاعة، والتفاني في الخدمة، والثقة"),

                MuseumBeat("world-fades", "The World Fades", 8, 15, 1f, 0.45f, 1f, 1f,
                    "The museum gradually dims; its outlines fade while the crystal remains illuminated.",
                    "Here, that legacy lives on… and a new chapter begins.",
                    "هنا، يبقى ذلك الإرث حيّاً… ويبدأ فصلٌ جديد."),

                // Deck prints 00:08-00:15 again for this page; 00:15-00:22 is the only slot that fits.
                MuseumBeat("last-light", "The Last Light", 15, 22, 0.45f, 0f, 1f, 1.3f,
                    "Darkness surrounds the visitor. Only the crystal remains, its core gently pulsing.",
                    "Within this light, the memory of a nation awakens",
                    "في قلب هذا النور، تستيقظ ذاكرة وطن"),

                MuseumBeat("legacy", "Preserving the Legacy", 22, 35, 0f, 0f, 1.3f, 2f,
                    "Museum documents, photographs and achievements emerge, transforming into light preserved within the crystal.",
                    "Every document, every achievement, every story carries a lesson. The Ministry of Interior preserves this legacy to protect its people—and the generations to come.",
                    "في كل وثيقة، وكل إنجاز، وكل حكاية، معرفةٌ تستحق أن تبقى. تصون وزارة الداخلية هذا الإرث، ليظل أساساً لحماية الإنسان وأمان الأجيال القادمة"),

                MuseumBeat("light-opens", "The Passage Opens", 35, 42, 0f, 0f, 2f, 7f,
                    "The crystal brightens, filling the visitor's view with light and opening the passage forward.",
                    "What we have learned becomes our guide to what comes next.",
                    "وما تعلّمناه بالأمس، يصبح دليلنا إلى ما يحمله الغد"),

                // Deck summary page says 2077; this page and its voice-over (EN + AR) say 2076. Using 2076.
                Future(6, "abu-dhabi-2076", "Abu Dhabi 2076", 42, 53, TransitionKind.FadeWhite, 4f, new Vector3(0.9f, 1.3f, 3.2f),
                    "Light clears to reveal Abu Dhabi in 2076. The crystal floats nearby as the visitor's guide.",
                    "Welcome to Abu Dhabi, 2076. A city looking further ahead, where protection is woven into the rhythm of everyday life.",
                    "مرحباً بكم في أبوظبي، عام 2076. مدينةٌ ترى أبعد، وتنسج الحماية في تفاصيل الحياة اليومية"),

                // Deck repeats beat 6's description and voice-over on this page. Direction below is read
                // off the frame; voice-over left empty until the client supplies the real line.
                Future(7, "safer-journeys", "Safer Journeys", 53, 66, TransitionKind.FadeBlack, 1.2f, new Vector3(-1.4f, 2.2f, 3f),
                    "[Inferred from frame - deck copy is a duplicate of beat 6] Street level at dusk. The crystal projects flight corridors overhead, steering air taxis apart while road traffic yields to pedestrians.",
                    "", ""),

                Future(8, "human-led", "Human-Led Protection", 66, 78, TransitionKind.FadeBlack, 1.2f, new Vector3(-1.6f, 2.3f, 3.2f),
                    "Police officers use spatial tools and AI-supported insights to assess risks and coordinate protection.",
                    "Behind this intelligence are people. Advanced tools help officers understand risks sooner, while judgment, responsibility and the commitment to protect remain human.",
                    "ووراء هذا الذكاء، يقف الإنسان. تساعد الأدوات المتقدّمة رجال الشرطة على فهم المخاطر مبكراً، ويبقى القرار والمسؤولية والالتزام بالحماية في يد الإنسان"),

                Future(9, "digital-identity", "Protecting Digital Identity", 78, 90, TransitionKind.FadeBlack, 1.2f, new Vector3(1.8f, 2f, 3.5f),
                    "A hologram rises from the visitor's device, detecting impersonation and blocking attempts to access private information.",
                    "That protection reaches your digital life. Attempts to steal your identity or deceive you are detected—because your privacy deserves the same care as your physical safety.",
                    "وتمتد هذه الحماية إلى حياتك الرقمية. تُكتشف محاولات انتحال هويتك وخداعك، وتُحجب محاولات الاختراق… لأن خصوصيتك تستحق العناية نفسها التي يستحقها أمنك"),

                Future(10, "coordinated-response", "One Coordinated Response", 90, 102, TransitionKind.FadeBlack, 1.2f, new Vector3(2f, 1.8f, 3f),
                    "A national command view connects cities, roads, airspace, deserts and seas under coordinated human oversight.",
                    "Across cities, roads, airspace, deserts and seas, Ministry officers and their partners connect information, verify risks, and coordinate one timely response.",
                    "عبر المدن والطرق والأجواء، وفي الصحارى والبحار، يربط ضباط الوزارة وشركاؤهم المعلومات، ويتحقّقون من المخاطر، وينسّقون استجابةً متكاملة في الوقت المناسب"),

                Future(11, "sands", "Shelter Across the Sands", 102, 114, TransitionKind.FadeBlack, 1.2f, new Vector3(-1.8f, 1.9f, 3.5f),
                    "In Liwa, officers activate an adaptive storm barrier, protecting communities and keeping travel corridors clear.",
                    "In Liwa, early warnings activate protective systems before the sandstorm arrives. Communities remain sheltered, and travellers are guided along safe routes.",
                    "في ليوا، تفعّل الإنذارات المبكرة أنظمة الحماية قبل وصول العاصفة الرملية. تبقى المجتمعات آمنة، ويُوجَّه المسافرون عبر مسارات محميّة"),

                Future(12, "coast", "A Protected Coast", 114, 126, TransitionKind.FadeBlack, 1.2f, new Vector3(2.2f, 1.9f, 3.5f),
                    "Coastal barriers respond to rising water while marine systems safeguard nearby habitats and wildlife.",
                    "Along the coast, rising waters trigger adaptive defences. Homes and public spaces stay protected, while marine systems help safeguard the life beneath the surface.",
                    "وعلى الساحل، تستجيب الحواجز الذكية لارتفاع المياه. فتحمي المنازل والمرافق العامة، وتساندها أنظمة بحرية تصون الحياة تحت السطح"),

                Future(13, "fire", "Containing Fire", 126, 137, TransitionKind.FadeBlack, 1.2f, new Vector3(-1.7f, 1.8f, 3.2f),
                    "Firefighting drones and building systems contain a localised fire as civil-defence teams direct the response.",
                    "When fire breaks out, every second matters. Civil-defence teams direct precision drones and building systems to contain it and keep escape routes clear.",
                    "وحين يندلع حريق، تصبح كل ثانية حاسمة. توجّه فرق الدفاع المدني الطائرات المسيّرة وأنظمة المباني لاحتوائه، وإبقاء مسارات الإخلاء آمنة"),

                Future(14, "city-responds", "A City That Responds", 137, 149, TransitionKind.FadeBlack, 1.2f, new Vector3(-1.5f, 2f, 3f),
                    "Buildings open protected connections, transit reroutes, and roads clear an emergency corridor around an affected area.",
                    "The city itself responds. Buildings open safe connections, transport changes course, and roads make way for responders—adapting around people when they need it most.",
                    "وتستجيب المدينة نفسها. تفتح المباني ممرات آمنة، وتتغيّر مسارات النقل، وتفسح الطرق المجال لفرق الطوارئ… لتتكيّف المدينة مع احتياجات الإنسان وقت الحاجة"),

                Future(15, "roots", "Returning to Our Roots", 149, 157, TransitionKind.FadeWhite, 1.6f, new Vector3(0f, 1.6f, 6f),
                    "The crystal opens a passage of refracted memories, carrying the visitor from the future into the past.",
                    "Yet to understand what carries us forward, we must remember what grounds us.",
                    "لكن، لنعرف ما يقودنا إلى الأمام، علينا أن نتذكّر الجذور التي نستند إليها"),

                Future(16, "what-endures", "What Endures", 157, 170, TransitionKind.FadeWhite, 2f, new Vector3(-1.2f, 1.7f, 2.8f),
                    "The visitor arrives at historic Qasr Al Hosn: a falcon rests ahead and the UAE flag moves in the breeze.",
                    "Here at Qasr Al Hosn, we return to Abu Dhabi's roots. Our tools may change, but our identity, our values, and our care for one another endure.",
                    "هنا، في قصر الحصن، نعود إلى جذور أبوظبي. قد تتغيّر أدواتنا، لكن هويتنا وقيمنا وتكاتفنا تبقى راسخة… نحملها معنا، جيلاً بعد جيل"),

                MuseumBeat("memory-returns", "The Memory Returns", 170, 176, 0f, 0.45f, 1.6f, 1.2f,
                    "The heritage scene fades. The crystal settles onto its museum podium as the room's outlines reappear.",
                    "We return with that promise: rooted in heritage, ready for tomorrow.",
                    "نعود بهذا الوعد: جذورٌ راسخة في إرثنا، واستعدادٌ دائم للغد"),

                MuseumBeat("promise-continues", "The Promise Continues", 176, 180, 0.45f, 1f, 1.2f, 1f,
                    "The museum fully returns, matching the opening view. The crystal holds a final, gentle glow.",
                    "Ministry of Interior. A promise of safety, across generations.",
                    "وزارة الداخلية… وعدُ أمانٍ تتوارثه الأجيال"),
            };

            // Open on a fade from black; come home from Qasr Al Hosn through black.
            beats[0].transitionIn = TransitionKind.FadeBlack;
            beats[0].transitionDuration = 3f;
            beats[16].transitionIn = TransitionKind.FadeBlack;
            beats[16].transitionDuration = 2f;
            return beats;
        }

        static Beat MuseumBeat(string id, string title, float start, float end, float revealFrom, float revealTo,
            float glowFrom, float glowTo, string direction, string en, string ar)
        {
            return new Beat
            {
                id = id, title = title, start = start, end = end, direction = direction,
                voiceOverEn = en, voiceOverAr = ar,
                environmentId = Museum, transitionIn = TransitionKind.Cut,
                revealFrom = revealFrom, revealTo = revealTo,
                crystal = CrystalMode.OnPodium, glowFrom = glowFrom, glowTo = glowTo,
            };
        }

        // Future / heritage beats run on storyboard frames for now. Those frames already have the
        // crystal painted in, so the 3D crystal is hidden; crystalOffset records where it floats in
        // the frame so switching a beat to a real set only needs crystal = Floating.
        static Beat Future(int number, string id, string title, float start, float end, TransitionKind transition,
            float transitionDuration, Vector3 crystalOffset, string direction, string en, string ar)
        {
            return new Beat
            {
                id = id, title = title, start = start, end = end, direction = direction,
                voiceOverEn = en, voiceOverAr = ar,
                environmentId = PrevisId(number), transitionIn = transition, transitionDuration = transitionDuration,
                revealFrom = 0f, revealTo = 0f,
                crystal = CrystalMode.Hidden, crystalOffset = crystalOffset, glowFrom = 1.4f, glowTo = 1.4f,
            };
        }
    }
}
