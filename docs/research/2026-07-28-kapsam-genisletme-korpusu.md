# Kapsam Genişletme Araştırma Korpusu (2026-07-28)

Kurucu revizyonu: daha fazla çalgı (Ostinato) · solo global danslar (Choreia) · tam fitness kataloğu (Gravita). 3 ajan, ~257k token.


# ==== ostinato-more-instruments ====

## SUMMARY
Beyond the 13 approved instruments, ~30 candidates were evaluated for Ostinato's on-device pose+audio coach. Nine are near-zero-cost drop-ins because they reuse existing bowed-string, wind, plucked-string-chord, or percussion modules with only tuning/fingering config changes (viola, double bass, trombone, oboe, bassoon, recorder, tin whistle, banjo, mandolin, cajon, djembe, bongos/congas). Five need moderate new module work but have large, verifiable global learner bases that justify it (accordion, harp, guzheng — with koto reusing the same zither module, pipa, tabla). A handful are niche/regional with thin global course-demand evidence (charango, balalaika, shamisen, bagpipes, oud, bağlama/saz) — real but small, better as later community-request waves than a numbered wave. French horn and organ pedalboard have a specific single-camera blind spot (hand-in-bell / feet-out-of-frame) that the other approved brass/keyboard instruments don't have. Steel pan and melodica are credible additions with real institutional footholds (Trinidad/US university steelband programs; melodica as Japan's near-universal "pianica" in elementary schools) but both need bespoke pitch-mapping work. DJ/production and any pure electronic-music-production skill are an honest ❌: there is no posture to coach and no acoustic instrument technique — it doesn't fit the pose+audio coaching thesis at all, only a mixing/software-tutorial thesis, which is a different product.

## RECOMMENDATIONS
- Wave A (config-only, ship first): Viola, Double Bass, Trombone, Oboe, Bassoon, Recorder, Tin Whistle, Banjo, Mandolin, Cajon, Djembe, Bongos/Congas — all map onto existing bowed-string, wind, plucked-string-chord, or percussion-onset modules; engineering cost is instrument-config (tuning, fingering chart, range) not new pose logic.
- Wave B (moderate new module, high learner-base ROI): Guzheng + Koto (shared new plucked-zither module with glissando/bent-pitch detection — China's ~10M guzheng learners is the single largest addressable market on this whole list), Accordion (new bimanual keys+buttons+bellows module), Harp (plucked-chord module + camera-framing guidance for the instrument's width), Tabla (percussion module extended for pitch-bent bol strokes), Pipa (plucked-string-chord module extended for tremolo/lunzhi technique).
- Wave C (regional/niche, ship on demonstrated demand not speculative): Sitar, Oud, Bağlama/Saz, Erhu (needs a genuinely new pose state-machine — vertical hold, no fixed fingerboard, harmonics via light touch — don't bundle with Wave B bowed-string reuse), Steel pan (new pitched-percussion module; note-layout config explosion across tenor/double-second/etc. pan types), Melodica (small new breath+keyboard hybrid module; strongest case is Japan school-market), Shamisen, Charango, Balalaika, Bagpipes (practice chanter only — full pipes are a distinct, physically extreme mechanism not suited to phone-camera coaching).
- Do NOT build: DJ/electronic music production. It fails the product's own definition of fit — no body posture to correct, no acoustic instrument technique, output is software workflow not physical skill. If founder wants to capture that demand, it should be scoped as a separate non-Ostinato product, not a 14th 'instrument.'
- Flag internally before committing Wave C: several of the 'huge learner base' claims for niche/regional instruments (bağlama millions, oud MENA demand, balalaika/charango global demand) returned only course-listing pages or no hard numbers in the research pass below — verify with a follow-up targeted search per instrument before greenlighting engineering spend, not just before marketing copy.

## RISKS
- Several 'popularity' figures for non-Western instruments come from B2B market-research report abstracts (dataintelo, verifiedmarketreports, marketresearchintellect) whose methodology is opaque and whose numbers (e.g. sitar CAGR, hand-percussion market size) should be treated as directional, not verified.
- The guzheng '10 million students in China' figure and the erhu '600,000 young players' figure both trace to secondary summaries of older/unclear primary sources (one explicitly cites a 2015 report) — worth a direct-source check before using in investor or marketing materials.
- Camera-feasibility verdicts for erhu, guzheng, harp, steel pan, and accordion are architectural judgments based on known playing mechanics, not hands-on device testing — validate with an actual MediaPipe pose capture session per instrument before committing engineering estimates.
- French horn is likely to disappoint users if shipped without caveats: right-hand-in-bell hand-stopping and subtle embouchure are core technique elements largely invisible to a single front-facing camera, unlike the other approved brass (trumpet/trombone) where slide/valve position is the primary visible signal.
- Bagpipes: full Great Highland Bagpipes involve continuous bag-arm pressure and drone tuning that a phone-camera+on-device-audio coach cannot meaningfully evaluate; only the practice chanter (mouth-blown, monophonic, fingering-only) is a realistic, honest scope — mis-scoping this as 'bagpipes' in marketing would overpromise.

## ITEMS
### Viola
- pop: Standard ABRSM/Trinity/RCM Grade 1–8 instrument worldwide; core to every school and youth orchestra; dedicated Suzuki Viola method exists.
- feas: ✅ Identical single-camera framing to violin/cello — chin/shoulder hold, bow arm, and left-hand fingerboard all visible from one static phone.
- curr: ABRSM/Trinity/RCM grade ladder + Suzuki Viola method; reuses violin pedagogy with alto-clef and a-5th-lower tuning offset.
- needs: None beyond string count/tuning config.
- caveat: Lowest-risk item on the whole list; no meaningful uncertainty.
- url: https://www.abrsm.org/en-us/instruments/
### Double Bass
- pop: Standard ABRSM/Trinity grade instrument; essential in school orchestras; overlaps with electric-bass method books in jazz/pop pedagogy.
- feas: ⚠️ Instrument height (~1.8m) and standing posture mean a fixed phone at typical desk/tripod distance may crop the bow-arm-to-fingerboard span — a camera-placement constraint (needs more distance/wider framing than violin/cello setups), not a technique constraint.
- curr: ABRSM/Trinity/RCM grades + Simandl method (classical); walking-bass/slap technique track for jazz.
- needs: App should enforce/guide a minimum camera-to-player distance for full framing.
- caveat: None on demand; only a UX/setup-flow caveat.
- url: https://www.abrsm.org/en-us/instruments/
### Trombone
- pop: Standard grade-exam brass instrument; core to concert band, jazz band, and orchestra curricula globally.
- feas: ✅ Slide position and arm extension are fully visible from a single front/side camera; maps cleanly onto a wind-module extension with slide-position state instead of valve-fingering state.
- curr: ABRSM/Trinity Brass grades; concert-band method books (Standard of Excellence, Essential Elements) universally include trombone.
- needs: New pose sub-state for slide position (distance-based, not finger-based) — small, well-scoped addition to the wind module.
- caveat: None significant.
- url: https://www.abrsm.org/en-us/instruments/brass
### French Horn
- pop: Standard ABRSM/Trinity grade instrument, core to every orchestra and concert band.
- feas: ⚠️ Right hand is largely hidden inside the bell (hand-stopping technique) and embouchure subtleties are hard to read at phone resolution — the single most camera-unfriendly instrument on this list among the 'obvious' orchestral additions.
- curr: ABRSM/Trinity/RCM grades; standard band method books.
- needs: Coaching would have to lean almost entirely on audio (pitch/tone) rather than pose, unlike trumpet/trombone where slide/valve position is the primary visual signal.
- caveat: Honest verdict: ship valve-visible fingering feedback only, and disclose that hand-stopping/embouchure coaching is out of scope for a single fixed camera.
- url: https://www.abrsm.org/en-us/instruments/brass
### Oboe
- pop: Standard ABRSM/Trinity grade instrument; core orchestral woodwind, present in most conservatory and school programs.
- feas: ✅ Finger/key positions on the front of the instrument are visible from one static camera, same framing as clarinet/sax.
- curr: ABRSM/Trinity/RCM grades; standard orchestral audition repertoire.
- needs: Double-reed embouchure nuance (lip pressure) is not visually assessable, but this matches the existing clarinet/sax scope limitation, not a new gap.
- caveat: None beyond the embouchure limitation already accepted for approved reed instruments.
- url: https://www.abrsm.org/en-us/instruments/
### Bassoon
- pop: Standard ABRSM/Trinity grade instrument; core orchestral woodwind, though smaller learner population than clarinet/sax/flute.
- feas: ✅ Key/finger positions visible from a static front camera despite the instrument's size and bent bocal; same visibility class as oboe/clarinet.
- curr: ABRSM/Trinity/RCM grades; standard orchestral method books.
- needs: Larger key system than clarinet means a bigger fingering-chart config, but no new pose logic.
- caveat: Smaller global learner base than the other woodwinds — worth confirming founder still wants it in an early wave vs. later.
- url: https://www.abrsm.org/en-us/instruments/
### Recorder
- pop: De facto standard classroom instrument in US, UK, Malaysia (KBSR curriculum), and many other national curricula (Carl Orff's Orff Schulwerk); effectively every child in these systems is taught recorder at some point.
- feas: ✅ Simplest camera case on the whole list — no reed/embouchure subtlety to assess, finger-hole coverage is the entire visual signal, monophonic pitch audio is trivial for the existing monophonic-pitch module.
- curr: No formal grade-exam tradition dominates (unlike violin/piano) — mostly classroom-curriculum based (Orff Schulwerk, national primary curricula) plus some ABRSM/Trinity recorder grades for advanced players.
- needs: None — lowest engineering cost, largest reach; strong candidate for Wave A despite feeling 'unserious.'
- caveat: None on feasibility; only a positioning question (recorder reads as a kids'-classroom instrument, not an 'adult hobbyist' one, which may or may not fit Ostinato's target demographic).
- url: https://www.atlasobscura.com/articles/why-every-kid-in-america-learns-to-play-the-recorder
### Accordion
- pop: Europe holds >35% of the accordion market (France, Germany, Italy, Eastern Europe); reported 20% enrollment growth where formal curricula added accordion; strong TikTok/YouTube-driven beginner interest per the Folk Music Academy.
- feas: ⚠️ Both hands are visible from a front camera, but the instrument body covers the torso (posture cues are largely occluded) and bellows technique — the primary expressive/dynamic control — is not visually assessable, only inferable from audio dynamics.
- curr: No single dominant grade system; regional conservatory tracks exist in France/Italy/Russia; largely taught through folk-tradition apprenticeship and dedicated academies (e.g. The Folk Music Academy).
- needs: New bimanual module: right-hand keyboard/button fingering + left-hand bass-button fingering + audio-inferred bellows/dynamics — meaningfully more engineering than a config-only add.
- caveat: Popularity evidence is solid for Europe but thinner for global course demand outside folk-tradition regions; treat as a real but second-tier build.
- url: https://www.marketresearchintellect.com/blog/accordion-market-strikes-a-chord-amid-rising-interest-in-vintage-instruments/
### Harp
- pop: Standard ABRSM/Trinity/RCM grade instrument; steady conservatory and orchestral demand, smaller than piano/guitar but consistent worldwide.
- feas: ⚠️ Both hands are visible, but the instrument's width and the player's seated position mean a single phone at a normal desk distance risks cropping one side of the strings — needs a documented wider framing distance, similar to the double-bass constraint.
- curr: ABRSM/Trinity/RCM grades; Suzuki Harp method exists; pedal-harp vs. lever-harp are distinct technical tracks.
- needs: New plucked-multi-string module (not a chord-shape module like guitar — each string is a fixed pitch, technique is about which fingers pluck which strings in sequence) plus pedal/lever state tracking for chromatic notes.
- caveat: Moderate new engineering; justified by genuine, verifiable grade-exam demand rather than social-media hype.
- url: https://www.abrsm.org/en-us/instruments/
### Banjo
- pop: Sustained bluegrass/folk/old-time demand; smaller than ukulele but consistent method-book and online-course market (Lessonface, TrueFire, ArtistWorks all carry dedicated banjo tracks).
- feas: ✅ Same camera framing and fretting-hand/strumming-hand visibility as guitar/ukulele — config-only extension of the plucked-string-chord module (5-string open-G tuning, clawhammer vs. 3-finger picking pattern config).
- curr: No single grade-exam ladder; taught through method books (Earl Scruggs method, clawhammer method books) and online mentor platforms.
- needs: None beyond tuning/technique-style config.
- caveat: Popularity is real but comparative online-course-enrollment stats vs. ukulele/mandolin were not found in this pass — directionally solid, not numerically pinned down.
- url: https://musiversity.co/blog-post/which-musical-instruments-are-people-most-eager-to-learn-in-2025
### Mandolin
- pop: Smaller than guitar/ukulele but persistent across multiple traditions (bluegrass, choro, Celtic, classical mandolin orchestras); dedicated method-book and online-academy market exists.
- feas: ✅ Same fretting/picking-hand visibility as guitar — config-only extension of the plucked-string-chord module (paired-string tuning, tremolo-picking config).
- curr: No dominant grade-exam ladder; taught via tradition-specific method books and mandolin-orchestra ensembles in some regions (Italy, Japan has an active mandolin-orchestra scene).
- needs: Tremolo-picking detection may need a small audio-side addition (rapid alternate-picking on a single note is mandolin's signature technique) beyond straightforward guitar strum/pluck detection.
- caveat: Direct comparative demand statistics not found; treat popularity claim as plausible-but-unquantified.
- url: https://musiversity.co/blog-post/which-musical-instruments-are-people-most-eager-to-learn-in-2025
### Organ / Keyboard-Synth
- pop: Standard Trinity/ABRSM grade instrument; large installed base via church organ tradition and electronic keyboard/synth hobbyist market (arguably one of the biggest 'keyboard' markets globally once synths are included).
- feas: ✅ for manuals (hand technique = piano module, config-only) / ⚠️ for pedalboard (feet are below the typical single fixed camera's frame on a desk/tripod setup — not visible without a second camera or floor-level placement).
- curr: ABRSM/Trinity Organ grades (with pedal technique as a distinct examined skill); separate keyboard/synth-specific pedagogy (Yamaha grade system) for electronic keyboards.
- needs: Ship 'manuals only' coaching as config-only piano-module reuse; explicitly scope pedalboard coaching out or as a stretch goal requiring a second camera angle.
- caveat: Electronic keyboard/synth demand is very large but diffuse (not a single 'course' category) — good popularity story, harder to cite one clean number.
- url: https://www.trinitycollege.com/qualifications/music/grade-exams
### Cajon
- pop: Hand-percussion market projected ~$1.24B (2025) growing to ~$2.15B (2033) at 6.5% CAGR; cajon specifically noted as globally adopted beyond its Peruvian origin into flamenco and acoustic ensembles.
- feas: ✅ Player sits on the box facing the camera (or the camera is placed to see the front face and hands) — hand-strike position/technique is fully visible; maps directly onto a percussion-onset module extension.
- curr: No formal grade-exam ladder; taught through drum-school method books and online percussion academies (e.g. Drumeo).
- needs: None beyond percussion-module config for cajon's tonal zones (bass tone at center, slap tone at edges).
- caveat: None significant — config-only, good Wave A candidate.
- url: https://dataintelo.com/report/global-hand-percussion-market
### Djembe
- pop: Widely adopted in world-music education and cultural-exchange programs globally; core to community drum-circle culture in US/Europe as well as its West African origin.
- feas: ✅ Hands and drumhead fully visible from a single front camera; maps directly onto a percussion-onset module extension with 3-stroke classification (bass/tone/slap).
- curr: No formal grade-exam ladder; taught through West African griot-lineage apprenticeship traditions and Western drum-circle/community-music-school method books.
- needs: Audio classification needs to distinguish 3 stroke types by timbre, not just onset timing — a moderate but well-scoped addition to the existing percussive-onset module.
- caveat: None on demand; audio-classification nuance is the only real cost.
- url: https://bmusician.com/djembe-classes-online/
### Bongos / Congas
- pop: Part of the same hand-percussion market growth as cajon/djembe; core to salsa, Afro-Cuban, and Latin jazz percussion sections and taught in most contemporary percussion programs.
- feas: ✅ Hands and drumheads visible from a single front camera in both seated (bongos) and standing (congas) setups; maps directly onto the percussion-onset module.
- curr: No formal grade-exam ladder; taught through Latin-percussion method books (Changuito, Giovanni Hidalgo pedagogy lineage) and community/university Latin-music programs.
- needs: Multi-drum stroke/tone classification similar to djembe (open tone, slap, muffled/heel-toe for congas).
- caveat: None significant — config/audio-classification extension of the same percussion module as cajon/djembe, good Wave A bundling.
- url: https://dataintelo.com/report/global-hand-percussion-market
### Tabla
- pop: Deep classical-conservatory tradition (guru-shishya lineage, Bhatkhande and other Indian music institutes); strong and growing online-course market (Artium Academy, ipassio, Gandharva School of Music, Bhatkhande Music Institute online offerings) serving both India and its global diaspora.
- feas: ✅ Both hands and both drums are visible from a single front camera in the standard seated cross-legged posture.
- curr: Guru-shishya parampara (oral/lineage-based) tradition plus formal conservatory diploma tracks (e.g. Bhatkhande, Prayag Sangit Samiti) — not a Western-style numbered grade ladder.
- needs: Audio side needs to classify a large bol vocabulary (dha, dhin, ta, ge, etc.) including pitch-modulated strokes from bayan heel pressure — a genuinely new, higher-complexity extension of the percussion module, not a simple onset detector.
- caveat: Strong qualitative evidence of demand (many dedicated academies), but no hard 'X million learners' figure was found in this pass — flag as directionally strong, not numerically verified.
- url: https://artiumacademy.com/course/online-tabla-classes
### Steel Pan
- pop: Pan is part of official school curricula in Trinidad & Tobago; university steelband programs exist across the US (Ohio State, University of Washington) and Northwestern offers pan studies as part of a B.Sc. Music major; active diaspora youth steelbands in NYC (Steel Sensation Steel Orchestra).
- feas: ✅ Mallets and pan surface fully visible from a single camera positioned above/in front of the instrument.
- curr: No single global grade ladder; taught through steelband ensemble apprenticeship in Trinidad's school system and university steelband programs, plus dedicated method books emerging from those programs.
- needs: New pitched-percussion module: mallet-strike detection plus a per-pan-type note-layout map (tenor pan layout differs substantially from bass pan) — real config complexity because there is no single standardized pan layout.
- caveat: Genuine institutional demand, but scale is modest compared to Wave A/B instruments — good Wave C candidate, not a headline addition.
- url: https://whensteeltalks.ning.com/forum/topics/revisiting-a-dream-coming-true-pan-in-the-schools-of-trinidad-and
### Kalimba
- pop: Strong TikTok/Instagram-driven virality with millions of views on kalimba cover videos; growing retail/Etsy-driven sales market; positioned explicitly as a beginner-friendly, near-instant-gratification instrument.
- feas: ✅ Extremely simple camera case — small instrument, both thumbs fully visible, tines produce a clear monophonic-to-lightly-polyphonic pitched signal well suited to the existing monophonic-pitch or Basic-Pitch chord-class module.
- curr: No conservatory/grade-exam tradition — almost entirely informal, tutorial-video/app-based learning (YouTube, dedicated kalimba apps with tab notation).
- needs: None significant — config-only extension of an existing pitch module.
- caveat: Popularity is real but is casual-hobbyist virality, not 'serious course demand' in the conservatory/grade-exam sense the other evidence categories use — flag this distinction explicitly to the founder so expectations (retention, depth of curriculum) are set correctly.
- url: https://www.marketresearchintellect.com/blog/kalimba-market-hits-high-notes-internet-and-tech-innovations-drive-new-wave-of-interest/
### Melodica
- pop: Standard elementary-school instrument in Japan (and used in some other Asian school systems) under the 'pianica' brand name; smaller but real Western hobbyist/beginner market via reggae/dub and singer-songwriter use (Augustus Pablo association).
- feas: ⚠️ Keys are visible like piano, but breath/mouthpiece connection and one-handed playing posture is a distinct physical configuration not identical to either the wind or keyboard module alone.
- curr: No formal grade-exam ladder; taught as part of Japan's standard elementary music curriculum and informally elsewhere.
- needs: Small new hybrid module (keyboard fingering + breath-control monophonic pitch) — moderate but well-scoped new work given only one hand plays keys.
- caveat: Japan school-market evidence is strong by common knowledge but not independently re-verified with a fresh source in this research pass — flag for a targeted follow-up search before committing to marketing claims about Japan specifically.
- url: https://www.abrsm.org/en-us/instruments/
### Tin Whistle
- pop: Universal beginner instrument within Irish traditional music education (comparable role to recorder in general music education); Comhaltas runs classes across Ireland, UK, US, and the Irish diaspora globally.
- feas: ✅ Same visibility class as recorder — finger-hole coverage is the whole signal, no reed/embouchure subtlety, monophonic pitch is trivial for the existing pitch module.
- curr: No formal grade-exam ladder; taught through Comhaltas classes, seisiún (session) culture, and dedicated Irish-trad method books/tutors (e.g. Bill Ochs' tin whistle method).
- needs: None — essentially a config variant of the recorder module (different diatonic hole-spacing/ornamentation vocabulary — rolls, cuts, cranns).
- caveat: Niche relative to global instruments overall, but very deep within its specific (large, active) community — good low-cost Wave A bundle with recorder.
- url: https://www.classcentral.com/subject/oud
### Bagpipes
- pop: Strong niche demand within Scottish/Irish diaspora communities, pipe bands, and military/ceremonial piping traditions worldwide; formal grade/qualification systems exist (e.g. Piping and Drumming Qualifications Board in Scotland).
- feas: ❌ for full pipes / ⚠️ for practice chanter only. Full Great Highland Bagpipes require continuous arm-pressure on the bag to sustain drone+chanter airflow — an extreme, sustained physical technique with essentially no useful single-camera pose signal, and the sound is extremely loud/unsuited to a phone mic or home practice context. The practice chanter (mouth-blown reed, no bag, monophonic, standard beginner tool for all pipers) is a realistic, honest scope: fingering is visible, pitch is monophonic and mic-friendly.
- curr: Formal piping qualification systems in Scotland/Canada; beginners universally start on the practice chanter for 6–12+ months before touching the full pipes.
- needs: Scope strictly to practice-chanter coaching (maps onto the wind/monophonic-pitch module, config-only); do not market this as 'learn bagpipes' without that caveat.
- caveat: Full-instrument coaching is a physical/practical ❌; practice-chanter coaching is a legitimate ⚠️ niche addition. Marketing must be precise about which is offered.
- url: https://en.wikipedia.org/wiki/Bagpipes
### Oud
- pop: Class Central lists 40+ oud online courses; strong presence in Arabic maqam-tradition conservatories and online tutorial ecosystems (OudforGuitarists, Arab Instruments), but the broader MENA e-learning market research found in this pass shows oud as a niche subject relative to dominant categories (IT/business skills), not a headline demand driver.
- feas: ✅ Fretless neck and both hands (fretting hand + risha plectrum hand) fully visible from a single camera, same general framing as guitar/lute.
- curr: No Western-style numbered grade ladder; taught through maqam-based conservatory tracks (e.g. Cairo, Beirut, Istanbul conservatories) and informal online tutorial ecosystems.
- needs: New plucked-string module variant needed because oud is fretless (pitch detection must work from bare fingerboard position, not fret-triggered chord shapes like guitar/ukulele) and uses quarter-tone maqam scales the existing chord-class module isn't built for.
- caveat: Real but modest, specialist demand; global course-demand evidence is thinner than the guzheng/sitar/tabla cases — treat as Wave C, not a headline non-Western addition.
- url: https://www.classcentral.com/subject/oud
### Bağlama / Saz
- pop: Central instrument in Turkish folk (âşık/ozan) tradition and state conservatory curricula (bağlama is the term used in Turkish conservatories, saz colloquially); multiple online course providers exist (Baraksaz, Farabius, Labyrinth Online) reaching the global Turkish diaspora, but no hard 'X million learners' figure was found.
- feas: ✅ Fretted neck, both hands visible from a single camera — same general framing class as guitar/banjo.
- curr: Turkish state conservatory (bağlama bölümü) curricula with formal grading; also taught informally through âşık-tradition apprenticeship and diaspora community schools.
- needs: New plucked-string module variant for movable frets (bağlama frets are tied gut/nylon and adjustable for microtonal Turkish makam intonation) — closer to oud's fretless-adjacent challenge than to guitar's fixed frets.
- caveat: Strong cultural/strategic case (Turkey base) but genuinely thin global course-demand statistics in this research pass — good candidate for a Turkey-market-specific wave rather than being justified purely on 'global demand' grounds.
- url: https://salamuzik.com/blogs/news/what-is-a-baglama-the-complete-guide-to-turkeys-most-beloved-instrument
### Sitar
- pop: Market research cites international conservatories (Berlin, London, Boston) formally adding sitar to world-music electives since 2024, online sitar-lesson enrollment reportedly growing >22%/year since 2023 across platforms like TakeLessons and India-based e-learning, and Indian classical content showing double-digit streaming growth on Spotify/Apple Music/YouTube Music.
- feas: ⚠️ Both hands are visible (fretting hand plus plucking hand with mizrab plectrum), but sitar's sympathetic strings, meend (pitch-bending by pulling the string sideways across the fret), and movable curved-fret tuning make pitch/technique detection meaningfully harder than a fixed-fret Western string instrument.
- curr: Guru-shishya parampara lineage tradition (Maihar gharana, Imdadkhani gharana, etc.) plus increasing formal conservatory elective adoption internationally; no numbered grade ladder comparable to ABRSM.
- needs: New plucked-string module variant handling meend (bent pitch) and sympathetic-string resonance in the audio signal — a real engineering lift, comparable to guzheng/erhu.
- caveat: Market-research figures (CAGR, enrollment growth %) come from B2B report abstracts without transparent methodology — treat as directional evidence of real demand, not verified statistics.
- url: https://dataintelo.com/report/global-sitar-market
### Erhu
- pop: A 2015 China Folk Music newspaper report cited ~600,000 young erhu players, dwarfed by guzheng's much larger base; still a substantial, culturally central instrument taught in Chinese conservatories (e.g. Central Conservatory of Music) and via a large domestic online-education market.
- feas: ⚠️ This is NOT a config variant of the approved violin/cello bowed-string module — the vertical hold, bow-between-strings mechanism, and fingerboard-less light-touch fingering are a fundamentally different physical technique requiring a new pose state-machine, not a tuning/size config change.
- curr: Chinese conservatory grade systems exist (e.g. Central Conservatory of Music grading, China Conservatory grading) with numbered levels roughly analogous to ABRSM grades.
- needs: New bowed-instrument pose state-machine (vertical posture, bow-insertion mechanics, no-fingerboard pitch detection) — meaningfully more engineering than viola/double-bass.
- caveat: The 600,000-learner figure is from 2015 and likely understates current demand, but no more recent hard number was found in this pass — flag for a follow-up search before using in planning materials.
- url: https://www.ecns.cn/2017/10-18/277530.shtml
### Guzheng
- pop: Widely cited as the most-studied traditional Chinese instrument, with a commonly repeated figure of ~10 million students in China; strong domestic online-education growth (China's paid digital-music sector grew ~28.4% in 2024 per market coverage) with platforms actively localizing curricula around guzheng and erhu.
- feas: ✅ with new work: strings and both hands are clearly visible on a horizontal instrument viewed from above/front by a single camera, but the module logic is genuinely new — each string is pre-tuned to a pentatonic scale (not fretted/fingered like guitar) and the left-hand pitch-bending behind the bridge is guzheng's signature technique, unlike anything in the existing plucked-string-chord module.
- curr: Chinese conservatory grading systems (Central Conservatory of Music, China Conservatory of Music, and the Chinese Musicians' Association's 1–10 grade ladder) are well-established and widely used, including for overseas Chinese-heritage students.
- needs: New plucked-zither module: fixed-pitch-per-string plucking detection plus left-hand pitch-bend/vibrato tracking — a real build, but the ~10M learner-base claim (if verified) would justify it as one of the highest-ROI additions on this entire list.
- caveat: The 10-million figure needs primary-source verification (it recurs across secondary summaries without a clearly cited original survey) before being used in investor-facing materials, even though directionally it is very likely the largest single non-Western learner population evaluated here.
- url: https://chinaalbums.com/guzheng-complete-guide/
### Pipa
- pop: One of the core 'four great instruments' of traditional Chinese music education alongside guzheng, erhu, and dizi; strong presence in Chinese conservatory curricula and a growing domestic online-course market, though no isolated learner-count figure was found in this pass (guzheng/erhu figures were specific, pipa's was not).
- feas: ⚠️ Closer to the existing plucked-string-chord module than guzheng (it is fretted, like guitar/banjo), but the vertical holding posture and the tremolo (lunzhi) technique — rapid alternating fingerpick strokes on a single note, central to pipa's idiomatic sound — are not covered by the guitar-chord module's strum/pick detection and need a dedicated technique-detection addition.
- curr: Same Chinese conservatory grading ladder (Central Conservatory of Music etc.) as guzheng/erhu; well-documented formal grade system.
- needs: Moderate new work: vertical-hold pose adaptation + tremolo-stroke audio/motion detection layered onto an otherwise guitar-like fretted-plucked-string base.
- caveat: No isolated pipa-specific learner-count evidence found in this pass — popularity is inferred from its status as one of China's 'big four' traditional instruments, not independently quantified; flag as directionally strong but unverified.
- url: https://markwideresearch.com/traditional-chinese-instruments-market/
### Koto
- pop: Historically standard in Japanese school music education and traditional-arts (iemoto) schools; smaller than guzheng's China-scale numbers but a real, sustained conservatory and cultural-heritage tradition with renewed global interest via Japanese-media/game-soundtrack exposure.
- feas: ✅ if the guzheng zither module is built first — koto's horizontal-zither, movable-bridge, plucked-with-picks mechanics are structurally close enough to guzheng to be largely a config variant (13 vs 21 strings, different tuning/scale conventions) rather than a second from-scratch module.
- curr: Japanese iemoto (school-lineage) certification tradition (e.g. Ikuta-ryū, Yamada-ryū schools) rather than a Western numbered-grade system; some conservatory programs internationally now offer koto electives.
- needs: Minimal beyond the guzheng module — mostly string-count/tuning config once that module exists.
- caveat: No fresh learner-count evidence gathered in this pass — popularity claim rests on well-known institutional/cultural presence rather than a cited statistic; flag as qualitatively strong, not numerically verified here.
- url: https://www.abrsm.org/en-us/instruments/
### Shamisen
- pop: Traditional accompaniment instrument for kabuki, bunraku puppet theatre, and geisha performance in Japan; smaller and more specialist learner base than koto, with some global niche interest driven by anime/game soundtrack fans (notably tsugaru-shamisen virtuoso performance videos going viral internationally).
- feas: ⚠️ Fretless neck and both hands visible from a single camera, but the bachi's dual role — striking strings for pitch AND striking the body/drumhead for percussive accent — is a hybrid melodic+percussive technique unlike any existing module (plucked-string-chord assumes pitch-only plucking).
- curr: Japanese iemoto/school-lineage tradition rather than a numbered grade system; regional style variation is significant (tsugaru-shamisen vs. nagauta-shamisen use different playing styles).
- needs: New hybrid module combining fretless pitch detection with percussive body-strike classification — a genuinely novel build, not a config variant of anything approved.
- caveat: No hard learner-population or global-course-demand statistic found in this pass; treat popularity as real-but-niche and evidence as thin — do not present as a high-demand item without further verification.
- url: https://en.wikipedia.org/wiki/Shamisen
### Charango
- pop: Core instrument of Andean folk ensembles across Bolivia, Peru, Ecuador, and northern Argentina/Chile, with some international niche popularity through world-music and Andean-folk performance groups touring globally; no global online-course-demand evidence was found in this research pass.
- feas: ✅ Fretted, both hands visible, small-instrument framing very similar to ukulele — a strong config-only candidate for the plucked-string-chord module (different tuning, course-pairing).
- curr: No formal grade-exam ladder; taught through Andean-folk-tradition apprenticeship and some regional conservatory folk-music programs (e.g. in Bolivia and Peru).
- needs: None beyond tuning/course-pairing config.
- caveat: Thin evidence: no course-demand or learner-population statistics were found; this is a real, technically easy addition but should be scoped as a regional/community-request item, not justified by strong global-demand data.
- url: https://en.wikipedia.org/wiki/Charango
### Balalaika
- pop: Iconic Russian folk instrument, taught in Russian regional music schools and folk-ensemble traditions, plus diaspora community schools in the US/Europe; no global online-course-demand evidence was found in this research pass.
- feas: ✅ Fretted, both hands visible, small-to-medium body — straightforward config-only candidate for the plucked-string-chord module (distinctive triangular body doesn't change hand-visibility).
- curr: Russian regional music-school curricula and folk-ensemble apprenticeship traditions; no international numbered grade-exam system found.
- needs: None beyond tuning config.
- caveat: Thin evidence: no course-demand or learner-population statistics were found; genuinely regional/niche (Russia and diaspora) rather than demonstrated global demand — treat as community-request-driven, not a headline addition.
- url: https://en.wikipedia.org/wiki/Balalaika
### DJ / Electronic Music Production
- pop: Very large, well-documented course-demand market: MasterClass offers DJ/production instructors (deadmau5), Pete Tong DJ Academy reaches thousands of DJs/producers across 140 countries, Point Blank Music School has operated since 1994, and multiple dedicated academies (Toolroom Academy, Funktasy Academy) compete for this market.
- feas: ❌ Not a fit for Ostinato's posture+audio coaching thesis. There is no body posture/technique to correct comparable to holding an instrument — DJing/production is primarily software-workflow and ear-training skill (beatmatching, EQ balancing, arrangement), which a MediaPipe pose engine has nothing to evaluate. The 'audio' being produced is the student's mix output, not a live acoustic performance the rule engines are built to score.
- curr: No conservatory/grade-exam tradition; taught through dedicated DJ/production academies and DAW-specific tutorial ecosystems (Ableton, Serato, Rekordbox certifications).
- needs: Would require an entirely different product category (screen-capture/DAW-state coaching, not pose/audio-from-microphone coaching) — fundamentally outside Ostinato's architecture.
- caveat: This is the one explicit ❌ on the list for architectural/product-fit reasons, not lack of demand — demand is real and large, but it doesn't belong inside Ostinato; recommend treating it as a distinct potential product if the founder wants to pursue it, not as instrument #14+.
- url: https://www.zipdj.com/blog/best-online-dj-courses


# ==== choreia-more-dances ====

## SUMMARY
Web research (July 2026) evaluated 15 candidate global dance styles for Choreia's solo-learnable expansion. STRONG ADDS (✅, good popularity + curriculum + camera/engine fit): Ballroom/Latin solo technique (uniquely backed by formal ISTD/WDSF graded syllabi across cha-cha/rumba/jive/waltz/quickstep/paso doble — the best-documented curriculum source found in this entire pass), Tap Dance (ISTD 6-level syllabus + 315-step dictionary; best audio-onset-engine fit of any style researched — literal percussion), Flamenco (inherently solo, UNESCO-recognized, global academies, zapateado footwork is also an onset-engine fit), Irish Dance (Riverdance's massive global reach, feiseanna are explicitly solo-competitive, hard-shoe work is onset-friendly), Samba no Pé (inherently solo carnival samba, good rhythm-engine fit — but keep distinct from partnered Samba de Gafieira, which should NOT be added separately), Locking/Popping/Waacking/Vogue as a bundled 'Funk Styles' pack (founder correctly identified these as a real gap versus the current afrobeats/house-heavy street catalog; all four are solo/battle-style by design and share a content-development profile), Merengue-solo/Cumbia-solo (lowest-risk item — directly reuses the already-shipped bachata-solo/salsa-shines content pattern), Bhangra and Garba (both genuinely large diaspora-driven demand, though Garba is sharply seasonal and its Dandiya stick-variant is NOT solo-learnable and should be excluded), Solo Jazz/Charleston/Shim Sham (smaller but real, well-networked global Lindy scene with a literal named fixed routine, the Shim Sham). CAUTION/DEFER: Hula — thinner course-supply evidence AND a real cultural-appropriation/sacred-practice risk that argues for a direct hālau/kumu-hula partnership before building, not a generic content pull. Amapiano — viral on social media (73M+ TikTok views) but lacks a stable named-step vocabulary, better treated as a rotating trend-pack inside the existing Afrobeats module than a standalone curriculum line. Reggaeton/Perreo-solo — culturally legitimate (danced solo by design) but content-tone/app-store-policy considerations mirror twerk (already approved), so it should be scoped as an adjacent addition to that existing sensitive-content bucket rather than a fresh line, and evidence is YouTube-tutorial-level rather than syllabus-level. NOT recommended as standalone: Samba de Gafieira solo (evidence too thin — fold into Samba no Pé as an advanced tier), Dandiya-Raas as a distinct item (inherently a two-person stick-striking dance, not solo). Not independently researched due to very thin/absent global evidence in initial passes and low likely ROI versus the above: Kuduro, Dabke, Greek sirtaki/folk, Country two-step — flagged as low-priority/uncertain rather than confidently rated.

## RECOMMENDATIONS
- Prioritize Tap and Ballroom/Latin solo technique first — they are the only two styles here backed by a formal, citable global syllabus body (ISTD/WDSF), which minimizes curriculum-design risk and maximizes credibility/marketing claims ('follow the real ISTD syllabus').
- Ship Locking, Popping, Waacking, and Vogue together as a single 'Funk Styles' expansion rather than four separate SKUs — they share heritage, audience, and content-development profile, and this directly closes the gap the founder flagged as a likely miss.
- Add Merengue-solo and Cumbia-solo as fast-follow, low-risk items since they reuse the already-validated bachata-solo/salsa-shines content pattern with minimal new production model needed.
- Treat Flamenco and Irish Dance as second-wave adds — both are excellent engine/curriculum fits but require more original content development (no global syllabus body) than the ISTD-backed items.
- Hold Hula pending a direct partnership/consultation with a hālau or kumu hula — do not build from generic web sources given its status as a living, protected cultural-spiritual practice.
- Fold Amapiano into the existing Afrobeats module as a rotating trend-pack rather than a stable curriculum line, since its step vocabulary changes on a viral-trend cycle rather than being fixed.
- Before adding Reggaeton/Perreo-solo, confirm app-store content-policy posture given it would be the second style (after twerk) in the sensually-expressive content bucket.
- Scope Garba narrowly to solo footwork/clapping technique and explicitly exclude the Dandiya stick-partner variant, which cannot be solo-learned as traditionally performed.
- Run a follow-up quantitative demand check (Google Trends, app-store competitor keyword scan) specifically for 'Samba no Pé' and 'ISTD ballroom solo technique' before final prioritization — the qualitative evidence found here is solid but not volume-quantified.
- Deprioritize or drop Kuduro, Dabke, Greek folk/sirtaki, and Country two-step from this expansion round — evidence gathered was too thin to clear the 'GLOBAL, heavily-taught, big-audience' bar the founder set; revisit only if a specific regional-market push justifies them.

## RISKS
- Vogue and Hula both carry real cultural-origin/appropriation sensitivity (Black/Latino LGBTQ+ ballroom culture for Vogue; sacred Hawaiian practice for Hula) — curriculum and marketing framing must credit origins accurately and, for Hula, likely requires direct community partnership rather than generic sourcing.
- Tap and Irish hard-shoe styles have a genuine hardware/environment dependency (proper shoes + hard resonant floor) that is a real adoption-friction risk not present in the barefoot/sneaker styles already in the catalog — must be clearly flagged in onboarding.
- Reggaeton/Perreo and the already-approved Twerk sit in a sensually-expressive content bucket that carries app-store content-policy and marketing-tone risk; adding more styles to this bucket compounds that exposure and should be reviewed with store-policy in mind before building.
- Several 'why-relevant' claims (course-demand for Samba de Gafieira solo, Amapiano's stable curriculum, Dabke/Kuduro/sirtaki/country-two-step demand) rest on thin or absent web evidence — treat as unconfirmed rather than validated, and do not greenlight production budget based on this research alone for those items.
- No single global syllabus body exists for Samba, Flamenco, Bhangra, Garba, Vogue/Waacking/Locking/Popping, Hula, or Merengue/Cumbia/Reggaeton solo styling — unlike Tap and Ballroom/Latin (ISTD/WDSF-backed), these will require original curriculum authorship, which raises content-development cost and time versus the two syllabus-backed picks.

## ITEMS
### Samba no Pé (Brazilian Carnival Solo Samba)
- pop: Global — studios teaching Samba no Pé/Passista found in UK (Samba de Rainha), US (SambaBrazil San Diego, EducArte, Sacramento Brazilian Center, Rae Studios SF), plus subscription online catalog (Samba Fusion, weekly new classes). Anchored in Rio Carnival's global media reach, but course-supply evidence is mid-size studios, not mass MOOC-scale (no Coursera/Udemy giant found) — flag as good-not-huge evidence.
- feas: ✅ — single fixed front camera works well: samba no pé is stationary/small-radius footwork+hip isolation, ideal for pose landmarks on hips/knees/ankles at high angular velocity. RhythmEngine (beat-grid) is a strong fit since samba is a percussion-driven genre in ~90-100 BPM samba feel (double-time surdo pulse) — the existing rhythm engine's beat-grid timing scorer maps directly.
- curr: Foundational steps: marcação (basic bounce/weight transfer), passo básico, hip/shoulder isolation drills, arm styling (braços), samba no pé travel patterns, passista turns/kicks for advanced. No single global syllabus body (unlike ballroom ISTD) — technique is transmitted via samba schools (escolas de samba) and named teachers (e.g., Samba Fusion's structured beginner→pro tiers).
- needs: None beyond normal studio floor; barefoot or soft shoes traditional. High-BPM footwork needs a full-body/lower-leg-visible camera frame.
- caveat: Distinguish from Samba de Gafieira/partner ballroom-samba (ISTD Latin 'Samba') which is a couple's dance — do NOT conflate. Course-supply evidence found is boutique-studio level, not confirmed at Udemy/Coursera mass-course scale; recommend a follow-up demand check (Google Trends / app-store competitor scan) before greenlighting build priority.
- url: https://sambaderainha.uk/
### Samba de Gafieira solo styling / technique drills
- pop: ⚠️ Thin — could not find dedicated global 'Gafieira solo styling' course catalogs; Gafieira itself is a real, named Brazilian couple-dance genre but online solo-technique offerings are sparse compared to Samba no Pé.
- feas: ⚠️ Feasible technically (single camera, footwork+turns) but ❌ NOT justified as a separate catalog item given thin, largely absent global solo-course evidence — recommend folding into the Samba no Pé module as an 'advanced styling' tier rather than a standalone dance.
- curr: Not independently documented at solo-course scale.
- needs: Same as samba no pé.
- caveat: Do not add as a separate SKU; evidence too thin to justify a distinct curriculum build.
- url: https://www.escoladesambafusion.com/downloadable-classes
### Ballroom/Latin Solo Technique (Cha-Cha, Rumba, Jive, Waltz, Quickstep, Paso Doble)
- pop: Global and deep: ISTD (UK, operating in 60+ countries) and WDSF (World DanceSport Federation, Olympic-recognized discipline) both publish graded syllabi (Bronze→Gold→Gold Star, per dance: Rumba/Cha-Cha/Samba/Jive/Paso Doble for Latin; Waltz/Quickstep/Tango/Foxtrot/V.Waltz for Standard). This is the single strongest 'named steps + syllabus' evidence base found in this whole research pass.
- feas: ✅ single fixed camera works for solo technique/foot-placement/frame drills (the standard 'practice syllabus alone' format ballroom students already do); ⚠️ constraint: full couple figures (rotational partnering, contact-frame) are out of scope — must scope strictly to solo/technique-only syllabus content, which IS a standard, separately-sold product (e.g. 'International Latin Series' solo classes).
- curr: ISTD graded syllabus: Pre-Bronze→Bronze→Silver→Gold→Gold Star 1-3 per dance; each level names specific figures (e.g., Cha-Cha: Basic Movement, New York, Spot Turns; Rumba: Basic Movement, Fan, Hockey Stick; Waltz: Natural/Reverse Turn, Whisk, Chassé). WDSF offers a parallel international competitive syllabus.
- needs: Smooth-soled dance shoes recommended for turns; otherwise none. BPM ranges are dance-specific and well-documented (Cha-Cha ~30 bars/min, Waltz ~28-30 bars/min, Jive ~44 bars/min) — good fit for RhythmEngine tempo-lock.
- caveat: This is arguably a BIGGER and better-documented opportunity than 'Tango solo' alone (already approved) — recommend treating full ISTD/WDSF ballroom syllabus as its own multi-dance module family rather than one line item.
- url: https://www.istd.org/documents/latin-american-syllabus-outline/latin-american-syllabus-september-24.pdf
### Flamenco (solo by definition)
- pop: Global — dedicated academies in UK (City Academy London), US (multiple city-level Theatre Flamenco/DanceUs.org listings), Spain (Taller Flamenco Seville — international students), plus a subscription-model global online studio (Online Flamenco Studio, 80+ courses). UNESCO-recognized Intangible Cultural Heritage, reinforcing global-institutional weight.
- feas: ✅ excellent fit: zapateado footwork is loud, sharp, and PERCUSSIVE — same 'audio-onset engine can hear it' logic the founder applied to tap applies directly to flamenco footwork+palmas; single fixed camera captures full-body arm/torso/foot coordination well.
- curr: Named forms (palos) by rhythm: Soleá, Alegrías, Bulerías, Tangos, Sevillanas (12/8, 4/4, 12-count compás variants); technique drills: zapateado (heelwork), braceo (arms), floreo (wrist), golpe (flat-foot stamp), palmas (hand-clap rhythm). Academies teach graded levels (beginner→intermediate→advanced) but no single global syllabus body like ISTD exists — transmission is teacher-lineage based.
- needs: Flamenco shoes (nailed heel/toe) strongly recommended for authentic sound and floor protection; a resonant/wood floor improves audio-onset detection; palmas (hand-clap) patterns could be a bonus audio-rhythm layer alongside footwork.
- caveat: No global syllabus body — curriculum will need original design from named-palo technique references (higher content-creation cost than ISTD-backed dances).
- url: https://www.onlineflamencostudio.com/
### Tap Dance
- pop: Global, deep, and formally syllabus-backed: ISTD Tap Faculty (UK-based, international reach) publishes 6 Popular Tap levels + 3 medal exams; separately, the '315 Tap Dictionary/Syllabus' (United Taps) and Al Gilbert Tap Technique are widely used North American teaching standards. Tap is a fixture of dance-school curricula worldwide (children's studios through pro conservatories).
- feas: ✅ Best-fit item in the whole set: (1) camera — pose landmarks on ankles/feet track the mechanics, but sound is the primary signal; (2) audio — the existing percussive-onset engine can score individual tap sounds (flap vs. shuffle vs. stamp have distinct onset/spectral signatures), enabling objective rhythmic-accuracy scoring no pose-only competitor offers. This is a genuine engine-differentiator, not just a content add.
- curr: 315-step dictionary organized in 7 learning-order levels (Al Gilbert / United Taps systems); ISTD's parallel 6-level Popular Tap + medal syllabus. Named steps: shuffle, flap, ball-change, riff, wing, Maxi-Ford, time step (multiple named variations), pullback.
- needs: REQUIRES actual tap shoes (metal toe/heel plates) AND a hard, resonant, unmiked floor — this is a hardware/environment dependency the app must state clearly (won't work on carpet, barefoot, or soft-soled shoes); needs a decent microphone/audio path, not just camera mic assumptions.
- caveat: Hardware dependency (tap shoes + hard floor) is a real adoption friction the other dance styles don't have — should be flagged prominently in onboarding/marketing, not treated as a drop-in like hip-hop.
- url: https://www.istd.org/documents/tap-dance-syllabus-outline/
### Irish Dance (solo step dance)
- pop: Global: Riverdance performed at 450+ venues, seen by 25M+ people since 1994, 30th-anniversary tour running 2026; feiseanna (200+ registered local competitions/year) held not just in Ireland but US, Canada, UK, Australia, South Africa, and across Europe/Asia wherever Irish diaspora communities exist. IDTANA (North America) governs a large graded solo-competition structure.
- feas: ✅ hard-shoe = percussive audio-onset fit (like tap); ⚠️ soft-shoe (reels/jigs, high jumps, pointed toes) is primarily a pose/timing challenge rather than audio — camera must capture full body including high leaps, so frame/distance calibration matters more than for floor-bound styles.
- curr: Graded solo levels (Beginner→Novice→Prizewinner→Preliminary Championship→Open Championship per most national bodies); named dances: reel, jig (single/double/slip), hornpipe, treble jig, traditional set dances — each with codified step counts.
- needs: Hard shoes (fiberglass-tipped heel/toe) for percussive dances; soft ghillies for reels/jigs/slip jigs — two different shoe types needed for full curriculum coverage.
- caveat: Competitive-syllabus detail (exact step names per grade) varies by governing body (An Coimisiún, IDTANA, etc.) — will need to pick one lineage as canonical rather than blend.
- url: https://idtana.org/types-of-irish-dance/
### Solo Jazz / Charleston / Shim Sham (Swing family solo)
- pop: Global grassroots scene: Lindy Hop/Solo Jazz communities and drop-in classes documented across UK (multiple cities), Germany (Berlin Meetup group), Australia (Perth Swing Dance Academy), plus Udemy-hosted structured courses — a real worldwide subculture with recurring in-person classes in most major cities, though smaller in raw headcount than hip-hop/salsa.
- feas: ✅ solid: solo, floor-based, moderate tempo, well within single-camera pose tracking; rhythm-engine fits swing's syncopated 4/4 feel well.
- curr: 'ABC of Jazz steps' progression → named moves (Charleston basic/variations, Susie-Q, Boogie Forward, Tacky Annie, Shorty George, Fall Off The Log) → the Shim Sham as a fixed 32-count named routine taught nearly identically at every scene worldwide — genuinely syllabus-like without a formal certifying body.
- needs: None special; regular sneakers/dance shoes.
- caveat: Smaller total audience than mainstream street styles — good cultural/curriculum fit, moderate popularity tier, not top-tier mass demand.
- url: https://perthswingdanceacademy.com/solo-charleston-and-authentic-jazz/
### Bhangra
- pop: Global: 'Learn Bhangra' brand explicitly serves users in 50+ countries, is taught in university curricula, and is a fixture at South Asian diaspora cultural events across US/UK/Canada/Australia; hybridizes with hip-hop/Bollywood in mainstream studios, extending its reach further.
- feas: ✅ good fit: upper-body/shoulder isolation + energetic footwork readable by single fixed camera; fast tempo folk-drum (dhol) rhythms suit the beat-grid RhythmEngine well.
- curr: No single global syllabus body, but Learn Bhangra's structured 'high-intensity curriculum' + app indicates a teachable, leveled progression exists commercially; named core moves include jhumar, bhangra jumps, shoulder shrugs, and dhol-matched footwork patterns.
- needs: None required; energetic — flag as moderate-cardio like Zumba-style.
- caveat: Curriculum content will likely need original development/licensing conversation with an org like Learn Bhangra rather than pulling from a public syllabus body.
- url: https://www.learnbhangra.com/
### Garba / Dandiya-Raas (solo/individual technique)
- pop: Global and large but SEASONAL: major presence in India plus US, UK, Canada, Australia, UAE, New Zealand diaspora communities; ~20 universities globally host annual Garba competitions.
- feas: ✅ Garba (footwork/clapping, no props) fits single-camera solo practice well; ⚠️ Dandiya-Raas is fundamentally a paired/group stick-striking dance (partner needed to strike sticks together) — NOT solo-learnable as traditionally performed, so should be scoped OUT or limited to solo stick-twirling drills only.
- curr: No formal global syllabus; content would be original (named Garba step patterns exist regionally — e.g., 'do taali', 'trikoni' — but not standardized like ISTD).
- needs: Dandiya requires two wooden sticks (props) if that variant is included at all — camera-based partner-strike timing is out of scope for a single-user single-camera app.
- caveat: Strong seasonal spike-only demand (concentrated around Navratri) — plan content release/marketing timing accordingly rather than treating as evergreen like hip-hop.
- url: https://kalasanskriti.org/garba-the-joyful-dance-of-gujarat/
### Vogue / Waacking (street-funk, solo-performance styles)
- pop: Global: dedicated open classes found in London (FABRIC), US ballroom-scene hubs (NYC/LA/Chicago historically), and mainstream studio menus increasingly list 'Vogue/Waacking' as standard alongside Locking/Popping/House (per ISTD's own Street Dance genre page and Red Bull's dance style guide, both treating these as core recognized street-dance pillars).
- feas: ✅ good fit: both are floor-based/standing solo choreography readable by single fixed camera; Waacking's fast arm-whip technique is highly visible to upper-body pose tracking; Vogue's hand-performance/floor work needs a slightly wider frame to catch ground-level movement.
- curr: Vogue: 5 elements typically taught (hand performance, catwalk, duckwalk, floor performance, dips/spins) across Old Way/New Way/Vogue Fem styles; Waacking: named arm/wrist whip technique, poses, and musicality drills rooted in 1970s LA disco clubs. No single global certifying syllabus body (transmitted via ballroom-scene/house lineages and named pioneering teachers) — similar content-development profile to flamenco/hip-hop.
- needs: Floor-work sections (Vogue dips/floor performance) need adequate room clearance in frame; otherwise none.
- caveat: Cultural-origin sensitivity: Vogue comes specifically from Black and Latino LGBTQ+ ballroom culture — curriculum/marketing framing should credit ballroom-scene origins accurately rather than presenting as generic 'street dance.'
- url: https://fabric.dance/events/vogue-and-waacking-open/
### Locking / Popping (street-funk foundational styles)
- pop: Global — long-established via battles (Juste Debout, Freestyle Session), mainstream studio menus worldwide, and Olympic-adjacent visibility through breaking's 2024 Olympic debut raising funk-styles' profile generally.
- feas: ✅ strong fit: both are isolation-based, largely stationary-to-moderate movement styles — ideal for single fixed camera + pose-landmark isolation scoring (Popping's precise muscle-hit timing is a great match for the existing beat-grid RhythmEngine; Locking's named freeze-points are good state-machine targets).
- curr: Locking named moves: Lock, Point, Skeeter Rabbit, Which-a-way, Scooby Doo, Stop-and-Go; Popping named techniques: Pop/Hit, Wave, Tutting, Robot, Strobe/Animation, Ticking, Glide. No single global syllabus body — technique passed through named-pioneer lineages (Don Campbell for Locking; Boogaloo Sam/Electric Boogaloos for Popping), similar development profile to breaking/hip-hop already in the catalog.
- needs: None special.
- caveat: Should likely ship together (Locking+Popping+Waacking+Vogue as one 'Funk Styles' expansion) since they share the same solo-battle heritage, audience, and curriculum-development profile — bundling reduces content-dev overhead vs. four separate SKUs.
- url: https://www.istd.org/dance/dance-genres/street/
### Hula (Polynesian)
- pop: Global reach via diaspora + tourism-driven interest, but core practitioner base is smaller/more culturally concentrated than mainstream commercial dance genres; multiple halau confirmed teaching online internationally.
- feas: ✅ camera-friendly: hand/arm storytelling gestures + hip sway are well within single fixed-camera pose tracking, moderate tempo, low injury risk.
- curr: No global public syllabus (knowledge is protected/transmitted within hālau lineages, not standardized like ISTD) — hand gestures often have specific narrative meanings tied to individual songs (mele), meaning generic 'named step' curriculum is harder to build without a genuine cultural-consultant partnership.
- needs: None physically, but there is a MEANINGFUL cultural-appropriation/authenticity risk: hula is a living, protected cultural/spiritual practice (not just choreography) — should not be added without direct halau/kumu hula partnership and cultural consultation.
- caveat: ⚠️ Recommend treating as ❌-for-now unless the founder is willing to commission content directly from a named hālau/kumu hula, given both the sacred/protected nature of the material and thinner course-supply evidence versus other candidates on this list.
- url: https://hulaaloha.org/
### Amapiano dance (South African)
- pop: Very high SOCIAL-MEDIA virality (#amapiano 73M+ TikTok views) and growing in-person class availability (London, LA, other major cities cited), but ⚠️ evidence is TikTok/social-trend-heavy rather than structured 'named syllabus' course demand — thinner as a formal curriculum candidate than as a viral-trend candidate.
- feas: ✅ camera fit is fine (moderate-tempo groove, floor-based); ⚠️ curriculum constraint — Amapiano dance is largely trend-driven and freeform/improvisational rather than built around a stable, namable step vocabulary, making a durable 'technique curriculum' (vs. a rotating trend-clip library) harder to build and keep current.
- curr: No stable named-step syllabus; content is trend-cycle based (specific viral moves change every few months) — would require an ongoing content-refresh pipeline rather than a one-time curriculum build, unlike ballroom/tap/Irish.
- needs: None.
- caveat: Recommend folding into the existing Afrobeats module as a rotating 'Amapiano trend pack' rather than building it as a separate stable curriculum line — the trend-cycle nature doesn't fit a fixed technique-track model well.
- url: https://www.tiktok.com/discover/amapiano-dance-class
### Merengue solo / Cumbia solo (Latin social solo styling)
- pop: Global — both are Latin social-dance staples taught worldwide (US Latin-dance studios, Latin America broadly, European Latin scenes); confirmed 'solo' class format exists commercially (Motion Arts Center's dedicated solo-styling class), following the same pattern as bachata-solo.
- feas: ✅ strong fit — same profile as the already-shipped bachata-solo/salsa-shines modules: simple, repetitive footwork patterns, easy pose tracking, clean beat-grid tempo lock (Merengue ~120-140 BPM one-step-per-beat; Cumbia ~90-100 BPM).
- curr: Merengue: basic marching step, hip accent, turns styling, arm styling; Cumbia: basic step, weight-transfer sway, footwork variations, styling arm/hand work. No formal global syllabus body, but content pattern directly mirrors the already-built bachata-solo module, minimizing net-new production risk.
- needs: None.
- caveat: Lowest-risk, most 'shippable' addition on this whole list given it reuses an already-validated content pattern (solo-styling extraction from partner dance) rather than requiring a new curriculum model.
- url: https://motionartscenter.com/merengue/
### Reggaeton / Perreo (solo styling)
- pop: Reggaeton is one of the most globally dominant music genres of the 2020s; perreo specifically is described as having become 'today's global dance' after early censorship — strong genre-level popularity, though dedicated 'perreo technique class' course-supply evidence found was thinner (mostly YouTube tutorials, not structured studio/syllabus programs).
- feas: ✅ camera fit is fine (hip/pelvis isolation, floor-based, similar profile to twerk/heels already in catalog); ⚠️ significant CONTENT-TONE constraint — perreo is a sexually-expressive dance style; curriculum, marketing copy, and any promotional material need careful, deliberate positioning (similar consideration as twerk, already in the approved set, so precedent exists) to avoid app-store content-policy issues.
- curr: Core techniques: hip circles/figure-8s, low squat-and-bounce ('sentadilla'), booty-pop isolation, musicality/hit-accenting to reggaeton's dembow rhythm — largely YouTube-tutorial-transmitted rather than formally syllabus-backed.
- needs: None physical; app-store content-rating/marketing caution given sexually-expressive nature (same category concern as twerk).
- caveat: Given twerk is already approved, perreo/reggaeton solo could reasonably fold into that same 'sensual/twerk-adjacent' content family rather than launching as a fully separate line — recommend confirming app-store policy posture before greenlighting, since this is now the second style in that sensitive-content bucket.
- url: https://remezcla.com/features/music/tu-pum-pum-perreo-history/


# ==== gravita-full-fitness ====

## SUMMARY
Gravita expansion mapped against a single fixed-camera, on-device MediaPipe Pose (33 landmarks) + Hands pipeline. Bottom line: barbell compounds are ✅ feasible for the big lower-body/pull lifts (squat, deadlift, hip thrust, overhead press, row) from a side/45° angle, but bench press and any supine/prone lift are ⚠️ structurally hard for a single camera (occlusion, foreshortened depth, bar path invisible from most single angles) — treat as 'partial rep-counting + setup coaching' rather than full form-grading. Dumbbell/kettlebell work is the best-fit category (open kinetic chain, upright, single implement, huge global demand) — kettlebell swing ✅, Turkish get-up ✅ but needs a genuine multi-state FSM (5-7 phases), snatch ⚠️ (fast overhead ballistic, motion blur + hand/bar occlusion at lockout). Machine exercises are correctly a near-blanket ❌/skip: the machine itself enforces the bar path, MediaPipe can't see joint angles through machine frames/pads, and there is no error mode to coach against that the machine hasn't already fixed. Core/stability and calisthenics are the strongest strategic fit for Gravita: full-body, open, single-plane-friendly, and this is where 'form coach' differentiation actually lives — most of section 4 and 5 are ✅, with clear ⚠️ flags only for movements needing depth-camera precision (ab-wheel roll-out distance, nordic-curl controlled-descent angle) or thin/small props (jump rope, ab wheel handle) that pose models don't segment. Explosive/plyometric moves are ✅ for jump squat/broad jump/box jump body mechanics but ⚠️ for anything requiring prop detection (box height, rope) since MediaPipe tracks landmarks, not objects. Library-size benchmarks: Fitbod ~1,600+ exercises (2026), Jefit 1,400+ — but both count barbell/machine/cable variants that Gravita's engine philosophy should NOT chase 1:1; the right comparison is a curated ~120-180 pose-trackable movement library organized by movement-class rules, not raw exercise count.

## RECOMMENDATIONS
- Adopt movement-CLASS feasibility rules (not per-exercise rules) so the catalog scales without bespoke state machines for every variant: (a) Open-chain, upright, single-plane-dominant, bar/limb path visible from one side/45° camera → ✅ full form coach. (b) Supine/prone/lying, or movement crosses camera's depth axis heavily (e.g., bench press vertical bar path viewed from the only non-occluded angle is nearly axial) → ⚠️ rep-count + setup/tempo coaching only, downgrade 'form-grade' claims. (c) Machine-guided (fixed cam/pulley path) → ❌ skip; machine already enforces form and frame occludes joints. (d) Requires tracking a prop/edge/small object (barbell plates for depth calibration, ab-wheel, jump rope, plyo box height) beyond body landmarks → ⚠️ flag as 'R&D: needs object/edge detection', not pure-pose feasible today.
- Build Turkish get-up and similar multi-phase lifts (sissy squat, dragon flag, skin-the-cat, elbow lever transitions) as explicit finite-state-machines reusing the existing 'pose state-machine' engine module — these are Gravita's best differentiation vs. any competitor because rule-based phase detection is exactly what on-device deterministic engines are good at and video-only apps (Fitbod/Jefit) don't attempt form-grading at all, only logging.
- Prioritize wave 1 by demand+feasibility overlap: (1) DB/KB library (curls, presses, rows, RDL, goblet squat, lunges, swings) — high global demand, high feasibility. (2) Core/stability (dead bug, bird dog, side plank, hollow hold, hanging leg raise) — high feasibility, strong 'form coach' story, moderate demand. (3) Barbell squat/deadlift/OHP/row/hip-thrust (side-view) — highest demand (StrengthLevel/NSCA-anchored) but fewer users have a barbell+plates at home/camera setup vs. DB/KB or bodyweight, so ship after the calisthenics/DB wave for adoption reasons, not feasibility reasons.
- Explicitly de-prioritize/skip: all major machine exercises (leg press, lat pulldown, cable stack, Smith machine, leg extension/curl machine, chest press machine) — confirm and publish the 'machine = skip' rule so support/marketing don't promise coverage there.
- Flag bench press, overhead barbell snatch, and jump-rope as named exceptions needing either a second camera angle, a depth sensor, or explicit scope-narrowing (e.g., bench press: only count reps + bar-path-visible warm-up sets from a foot-of-bench low angle; can't grade elbow flare/wrist alignment reliably single-cam).
- Before building the box-jump/broad-jump modules, decide product scope: MediaPipe Pose gives excellent jump-height/landing-mechanics/knee-valgus feedback without ever detecting the box — so ship 'jump squat, broad jump, jump squat depth/landing coaching' as pure body-mechanics products and treat 'box jump box-clearance detection' as a separate, lower-priority object-detection R&D item, not bundled into the same release.

## RISKS
- Bench press is the single most requested 'big 3' lift and is also the worst single-camera use case (supine, bar path largely axial to any workable side camera, spotter/rack often occludes). Overpromising 'Gravita coaches your bench press' risks a visible, embarrassing quality gap versus the squat/deadlift modules — needs explicit UX framing (rep counter + tempo, not form grade) or a stated ⚠️ limitation in marketing.
- StrengthLevel and NSCA/ACSM/ACE evidence supports demand for the 'big lifts' but that demand is concentrated among barbell-owning, gym-going or home-rack users — a meaningfully smaller addressable slice than the bodyweight/DB/KB audience; conflating 'most tracked lift on StrengthLevel' with 'most useful Gravita feature' could misallocate engineering effort.
- Deep flexion/rotation moves (sissy squat, nordic curl, ATG-style deep squat) push MediaPipe Pose's known weak spots: self-occlusion of the trailing leg, ankle/knee landmark jitter at extreme flexion, and single-camera depth ambiguity for how far the torso leans — these need on-device validation against real footage before a ✅ verdict is finalized, not just biomechanical reasoning.
- Exercise-count benchmarking (Fitbod ~1,600+, Jefit ~1,400+) is drawn from marketing/blog copy, not an audited exercise-by-exercise list — treat as directional scale evidence only, and note neither app does biomechanical form-grading, so a raw count comparison is apples-to-oranges against Gravita's rule-engine catalog.
- Kettlebell snatch and swing at pace can produce fast joint velocity that stresses MediaPipe's per-frame landmark smoothing (motion blur / frame-to-frame landmark snapping), especially at lockout overhead — flagged ⚠️ pending an actual frame-rate/blur test on a fixed phone camera, not confirmed from spec sheets alone.

## ITEMS
### Barbell Back/Front Squat
- pop: StrengthLevel squat standards built on 793,825 powerlifting totals (2015-2026 dataset, updated 2026-07-20); one of the 'Big 3' in every NSCA/ACSM CPT curriculum
- feas: ✅ — side/45° camera clearly shows hip-crease-below-knee depth, knee valgus, torso lean, bar path (visually, not literally tracked); this is the canonical single-camera lift
- curr: NSCA/ACSM/ACE 1RM & technique standards
- needs: None beyond existing pose state-machine module
- caveat: Depth judgment (hip crease vs knee) needs reliable hip/knee landmark z-estimation single-cam; validate against side-by-side goniometer footage
- url: https://strengthlevel.com/strength-standards/squat
### Barbell Deadlift (conventional/sumo)
- pop: Second most-tracked StrengthLevel lift; NSCA technique standards for hip-hinge patterning are explicit
- feas: ✅ — side view is the standard coaching angle in-person too; spine curvature and hip/knee sequencing are pose-trackable
- curr: NSCA PTQ 10.2 fundamental resistance training movement patterns
- needs: Rounded-back detection needs shoulder-hip-lumbar landmark angle rules, already analogous to RhythmEngine-style rule thresholds
- caveat: Sumo stance widens frontal-plane motion which a single side camera won't fully capture — may need stance-aware camera-placement guidance in-app
- url: https://strengthlevel.com/strength-standards/deadlift
### Barbell Bench Press
- pop: NSCA/ACSM/ACE treat as canonical upper-body 1RM test lift; StrengthLevel standard #2 by search volume
- feas: ⚠️ — lying position means the working joints (shoulder/elbow/wrist) move mostly along the camera's depth axis from any side angle; a camera at the foot of the bench sees the bar path but not elbow flare; rack/spotter often occludes upper body. Best framed as rep-count + tempo/pace only, not full form grade
- curr: NSCA CPT bench press technique + metronome-paced 1RM testing protocol
- needs: Needs either an overhead/foot-of-bench mount recommendation or explicit scope reduction
- caveat: Genuine constraint, not just a UX choice — occlusion is physical (torso between camera and bar at most home-gym angles)
- url: https://en.wikipedia.org/wiki/Bench_press
### Barbell Overhead Press
- pop: Included among StrengthLevel's core 4 standards alongside squat/bench/deadlift
- feas: ✅ — standing, front or 45° camera shows bar path and lumbar arch/rib-flare compensation clearly
- curr: NSCA/ACSM standing press technique guidance
- needs: None
- caveat: Overhead lockout near top of frame — needs camera-distance guidance so wrists don't clip frame edge
- url: https://strengthlevel.com/strength-standards
### Barbell Row (bent-over)
- pop: Consistently in NSCA fundamental movement-pattern teaching progressions
- feas: ✅ — side view captures torso-angle maintenance (the #1 form fault: standing up during the pull) very reliably
- curr: ?
- needs: None
- caveat: Bar/plates occasionally cross in front of shins in narrow frames — minor
- url: https://www.nsca.com/contentassets/3d09f06f0b4c4f6fbd8cc382ed1f3d4a/ptq-10.2.1-progressive-strategies-for-teaching-fundamental-resistance-training-movement-patterns.pdf
### Hip Thrust
- pop: One of the most-searched glute exercises globally; standard in ACE/NSCA glute-training guidance
- feas: ✅ — side view is the only coaching angle used in person too; hip extension angle, lockout, and lumbar over-extension are all clearly visible pose signals
- curr: ?
- needs: None
- caveat: Bench itself may partially occlude lower legs depending on camera height — minor, tune camera angle guidance
- url: https://strengthlevel.com/strength-standards
### Dumbbell/Barbell Curl
- pop: StrengthLevel dumbbell curl / barbell curl among its core tracked standards
- feas: ✅ — simple single-joint, front-view friendly, elbow-drift and swing/momentum ('body English') are exactly what pose rule-engines catch well
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Lateral Raise
- pop: Very high — a top search term in gym exercise content globally
- feas: ✅ — front view captures arm-path plane and shoulder-shrug compensation clearly
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Romanian Deadlift (DB/BB)
- pop: Staple in nearly every posterior-chain program worldwide
- feas: ✅ — same side-view hinge-tracking logic as deadlift, arguably easier since load is lighter and tempo slower
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Goblet Squat
- pop: Standard teaching progression referenced across NSCA/ACE materials
- feas: ✅ — front-loaded, upright torso, very pose-friendly; ideal onboarding movement for Gravita's squat state machine
- curr: ?
- needs: None
- caveat: None
- url: https://www.nsca.com/contentassets/3d09f06f0b4c4f6fbd8cc382ed1f3d4a/ptq-10.2.1-progressive-strategies-for-teaching-fundamental-resistance-training-movement-patterns.pdf
### Walking/Reverse/Static Lunges
- pop: Extremely common in nearly every lower-body program globally
- feas: ✅ — side view captures front-knee tracking-over-toe and torso lean well; front view better for hip drop/knee valgus
- curr: ?
- needs: Camera-angle guidance differs from squat (may want slight rotation for lunge direction)
- caveat: Walking lunges cross the frame — needs a wider FOV or treadmill-style in-place variant guidance
- url: https://strengthlevel.com/strength-standards
### DB/BB Shoulder Press (standing/seated)
- pop: Extremely common accessory/primary press
- feas: ✅ — same logic as barbell OHP
- curr: ?
- needs: None
- caveat: None
- url: https://strengthlevel.com/strength-standards
### One-Arm DB Row
- pop: Staple accessory lift worldwide
- feas: ✅ — side view, torso stays fixed on bench which actually REDUCES occlusion vs. bent-over barbell row
- curr: ?
- needs: None
- caveat: None
- url: https://strengthlevel.com/strength-standards
### Kettlebell Swing (Russian/American)
- pop: Core movement of kettlebell training globally, referenced in ACE/NSCA kettlebell-specific continuing-ed content
- feas: ✅ — side view captures the hip-hinge/hip-snap pattern extremely well; this is arguably a better single-camera use case than barbell deadlift because tempo is faster and repetitive, giving RhythmEngine-style beat-grid timing analysis a natural fit (hip-snap cadence)
- curr: ?
- needs: Could reuse RhythmEngine (beat-grid) for swing cadence/tempo consistency scoring — good cross-module synergy
- caveat: Fast eccentric-to-concentric transition at the 'hike pass' position may stress per-frame landmark smoothing — validate on real footage
- url: https://strengthlevel.com/strength-standards
### Turkish Get-Up
- pop: Widely programmed in functional-strength and kettlebell-certification curricula (StrongFirt/RKC); moderate-high global demand, not as universal as squat/curl
- feas: ✅ but ⚠️ engineering-heavy — requires a genuine 5-7 state finite-state-machine (not a simple rep counter); each phase transition has a distinct pose signature (supine→elbow-support→hand-support→bridge→kneeling→lunge→stand) that IS individually pose-trackable from one side-on camera, but building/tuning the FSM is nontrivial dev effort
- curr: StrongFirst/RKC kettlebell technique standards (industry, not NSCA/ACSM)
- needs: Reuse + extend existing pose state-machine module; this is the flagship 'why Gravita and not a video app' feature
- caveat: Camera framing must capture full floor-to-standing range (near/far z-distance changes drastically across phases) — needs a 'step back further' onboarding prompt
- url: https://strengthlevel.com/strength-standards
### Kettlebell Snatch
- pop: Moderate — programmed in KB-sport/CrossFit, not mainstream general-fitness
- feas: ⚠️ — high bar-speed at the top (overhead lockout) risks motion blur / landmark snapping on typical phone frame rates (30fps); the hand transition ('the flip') happens fast and close to the head, a self-occlusion risk zone
- curr: ?
- needs: Needs real on-device frame-rate testing before committing to a ✅ verdict
- caveat: Flagged explicitly as thin-evidence pending device testing, not a settled verdict
- url: https://strengthlevel.com/strength-standards
### Machine exercises (leg press, lat pulldown, cable stack, Smith machine, leg extension/curl, pec deck, chest press machine)
- pop: High usage in commercial gyms but zero differentiation value for a form-coaching product
- feas: ❌ — two independent reasons: (1) the machine mechanically constrains the bar/pad path, so there is very little 'form' left to coach that the machine hasn't already enforced; (2) the machine frame, seat pads, and shrouds physically occlude the joints a single camera needs to see (hip/knee on leg press, shoulder/elbow on chest press). Recommend explicit skip, not silent gap.
- curr: N/A
- needs: None — deliberately out of scope
- caveat: If founder wants ANY machine coverage, seated cable row and lat pulldown are the least-bad candidates (open front view, less shrouding) but still low value-add over rep counting
- url: https://fitbod.me/about-fitbod-exercises/
### Dead Bug
- pop: Extremely common in core/rehab programming, high demand via physical-therapy-adjacent content
- feas: ✅ — performed supine but limbs move in a wide, camera-facing plane (overhead or side view) unlike bench press's axial bar path; limb symmetry and lower-back-flat-to-floor cues are trackable
- curr: ?
- needs: Needs overhead or 45°-elevated camera mount guidance since it's a floor exercise
- caveat: Camera placement differs from standing-exercise default — app needs per-exercise camera-angle prompts
- url: https://www.nsca.com/education/articles/kinetic-select/the-big-3-exercises-for-core-training/
### Bird Dog
- pop: Extremely common, near-universal in core-stability programming
- feas: ✅ — side view captures spine-neutrality and limb-height symmetry very well; classic pose-tracking use case
- curr: ?
- needs: None
- caveat: None significant
- url: https://www.nsca.com/education/articles/kinetic-select/the-big-3-exercises-for-core-training/
### Hollow Hold / Hollow Body Hold
- pop: High within calisthenics/gymnastics-strength communities, growing mainstream via 'gymnastics strength training' trend
- feas: ✅ — static hold, side view, lumbar-to-floor contact and leg/shoulder angle are clean pose signals; ideal for a simple isometric-hold timer + form-break detector
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Side Plank
- pop: Extremely common globally
- feas: ✅ — side view is literally the exercise's natural camera angle; hip-sag detection is a textbook single-camera pose problem
- curr: ?
- needs: None
- caveat: None
- url: https://www.nsca.com/education/articles/kinetic-select/the-big-3-exercises-for-core-training/
### Pallof Press (banded)
- pop: Common in core/rehab programming, moderate mainstream demand
- feas: ⚠️ — the core anti-rotation cue (torso staying square while resisting band pull) IS pose-trackable, but the band itself is a thin, low-contrast object MediaPipe won't segment/anchor-detect, so the app can coach torso stability but can't verify band tension/anchor point or resistance level
- curr: ?
- needs: Requires a fixed anchor point off-screen; app can't verify this setup automatically
- caveat: Verdict is for the BODY mechanics only — equipment-verification is out of scope
- url: https://www.nsca.com/education/articles/kinetic-select/the-big-3-exercises-for-core-training/
### Hanging Leg Raise / Toes-to-Bar
- pop: Very common in CrossFit/calisthenics, moderate-high global demand
- feas: ✅ — side view of a hanging body against a bar is a clean, high-contrast pose scenario (similar to pull-up tracking which is presumably already solved for a fixed-camera coaching app); hip flexion angle and kipping-vs-strict swing are trackable
- curr: ?
- needs: None beyond existing hanging-movement tracking (if pull-ups already supported)
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Ab Wheel Rollout
- pop: High within strength-training and core-focused communities
- feas: ⚠️ — torso/hip angle and lumbar-sag are pose-trackable, but rollout DISTANCE (a key progression/difficulty metric) requires tracking the small wheel itself, which is a thin low-profile object outside MediaPipe Pose's landmark set — flag as partial: form-fault detection ✅, distance/ROM metric ❌ without added object tracking
- curr: ?
- needs: Object-tracking R&D item if rollout-distance metric is wanted
- caveat: Distinguish 'we can tell you your back is sagging' (yes) from 'we can measure how far you rolled out' (no, not with pose alone)
- url: https://www.nsca.com/education/articles/kinetic-select/the-big-3-exercises-for-core-training/
### Archer Push-Up / Archer Pull-Up
- pop: High within calisthenics community (large, active global online community — reddit r/bodyweightfitness, FitnessFAQs-style channels)
- feas: ✅ — front or 45° view captures the lateral weight-shift and extended-arm lockout clearly
- curr: ?
- needs: None
- caveat: Popularity is strong within calisthenics niche but should not be conflated with StrengthLevel-scale mainstream demand — flagged as niche-but-real
- url: https://strengthlevel.com/strength-standards
### Typewriter Push-Up / Typewriter Pull-Up
- pop: Moderate within calisthenics community
- feas: ✅ — same reasoning as archer variants; lateral torso translation is clearly visible front-on
- curr: ?
- needs: None
- caveat: Niche popularity — calisthenics community is large globally but smaller than mainstream gym-goer base
- url: https://strengthlevel.com/strength-standards
### Pseudo Planche Push-Up
- pop: High within calisthenics progression content (huge YouTube/Instagram calisthenics-coaching niche)
- feas: ✅ — side view captures shoulder-over-hand lean angle cleanly, a textbook single-joint-angle rule
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### One-Arm Push-Up Progressions (archer→lever→full OAP)
- pop: Extremely high aspirational search demand within fitness content (a top 'bucket list' bodyweight goal)
- feas: ✅ — front-on camera tracks the single working arm's elbow angle and torso rotation/twist (a common fault) well
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Commando Pull-Up
- pop: Moderate within calisthenics community
- feas: ✅ — same hanging-body tracking logic as strict pull-ups/toes-to-bar
- curr: ?
- needs: None
- caveat: None
- url: https://strengthlevel.com/strength-standards
### Dragon Flag
- pop: High recognition/aspirational demand (famous via pop culture), moderate-high within calisthenics community
- feas: ✅ — side view, the whole body forms a visible rigid lever, exactly the kind of joint-angle-over-time signal pose rule-engines score well
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Nordic Hamstring Curl
- pop: Growing rapidly — strong sports-science/injury-prevention evidence base, increasingly mainstream in strength content
- feas: ✅ — side view captures the controlled knee-to-torso lowering angle and any 'break' at the hips (the classic form fault) very clearly; excellent candidate for tempo/eccentric-control coaching (ties into RhythmEngine-style tempo scoring)
- curr: Sports-science hamstring-injury-prevention literature (soccer/sprint research)
- needs: Requires a foot-anchor (partner, bar, or nordic bench) off-camera — app can coach body only
- caveat: Popularity evidence here is stronger from sports-science/S&C literature than from raw consumer search volume — flagged as 'professionally-recommended' rather than 'mass-market popular,' matching the founder's own dual criterion
- url: https://www.nsca.com/education/articles/
### Sissy Squat
- pop: High current demand (visibly trending in fitness content 2024-2026)
- feas: ⚠️ — side view is the right angle, but the deep knee flexion + backward lean pushes MediaPipe Pose toward known weak spots (ankle/knee landmark jitter at extreme flexion, partial self-occlusion of the trailing leg) — needs on-device validation before a full ✅
- curr: ?
- needs: On-device accuracy validation at extreme knee flexion
- caveat: Verdict downgraded from the founder's implicit ✅ expectation specifically because of pose-model edge-case behavior, not lack of demand
- url: https://strengthlevel.com/strength-standards
### Shrimp Squat
- pop: High within calisthenics/functional-strength content (common benchmark movement)
- feas: ⚠️ — similar to sissy squat: deep single-leg flexion plus a held rear foot creates self-occlusion and balance-wobble that stresses landmark stability; side-45° view helps but needs validation
- curr: ?
- needs: On-device validation at extreme unilateral flexion
- caveat: Flagged, not confirmed ❌ — likely resolvable with a slightly elevated camera angle, needs testing
- url: https://strengthlevel.com/strength-standards
### Elbow Lever
- pop: Moderate within calisthenics/gymnastics-strength niche
- feas: ✅ — static hold, side view, body-line angle from ground is a clean single-frame-repeatable pose metric
- curr: ?
- needs: None
- caveat: Niche popularity, not mainstream
- url: https://strengthlevel.com/strength-standards
### Skin the Cat
- pop: Moderate within calisthenics/gymnastics-strength niche
- feas: ✅ but state-machine-required — a hanging, rotating multi-phase movement (like Turkish get-up's aerial cousin); side view tracks the rotation arc well, but needs phase-based FSM logic rather than a simple rep counter
- curr: ?
- needs: Reuse pose state-machine module (phase-based, similar engineering pattern to Turkish get-up)
- caveat: Requires rings or bar equipment most home users won't have — feasibility ✅ but addressable-audience is small
- url: https://strengthlevel.com/strength-standards
### Front Lever Rows
- pop: High aspirational demand within calisthenics community
- feas: ✅ — side view, rigid horizontal body-line plus arm-pull angle are both clean pose signals
- curr: ?
- needs: None
- caveat: Requires bar/rings — addressable audience narrower than bodyweight-floor exercises
- url: https://strengthlevel.com/strength-standards
### Straddle Planche Press
- pop: Niche — elite calisthenics athletes and aspirational content, not mass-market
- feas: ⚠️ — extremely low-to-ground, near-horizontal body position with hands close together can create self-occlusion of the legs/hips depending on camera height; likely needs a low, close camera placement not typical of Gravita's default standing-height mount
- curr: ?
- needs: Non-standard low camera placement
- caveat: Low priority: niche audience + camera-placement friction; good 'flagship skill' marketing move but poor ROI as an early build target
- url: https://strengthlevel.com/strength-standards
### Wall Walk
- pop: Common in CrossFit programming
- feas: ✅ — side view against a wall is high-contrast and clean; inverted transition is trackable throughout since the whole body stays in frame profile
- curr: ?
- needs: Needs a wall in frame — camera-placement guidance
- caveat: None significant beyond framing
- url: https://strengthlevel.com/strength-standards
### Crab Walk
- pop: Common in warm-up/conditioning circuits, moderate demand
- feas: ✅ — side view tracks hip-height maintenance and limb coordination well
- curr: ?
- needs: Movement crosses the frame — needs wide FOV or in-place variant
- caveat: Traveling movement is a camera-framing challenge shared with walking lunges
- url: https://strengthlevel.com/strength-standards
### Bear Crawl
- pop: Very common globally in conditioning programming
- feas: ✅ — side view, same framing caveat as crab walk (traveling movement)
- curr: ?
- needs: Wide FOV or in-place variant guidance
- caveat: Same traveling-movement framing issue
- url: https://strengthlevel.com/strength-standards
### Clap Push-Up
- pop: Common in athletic/explosive-training programming
- feas: ✅ — front view captures airtime/elbow-lockout-at-launch and landing control; fast but well within phone frame-rate tolerance for a single planar movement
- curr: ?
- needs: None
- caveat: None significant
- url: https://strengthlevel.com/strength-standards
### Broad Jump
- pop: High recognition via combine testing and athletic programming
- feas: ✅ for landing mechanics/takeoff form; ⚠️ for the DISTANCE metric specifically, since accurate distance measurement from a single fixed camera without a calibrated reference plane/marker is error-prone (perspective distortion)
- curr: ?
- needs: Would need a calibration step (known-length floor marker) for accurate distance — form-only mode needs no such calibration
- caveat: Split verdict explicitly: mechanics ✅, precise distance measurement ⚠️
- url: https://strengthlevel.com/strength-standards
### Box Jump
- pop: Extremely common in CrossFit/athletic programming globally
- feas: ⚠️ — landing mechanics (soft-landing, knee alignment) are trackable, but the BOX itself is an external prop MediaPipe Pose does not detect; app can't verify box height, foot placement on the box edge, or (critically) safe landing on top of the box vs. a near-miss — this is a genuine object-detection gap, and also a safety-relevant one (giving false-confidence feedback on a fall-risk movement)
- curr: ?
- needs: Object/edge detection R&D item; flagged as the planned bar/edge-detection module in your roadmap — box jump is a natural first use case for that R&D line
- caveat: Safety-relevant gap — recommend NOT shipping full 'form-graded' box jump until edge-detection R&D lands, to avoid false-confidence on a fall-risk movement
- url: https://strengthlevel.com/strength-standards
### Jump Squat
- pop: Extremely common in bodyweight/HIIT conditioning content
- feas: ✅ — no prop dependency (unlike box jump), so this is a clean pose-only plyometric use case: depth, jump height (relative, via hip-landmark trajectory), and soft-landing knee tracking are all trackable
- curr: ?
- needs: None
- caveat: Absolute jump-height-in-cm would need calibration like broad jump; relative/consistency scoring needs none
- url: https://strengthlevel.com/strength-standards
### Jump Rope
- pop: Extremely high global demand (one of the most common cardio tools recommended by ACE/ACSM for conditioning)
- feas: ⚠️/❌ for rope-specific coaching — the rope itself is a thin, fast-moving, low-contrast object that MediaPipe Pose's 33 body landmarks do not track at all; jump TIMING/cadence and landing softness ARE trackable from body pose alone (ties well to RhythmEngine beat-grid), but 'did the rope pass under your feet cleanly' / 'did you trip' is invisible to a pose-only pipeline
- curr: ACE/ACSM cardio-conditioning recommendations
- needs: Would need dedicated thin-object tracking (different problem class from pose) — likely out of scope for the current engine architecture
- caveat: Recommend shipping as a body-only cadence/rhythm trainer (reusing RhythmEngine) explicitly WITHOUT claiming rope-fault detection, rather than skipping the whole exercise — good RhythmEngine synergy makes partial coverage worthwhile despite the rope-tracking gap
- url: https://strengthlevel.com/strength-standards
