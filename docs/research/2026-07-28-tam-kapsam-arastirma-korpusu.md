

# ==== jablab-scope ====

## SUMMARY
Full-scope solo-combat catalog for JabLab: 10 in-scope disciplines (Boxing baseline, Kickboxing, Muay Thai, Karate, Taekwondo, MMA-striking-subset, Wing Chun, Krav Maga-combatives-subset, Fitness/Cardio Kickboxing, Tai Chi) plus 2 explicitly evaluated-and-excluded categories (grappling arts: BJJ/Wrestling/Judo; weapons arts: Kali/Kendo/HEMA). Every item has a real popularity/curriculum URL. Two hard technical questions are answered directly: (1) high kicks & spins ARE measurably worse than punches for pose fidelity — a published SSRN Taekwondo dataset paper exists specifically because motion blur/self-occlusion on kicks challenges standard pose models, so kick-heavy arts (Taekwondo, Kickboxing) need frame-confidence smoothing and honest in-app accuracy caveats; (2) kata/poomsae/taolu sequence scoring IS structurally closer to Choreia's DTW-based long-sequence alignment than to Boxing's discrete event detection — confirmed by a published Karate-kata deep-learning scoring paper and an iKarate F-DTW system (91% accuracy), and Tai Chi is flagged as the easiest possible proving ground for that same DTW engine since it has zero motion blur.

## RECOMMENDATIONS
- Expansion order by (popularity × feasibility × curriculum-clarity), highest first: (1) Kickboxing — near-zero new engineering, reuses V1 punch engine, add kick classifier, huge fitness-market pull; (2) Tai Chi — largest practitioner base of any item, zero motion-blur problem, and the ideal low-risk place to first build the DTW/sequence-scoring engine before tackling kata/poomsae's speed; (3) Karate kihon+kata — massive practitioner base (50-100M) and a published deep-learning kata-scoring precedent to build from directly; (4) Muay Thai — fast-growing global market, mostly reuses kick/punch engines plus new elbow/knee classifiers, clinch explicitly simulated-only; (5) Fitness/Cardio Kickboxing — ship as a UI mode on top of items 1+4, not a separate pipeline; (6) Taekwondo poomsae+kicks — largest single-discipline practitioner claim but the hardest kick-fidelity problem in the catalog (ship with visible in-app accuracy caveats on jump/spin kicks, Wave 2/3 not Wave 1); (7) MMA-striking — repackage items 1+3+4 as a combo mode once each exists standalone; (8) Krav Maga combatives — ship narrowly-scoped and clearly labeled to avoid overpromising self-defense capability; (9) Wing Chun forms — real but thin/fragmented popularity evidence, treat as an enthusiast Wave 3+ addition.
- Build the DTW/long-sequence scoring engine ONCE as a shared module (kata/poomsae/taolu/tai-chi-form scorer) rather than per-discipline — it is required by Karate, Taekwondo, Wing Chun, and Tai Chi alike, and is architecturally the same class of problem as Choreia's dance-sequence scoring.
- Ship every kick-heavy discipline (Kickboxing, Muay Thai, Taekwondo, MMA-striking) with an explicit, user-visible accuracy caveat on high/spinning/jumping techniques rather than silently scoring them with degraded confidence — this is a defensible engineering constraint, not a hidden limitation.
- Do not market the Krav Maga or Wing Chun modules as complete versions of those arts — label them 'Combatives Conditioning' / 'Solo Forms' respectively, since their most defining content (live defenses against a resisting attacker; dummy-contact timing) is not solo-camera-trainable.
- Explicitly publish the BJJ/Wrestling/Judo and Weapons-arts exclusions in-app or in marketing copy (a short 'what JabLab does not teach, and why' note) — this protects the founder's honesty commitment and preempts obvious user questions/complaints better than silence would.

## RISKS
- Popularity figures for several disciplines (Karate, Taekwondo, Tai Chi, Krav Maga) are federation self-reports or secondary-source estimates that disagree by 2-4x across sources — every number in this catalog should be presented as a range with its source, never as a single precise figure, in any founder-facing or marketing material.
- Kick-technique pose fidelity (especially jumping/spinning kicks in Taekwondo, head-height roundhouse in Muay Thai/Kickboxing) is a genuinely unsolved engineering risk, not just a UX caveat — before committing Taekwondo/Muay Thai to a wave, run an internal pose-accuracy pilot against the cited SSRN Taekwondo dataset or equivalent footage to quantify real confidence degradation before promising users a score.
- Krav Maga and Wing Chun both have fragmented/no unified governing federation, meaning there is no authoritative curriculum standard to certify against — any in-app belt/level claims for these two disciplines carry more curriculum-legitimacy risk than the federation-standardized arts (Karate/Taekwondo/Muay Thai) and should be reviewed for liability/marketing-accuracy before launch.
- Excluding BJJ/Wrestling/Judo and weapons arts removes some of the single most globally popular combat categories from JabLab's total addressable market — confirm with the founder that 'full scope' is being interpreted as 'full scope of what is physically solo-trainable' rather than 'full scope of all popular combat sports,' since the latter is not achievable on this engine at all.

## ITEMS
### Boxing (V1 baseline — done)
- pop: 8.4M Americans trained boxing/MMA for fitness in 2023 (Statista/Gymdesk); global boxing gym base in the tens of millions.
- feas: ✅ feasible — single-camera event detection on punches already validated in V1.
- curr: Numbered punches (1-jab,2-cross,3-lead hook,4-rear hook,5-lead uppercut,6-rear uppercut), stance (orthodox/southpaw), pad/bag combo numbering system, no belts — gym 'levels' (beginner/intermediate/advanced/competitive).
- needs: None beyond existing V1 engine.
- caveat: None — shipped baseline.
- url: https://www.statista.com/statistics/191905/participants-in-boxing-in-the-us-since-2006/
### Kickboxing (Full-Contact / American Kickboxing)
- pop: Cardio kickboxing had the largest 1-year participation growth of any tracked fitness activity in the US, +8.5% (SFIA 2023 Tracking the Fitness Movement Report).
- feas: ⚠️ feasible-with-constraints — punches ✅; roundhouse/head kicks introduce motion blur and self-occlusion of the chambered leg at speed, requiring a wider FOV / floor clearance behind the phone and lower confidence thresholds during the kick apex frame.
- curr: WAKO rule divisions (light-contact, full-contact, low-kick); combo numbering extends boxing's (e.g. '1-2-3 roundhouse'); no universal belt system — many commercial gyms use color-cord level bands (white→black) borrowed from karate lineage.
- needs: Kick-classifier (angle/height/target zone) layered on top of the existing punch classifier; chambering-knee detection to disambiguate front/round/side kick before impact.
- caveat: No single global governing body — WAKO (Olympic-recognized since 2021 provisional) is the closest to a unified ruleset; participation stats are largely US/EU commercial-gym derived
- url: https://sfia.org/resources/sfias-tracking-the-fitness-movement-report-sees-increase-in-number-of-americans-working-out/
### Muay Thai (Thai Boxing)
- pop: IFMA (Olympic-recognized international federation) has 128 member national federations across 5 continental federations; Europe alone ~22.4% of a fast-growing (7.6% CAGR) commercial Muay Thai market.
- feas: ⚠️ feasible-with-constraints — punches/kicks/teeps solo-trainable ✅; elbows are short-range and generally low-blur (✅); knees from clinch range require a mock/imagined opponent distance (feasible as shadow drill, ⚠️ no real contact feedback); actual clinch work (2-person grip fighting) is ❌ not feas
- curr: No universal belt system; Thai gyms use informal skill tiers + Kru (teacher) approval; WMC/IFMA amateur scoring criteria (balance, power, technique); Ram Muay/Wai Kru pre-fight ritual sequence (a scoreable choreographed solo form, DTW-friendly); core
- needs: Elbow-strike classifier (short-radius, high-angular-velocity distinct from punch/hook); knee-strike classifier from standing/simulated-clinch posture; teep (push-kick) as a distinct kick type from roundhouse.
- caveat: ?
- url: https://muaythai.sport/
### Karate (Kihon + Kata)
- pop: WKF states >100M practitioners/fans worldwide across 201 member countries; even the more conservative UWKF estimate is 50M practitioners (https://www.wkf.net/news-center/article/!/2630/karate-the-great-greatest-absence-o
- feas: ⚠️ feasible-with-constraints — kihon line-drills (front camera, in-place) ✅ fully; full kata performed with embusen (floor pattern/directional movement) requires the performer to move toward/away from and sideways to a single fixed phone camera, causing scale changes and occasional off-axis limb for
- curr: Kyu/Dan belt ladder (10th–1st kyu → 1st–10th dan, color belts white→brown→black); named kata syllabus per style (Shotokan: Heian 1–5, Tekki, Bassai Dai, Kanku Dai, Jion, Empi...; WKF Kata List ~102 recognized kata); embusen (floor diagram) scoring; k
- needs: Long-sequence scoring engine (DTW/temporal-alignment against a reference performance, not per-event classification) — same technical family Choreia already needs for dance; embusen/floor-pattern tracking (relative displacement across the kata, not ju
- caveat: WKF's '100M' figure is a federation self-report, not an independent census — treat as directional, not precise; independent estimates range 50–100M.
- url: https://www.researchgate.net/publication/395850769_Karate_Kata_Scoring_and_Performance_Evaluation_Using_Video_Analysis_and_Deep_Learning
### Taekwondo (Poomsae + Kicking)
- pop: World Taekwondo has ~208–213 member national associations; oft-cited estimate ~80–100M practitioners worldwide (https://gitnux.org/taekwondo-statistics/, cross-checked against https://www.fightmatrix.com/2025/06/09/explo
- feas: ⚠️ feasible-with-constraints — this is the field's own admitted hard case: the cited SSRN dataset paper states explicitly that 'Taekwondo's high-speed kicks introduce motion blur, self-occlusion, and large joint excursions that challenge models trained on everyday actions,' which is why the research
- curr: WT Kukkiwon rank ladder: 10th–1st geup (colored belts) → 1st–9th dan (black belt); poomsae syllabus: 8 Taegeuk forms (colored belt) + Koryo, Keumgang, Taebaek, Pyongwon, Sipjin, Jitae, Cheonkwon, Hansu, Ilyeo (black-belt Yudanja forms); kick taxonomy
- needs: Same DTW/sequence-scoring engine as Karate kata (poomsae is structurally identical: fixed embusen + timed technique sequence); high-kick classifier tolerant of partial-frame blur (confidence-decay smoothing across frames rather than single-frame clas
- caveat: Kick fidelity for advanced (spin/jump) techniques is the single biggest open technical risk in the whole JabLab scope — should be Wave 2/3, not Wave 1, and shipped with an honest i
- url: https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5436562
### MMA Striking (solo striking subset only)
- pop: MMA gym sign-ups reported +192% YoY in early 2025 across 30 gyms in US/EU/AU/NZ (MMA.inc via Fight Matrix); UFC 324 (early 2026) averaged 4.6M viewers on Paramount+, among UFC's strongest numbers ever.
- feas: ✅ feasible for the striking subset only (it is literally the union of Boxing+Kickboxing+Muay Thai's already-evaluated techniques) — ❌ not feasible for the sport's other half: wrestling takedowns and BJJ ground grappling require a resisting partner and often ground-level camera occlusion, so they are
- curr: No belt system in most MMA gyms (skill classes: beginner/intermediate/advanced, sometimes amateur fight-record tiers); training structured around 'phases' (striking, clinch [excluded], ground [excluded]) — JabLab's MMA mode should be marketed explici
- needs: None beyond the union of Boxing/Kickboxing/Muay Thai engines already scoped.
- caveat: This is a repackaging/combo mode, not a new technical build — should ship after Boxing+Kickboxing+Muay Thai are individually complete, as a 'style-mixing' free-spar drill mode.
- url: https://www.fightmatrix.com/2025/06/09/exploring-the-global-growth-of-mma/
### Wing Chun (Kung Fu — solo forms subset)
- pop: No single global census exists (fragmented lineage system, no unified federation) — popularity evidence is indirect: enduring global commercial gym presence across Europe/N.America/Asia and sustained course/YouTube deman
- feas: ✅ feasible for Siu Nim Tao (performed almost entirely stationary, hands/arms only — ideal pose-camera subject) — ⚠️ feasible-with-constraints for Chum Kiu/Biu Jee (add stepping/turning, similar embusen-tracking need as karate kata) — ❌ not feasible for the wooden-dummy form as literally practiced (r
- curr: No belt/kyu system in most traditional lineages (some modern commercial schools added sash-color ladders); 3 core solo forms in sequence (Siu Nim Tao → Chum Kiu → Biu Jee) representing beginner→advanced structure; wooden dummy form as capstone (teach
- needs: Same kata/poomsae-style DTW sequence engine, but must handle much smaller/subtler joint movements (Wing Chun emphasizes economy of motion, centerline control) — needs finer hand/wrist/elbow angle resolution than the kicking arts.
- caveat: Weakest popularity evidence of any item in this catalog — no unified federation or membership count exists; include but flag as a 'niche-enthusiast, thin-data' Wave 3+ item, not a 
- url: https://ctwingchun.com/2024/11/25/wing-chun-kung-fus-mook-yan-jong-form-wooden-dummy-form-training-review-with-commentary/
### Krav Maga (solo drilling subset)
- pop: Fragmented across organizations: Krav Maga Global >40,000 students/instructors across 70 countries; IKMF active in >80 countries; FEKM (Europe) ~18,000 practitioners across 12 countries — no single unified census exists.
- feas: ⚠️ feasible-with-constraints — striking combinations (palm strikes, hammerfists, elbows, knees, kicks to low/mid targets) thrown at an imagined attacker ✅ solo-trainable; ❌ not feasible for the discipline's signature content: defenses against actual grabs, chokes, and weapon-disarms, which require a
- curr: Krav Maga Global (KMG) practitioner levels P1–P5 + Graduate/Instructor tracks (no colored belts); IKMF uses a similar graded-level system with yellow/orange/green/blue/brown/black; solo-drillable content maps to KMG's 'combatives' curriculum (strike 
- needs: Reuses Boxing/Kickboxing strike classifiers (palm-heel, hammerfist, elbow, knee, low-kick) — no fundamentally new pose category, but needs an in-app disclaimer distinguishing 'combatives conditioning' from full self-defense training.
- caveat: Because the discipline's core identity (contact self-defense against a resisting attacker) is not solo-trainable, JabLab's Krav Maga module should be explicitly framed as 'Krav Mag
- url: https://www.forgekravmaga.com/forge-krav-maga-blog/april-2025-the-global-state-of-krav-maga-major-organizations-breakaways-and-innovators
### Fitness Boxing / Cardio Kickboxing (non-technical fitness mode)
- pop: Cardio kickboxing: +8.5% YoY participation growth, the largest 1-year increase of any tracked US fitness activity (SFIA 2023 Tracking the Fitness Movement Report).
- feas: ✅ feasible — technically the easiest tier in the whole catalog: simplified punch/kick vocabulary, no advanced kicks or forms, tempo-driven rather than precision-driven, ideal fit for the existing V1 event-detection engine plus a beat/tempo layer.
- curr: No belts/levels — structured as class formats/tracks (e.g. beginner 20-min / intermediate 30-min / advanced 45-min HIIT combos); combo vocabulary is the shared jab-cross-hook-uppercut-front kick-round kick set already covered by Boxing+Kickboxing eng
- needs: Tempo/BPM-sync layer (matching strikes to a music beat) rather than a new pose-classification need — lowest engineering lift of any item in this catalog.
- caveat: Overlaps heavily with Boxing+Kickboxing content; best treated as a UI/mode ('Fitness Mode' toggle with music sync and simplified scoring) rather than a separate content pipeline.
- url: https://sfia.org/resources/sfias-tracking-the-fitness-movement-report-sees-increase-in-number-of-americans-working-out/
### Tai Chi (Taijiquan — slow forms)
- pop: Estimates vary by source from ~78M (2025 national survey, China-specific, https://www.taichiwuji.com/blog/the-national-survey-on-tai-chi-practitioners/) up to 250–300M cited in older secondary sources (https://www.medica
- feas: ✅ feasible — best-case scenario for solo camera pose analysis: slow tempo eliminates blur, forms are performed largely in place or with small controlled steps, and the DTW/sequence-scoring engine already required for Karate kata / Taekwondo poomsae applies directly, with an easier input signal than 
- curr: No belt system; forms-based progression by form length/complexity: simplified 24-form (Yang, standardized 1956 competition form) → traditional 85–108 move long forms → weapons forms (excluded, see risks) → push-hands (partner-based, excluded); named 
- needs: Reuses the kata/poomsae DTW sequence-scoring engine but tuned for slow, continuous (non-discrete-event) motion — actually a good proving ground to build that engine on before tackling the harder fast-kick cases in Karate/Taekwondo.
- caveat: Practitioner-count sources disagree by >3x (78M vs 250–300M) depending on whether 'practice at least occasionally' or 'formally trained' is counted, and whether the count is China-
- url: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12436410/
### EXCLUDED: BJJ, Wrestling, Judo (grappling/ground arts)
- pop: All three are globally massive (Judo is Olympic since 1964 with 200+ IJF member federations; BJJ has exploded in Western gyms post-UFC/ADCC boom; wrestling is one of the oldest Olympic sports) — popularity is not the lim
- feas: ❌ not feasible for the core discipline — every technique that defines these arts (takedowns, throws, pins, submissions, guard passing, sweeps) requires a second body applying real resistance, grip, and weight; a solo phone-camera app cannot simulate an opponent's mass, friction, or counter-resistanc
- curr: N/A — excluded from scope.
- needs: N/A — excluded from scope.
- caveat: A narrow, defensible 'solo conditioning' mode (e.g. judo ukemi/breakfall solo practice, wrestling stance-and-motion drilling) is theoretically salvageable as a minor adjacent featu
- url: https://en.wikipedia.org/wiki/International_Judo_Federation
### EXCLUDED: Weapons Arts (Kali/Arnis, Kendo, Iaido, HEMA, etc.)
- pop: Kendo: All Japan Kendo Federation + International Kendo Federation report participation across 50+ countries; Kali/Arnis is the Philippines' national sport with global FMA (Filipino Martial Arts) seminar/course circuit d
- feas: ❌ not feasible with current engine (MediaPipe body-only pose landmarks) — the entire technique vocabulary (strike angles, weapon-tip trajectory, sword-cutting-plane accuracy, stick/blade contact timing) is defined by the WEAPON's position and edge/tip alignment, not just the practitioner's body join
- curr: N/A — excluded from scope.
- needs: N/A — excluded from scope; would require a wholly separate object/prop-tracking computer-vision stack (not a MediaPipe pose extension) to even attempt in a future product line, which is out of scope for JabLab as currently engineered.
- caveat: If ever revisited, only a prop-free 'empty-hand footwork and body mechanics' subset (e.g. Kali's angle-of-attack footwork drilled without a stick) would be body-pose-feasible — the
- url: https://en.wikipedia.org/wiki/All_Japan_Kendo_Federation


# ==== ostinato-scope ====

## SUMMARY
Full-scope catalog for Ostinato (camera-posture + audio instrument coach) covering the 13 highest-demand instruments across keyboard, guitar-family, voice, bowed strings, winds, and percussion. Voice, ukulele, and bass are the most cleanly ✅-feasible items (monophonic audio, unoccluded posture); piano and guitar are the highest-demand but structurally ⚠️-limited to chord-class + posture coaching rather than full polyphonic transcription; violin/cello/flute/sax/clarinet/trumpet share two new reusable engine modules (bowed-string monophonic-pitch+bow-posture; wind monophonic-pitch+breath-posture); drums require a genuinely separate percussive-onset-detection module and are recommended as a later wave; harmonica is a cheap optional bonus lacking a formal grade ladder. Recommended build order follows demand × feasibility × marginal engine cost: Voice → Piano/Guitar → Ukulele/Bass → Violin/Cello → Flute/Sax/Clarinet/Trumpet → Drums → (optional) Harmonica.

## RECOMMENDATIONS
- Wave 1 (highest demand × highest feasibility × lowest tech-increment cost): Voice (fully feasible, monophonic, reuses nothing external), Piano/Keyboard posture+chord-class, Guitar posture+chord-class. These three account for ~87% of US lesson-request demand and validate both the monophonic-pitch engine (voice) and the chord-class/hand-landmark engine (piano, guitar) that every later wave reuses.
- Wave 2 (cheap incremental adds once Wave-1 engines exist): Ukulele and Bass Guitar — both reuse the guitar fretboard/hand-landmark module almost unchanged (ukulele = fewer strings/simpler shapes, bass = mostly monophonic so it's actually easier than 6-string guitar audio-wise). Near-zero net-new engine cost, meaningful demand coverage.
- Wave 3 (bowed strings, share a new monophonic-pitch-plus-bow-posture module): Violin then Cello — violin first since it has stronger demand/curriculum evidence; cello reuses ~90% of the violin engine with a seated-posture variant.
- Wave 4 (winds, share a new breath-posture-plus-monophonic-pitch module): Flute first (broadest school-band footprint), then Saxophone and Clarinet (near-identical engine, differ mainly in reference-data/fingering charts), then Trumpet (cheapest brass fingering system to track).
- Wave 5 (drums — genuinely new audio paradigm): add only after the percussive-onset-detection module is built separately from every pitched-instrument module above; PAS 40 Rudiments give a ready-made curriculum ladder.
- Wave 6 / optional low-priority: Harmonica — cheap to bolt onto the monophonic engine for basic melody coaching, but lacks a formal grade syllabus, so treat as a bonus rather than a scoped core instrument.
- Explicitly scope piano and guitar claims to the public: market copy should say 'chord-class verification + posture/hand-shape coaching', never 'note-perfect polyphonic transcription' — the latter is not deliverable on-device from a single mic in real time and overclaiming here is a credibility risk given the founder's honesty-metrics standard.

## RISKS
- Polyphony ceiling: piano and guitar chord-class detection (root+quality via chroma/FFT) is NOT equivalent to full multi-note transcription; if marketing or in-app copy implies note-perfect grading of chords, this is a false/overclaimed capability and violates the product's own honesty-metrics stance.
- Camera occlusion: two-hand piano playing (far hand blocked by torso/near hand), full drum-kit view (4 limbs, some hidden by hardware), and fine embouchure/fingering detail on all wind instruments cannot be fully resolved from ONE static phone camera — coaching must be explicitly scoped to what's visible (posture, near-hand shape, broad timing) rather than implying complete technique grading.
- Evidence thinness: several popularity claims (violin, cello, saxophone, clarinet, trumpet, bass, ukulele) rest on exam-board catalog presence and school-enrollment convention rather than an independent global participation survey — no single authoritative 'instrument popularity census' was found in this research pass; these should be labeled directional, not hard-verified, in any founder-facing roadmap doc.
- Percussive audio module is a genuinely separate engineering investment from every pitched-instrument module (onset/energy-transient detection vs. pitch/chroma detection) — do not treat drums as a 'small incremental add' the way ukulele/bass are relative to guitar; budget it as its own build.
- Harmonica and similarly under-graded instruments (oud/regional instruments not covered in this pass) lack ABRSM/Trinity-style standardized curricula, which weakens the deterministic rule-engine's ability to grade progress against an external, defensible standard — worth a founder decision on whether 'full scope' requires inventing an in-house grading ladder for ungraded instruments.

## ITEMS
### Piano / Keyboard (digital keyboard, no visible strings)
- pop: Piano/keyboard players estimated >100M globally; piano is the #1 US lesson request instrument (nearly 87% of requests shared with voice+guitar).
- feas: ⚠️ feasible-with-constraints — single side/3-quarter static phone shot can see posture (back curve, wrist angle, shoulder) and finger position on the visible hand, but full 10-finger polyphony cannot be reliably transcribed from audio alone (MIDI-less piano) nor from a single 2D camera angle (hand-o
- curr: ABRSM/Trinity/RCM graded syllabi (Grade 1–8, ~3 pieces per grade from lists A/B/C) + standard method books (Alfred, Faber, Bastien).
- needs: Chroma/FFT-based chord-class detector (not full polyphonic transcription); optional MIDI-keyboard-audio bridge as an opt-in higher-fidelity mode; two-hand occlusion means engine should coach posture+hand-shape primarily, chord audio secondarily, not 
- caveat: Global player-count figures (>100M) come from industry blog aggregation (WorldRankd), not a primary census — treat as directional. Full note-level transcription from mic audio on p
- url: https://www.namm.org/sites/default/files/2025-11/NAMM2025GlobalReportV3.pdf
### Acoustic & Electric Guitar
- pop: Guitar sales >3.8M units/year (acoustic+electric combined, 2020 baseline) and 50M+ global players; #1 global search-trend instrument in 2025-2026 per trend aggregation.
- feas: ⚠️ feasible-with-constraints — single phone angled to see fretting hand + body posture works for chord-shape/strum coaching, but full 6-string polyphonic transcription (verifying every note in a barre chord) is not reliable from mono mic + MediaPipe hand landmarks alone. Fretting-hand fingertip-to-f
- curr: ABRSM/Trinity/RockSchool guitar grades (3 pieces from Lists A/B/C, technical exercises, sight-reading) + open chord library → barre chords → CAGED system progression.
- needs: MediaPipe Hands (21 landmarks) mapped to a virtual fretboard for finger-shape scoring; chroma/FFT chord-class recognizer for strum verification; strum-hand motion/rhythm tracked via pose/hand velocity, not audio-onset alone (percussive string noise i
- caveat: Guitar unit-sales stat (3.8M/yr) is a 2020 figure repeated in secondary sources, not independently re-verified for 2025-2026.
- url: https://www.abrsm.org/sites/default/files/2025-05/Guitar%20Practical%20Grade%20Syllabus_0.pdf
### Voice / Singing
- pop: Voice lessons are one of the top 3 requested instrument categories in the US 190,000-lesson-request dataset analyzed by LessonRating.
- feas: ✅ feasible — single static front-facing phone camera sees full posture (spine, shoulders, jaw tension) and breath mechanics (visible diaphragm/rib expansion); audio is single-note monophonic, ideal for real-time on-device pitch tracking (YIN/CREPE-class algorithms run well on mobile CPUs).
- curr: ABRSM/Trinity Singing & Singing-for-Musical-Theatre grades (Grade 1–8): prepared songs + musicianship + aural tests, adaptable to solfège/interval drills.
- needs: Monophonic pitch tracker (YIN or a lightweight CREPE-style CNN) for cents-accurate pitch/vibrato feedback; pose landmarks for shoulder/jaw/posture cues; breath-timing inferred from torso landmark motion, not audio alone.
- caveat: None major — this is the most technically 'solved' instrument for the engine; main caveat is repertoire licensing for reference tracks, not feasibility.
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Violin
- pop: Violin is a core ABRSM/Trinity bowed-strings offering alongside viola/cello/double bass, one of the most-examined instruments in graded music exam systems globally.
- feas: ⚠️ feasible-with-constraints — single side-on camera shot shows bow-arm angle, elbow height, and violin/shoulder posture well; monophonic pitch tracking (mostly single sustained notes for beginners) works well on-device. Constraint: fast bow strokes and left-hand finger placement on the fingerboard 
- curr: ABRSM/Trinity/Suzuki-book progressions (Grade 1–8 or Suzuki Books 1–10): scales, arpeggios, graded repertoire, sight-reading, aural tests.
- needs: Monophonic pitch/intonation tracker (same class as voice); pose+object detection for the bow stick to estimate bow angle/straightness; left-hand landmark tracking limited by camera resolution at typical filming distance.
- caveat: No global player-count survey found with strong evidence; popularity claim rests on exam-board breadth and Suzuki-method ubiquity, not a hard participation number — flagged as thin
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Cello
- pop: Included in ABRSM/Trinity Bowed Strings family alongside violin; standard second string instrument in school orchestra programs worldwide.
- feas: ⚠️ feasible-with-constraints — same as violin: side-on static camera captures bow-arm and seated posture well; monophonic pitch tracking works; fine bow-angle/fingerboard precision is constrained by camera resolution/frame rate, and seated posture needs a slightly different fixed camera height than 
- curr: ABRSM/Trinity Cello grades (parallel structure to violin) + Suzuki Cello Books 1–8.
- needs: Same monophonic pitch engine as violin/voice, reused; seated-posture pose model variant (hip/back angle relative to chair, endpin/instrument angle) distinct from violin's standing model.
- caveat: No independent global demand statistic found beyond exam-board catalog presence; treat popularity ranking as lower-confidence than violin/piano/guitar.
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Bass Guitar (electric/acoustic)
- pop: Standard rhythm-section instrument taught in every contemporary/rock music program; RockSchool/Trinity offer dedicated bass grade syllabi mirroring guitar's structure.
- feas: ✅ feasible — mostly monophonic (one note at a time), so audio pitch-tracking is straightforward (unlike 6-string chordal guitar); fretting-hand shape visible from the same camera angle used for guitar.
- curr: RockSchool/Trinity Bass Grades 1–8 (technical exercises + pieces) + walking-bassline/groove pattern libraries.
- needs: Reuses guitar's MediaPipe-Hands fretboard mapping at 4-string spacing; audio engine is simpler than guitar's since bass is overwhelmingly monophonic — largest 'free' addition to the catalog.
- caveat: No standalone global player-count found; popularity inferred from universal rhythm-section role and exam-board coverage, not a demand survey.
- url: https://www.trinitycollege.com/qualifications/music/rock-pop
### Drums / Percussion (drum kit)
- pop: 40 PAS International Drum Rudiments are the globally adopted standard curriculum, maintained by the Percussive Arts Society and used in drum corps, orchestral, and drum-set pedagogy worldwide.
- feas: ⚠️ feasible-with-constraints — camera sees stick-hand/limb posture and general body mechanics from a fixed 3-quarter angle, but full kit view (hi-hat foot, kick pedal, all 4 limbs) from ONE static phone requires careful placement and some limbs will be partially occluded by the kit itself; audio-sid
- curr: PAS 40 International Drum Rudiments (26 standard + 14 additional) + drum-set-specific grade books (RockSchool/Trinity Drum Kit Grades 1–8).
- needs: Percussive onset-detection engine (energy-transient based, not pitch-based) — a genuinely different audio module from every pitched instrument in the catalog; stick/limb pose tracking rather than fingerboard hand-landmarks; camera placement guidance 
- caveat: No global drummer-count survey found; popularity claim rests on rudiment-standard ubiquity and exam-board coverage rather than participation numbers.
- url: https://pas.org/rudiments/
### Ukulele
- pop: Widely adopted in school music programs worldwide (esp. US, UK, Pacific) as a low-cost guitar-family entry instrument; Trinity College London offers a dedicated Ukulele grade syllabus.
- feas: ✅ feasible — 4-string, simpler chord shapes than guitar reduce both hand-landmark ambiguity and audio chord-class ambiguity versus 6-string guitar; single static camera angle works well given the instrument's compact size and typically seated/close-body playing position.
- curr: Trinity/RockSchool Ukulele Grades (technical + pieces) + open-chord shape libraries (C, Am, F, G progressions).
- needs: Directly reuses the guitar fretboard-mapping + chord-class engine at 4-string/simplified-shape config — near-zero net-new engine work, making it a high-ROI early wave item.
- caveat: No standalone global demand statistic found beyond its role in school curricula; treated as a demand-inferred rather than measured entry.
- url: https://www.trinitycollege.com/qualifications/music
### Flute (Western concert)
- pop: Flute is one of the most-enrolled instruments in US/UK school band programs and a standard ABRSM/Trinity Woodwind syllabus instrument.
- feas: ⚠️ feasible-with-constraints — side-on camera sees posture, head/embouchure angle, and breath support reasonably well; monophonic audio pitch-tracking is straightforward (single note at a time like voice/violin). Constraint: fine embouchure lip-shape detail and exact fingering on tone-hole keys are 
- curr: ABRSM/Trinity Woodwind (Flute) Grades 1–8: scales, arpeggios, graded pieces, sight-reading, aural.
- needs: Same monophonic pitch engine as voice/violin/cello (reused); breath-support cue from torso-landmark motion; no object-detection needed (no external implement).
- caveat: No global player-count survey found; popularity inferred from school-band enrollment patterns (US/UK), which may not generalize globally — flagged as regionally-biased evidence.
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Saxophone (alto, most common beginner horn)
- pop: Standard ABRSM/Trinity Woodwind syllabus instrument and one of the top beginner-horn choices in US school band enrollment alongside flute and clarinet.
- feas: ⚠️ feasible-with-constraints — same profile as flute: posture and breath visible from a fixed side/front angle, monophonic pitch tracking works well; embouchure and fine key-fingering detail again resolvable only coarsely at typical phone distance.
- curr: ABRSM/Trinity Saxophone Grades 1–8 (parallel structure to flute/clarinet).
- needs: Reuses the shared monophonic-pitch + breath-wind posture module built for flute; neck-strap/instrument-angle posture cue specific to saxophone's weight-bearing ergonomics.
- caveat: Same evidence caveat as flute — no independent global demand survey, popularity inferred from school-band and exam-board presence.
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Clarinet
- pop: Core ABRSM/Trinity Woodwind syllabus instrument; standard third woodwind choice in school band programs alongside flute and saxophone.
- feas: ⚠️ feasible-with-constraints — identical profile to flute/saxophone: posture+breath+monophonic pitch feasible, fine embouchure/key detail only coarse.
- curr: ABRSM/Trinity Clarinet Grades 1–8.
- needs: Reuses shared monophonic-pitch + wind-instrument posture module; no new engine component beyond instrument-specific fingering charts/reference data.
- caveat: Same evidence caveat as flute/saxophone — no independent global demand survey found.
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Trumpet
- pop: Standard ABRSM/Trinity Brass syllabus instrument and the most common beginner brass choice in school band programs.
- feas: ⚠️ feasible-with-constraints — posture/breath/monophonic-pitch feasible on the shared wind module; the 3-valve system is actually MORE camera-tractable than flute/sax/clarinet key systems (fewer, larger, more visually distinct finger positions), though embouchure buzz detail is still not resolvable 
- curr: ABRSM/Trinity Trumpet Grades 1–8.
- needs: Reuses shared monophonic-pitch + wind posture module; valve-press detection via hand-landmark tracking is simpler than woodwind key-tracking, making trumpet a comparatively cheap brass-family entry.
- caveat: No independent global demand survey found; popularity inferred from school-band enrollment convention.
- url: https://www.abrsm.org/sites/default/files/2023-10/00-performance-grades-qual-spec-generic-parts-230728.pdf
### Harmonica
- pop: One of the best-selling instruments globally by unit volume (very low price point) though it lacks a dedicated ABRSM/Trinity grade ladder — its curriculum is method-book driven (Hohner/Lee Oskar tutors) rather than exam-
- feas: ✅ feasible for basic single-note melody coaching (breath direction + monophonic pitch) — ⚠️ feasible-with-constraints for bending/chord techniques (2-3 simultaneous reed tones during bends are a mild polyphony case, similar in kind to guitar/piano chord-class detection, not full transcription).
- curr: Method-book progressions (single notes → bends → tongue-blocking/chords → cross-harp blues positions); no major exam-board grade system found, unlike piano/guitar/strings/winds.
- needs: Reuses monophonic pitch engine for melody; needs a bend/vibrato-specific pitch-glide detector; minimal camera/pose requirement since there is little visible posture information (mouth position is the main visual cue).
- caveat: No formal grade syllabus exists (unlike ABRSM-covered instruments) — curriculum structure is thinner/less standardized; treat as a lower-priority, low-cost 'wave 3+' addition rathe
- url: https://pas.org/rudiments/


# ==== music-tech-deep ====

## SUMMARY
Ostinato (multi-instrument audio coaching) tech deep-dive: a licensing-clean, on-device toolbox exists for every requested capability except camera-based embouchure detection. Spotify's Basic Pitch (Apache-2.0) is the right engine for polyphonic chord/note verification on guitar/piano/ukulele — feasible for chord-match scoring, not full fast-passage transcription. GPL/AGPL libraries (aubio, Essentia, madmom's ecosystem, TarsosDSP's GPL dependencies) are common traps and should be avoided in favor of in-house reimplementation of standard, well-published onset-detection DSP (spectral flux/HFC), which is low-risk engineering. Percussion rudiment timing via on-device onset detection is already proven viable by shipped competitor apps (Rudimentalist, StickPulse), but full-kit multi-drum classification from one phone mic is not reliable — scope v1 to single-pad/snare timing. Voice/singing apps (Yousician, Vanido) validate a metric set of pitch accuracy, timing, and vibrato rate/extent (derivable from the existing YIN/SwiftF0 pitch stream with no new library); camera-based 'breath posture' is feasible only as a coarse shoulder/chest posture cue, not a true breath-support measurement. Wind instruments are feasible for pitch and articulation-onset (same architecture as voice/percussion) but embouchure is confirmed NOT camera-visible — peer-reviewed embouchure research relies on intraoral piezoresistive sensors or dental impressions, with no camera substitute existing; this should be explicitly excluded from the wind module's promised feedback. The MIDI shortcut for piano is a strong, low-risk win: BSD-licensed Flutter MIDI packages (flutter_midi_command, libremidi_flutter, universal_ble) give exact note/timing/velocity data with zero audio-ML uncertainty when a student has a MIDI keyboard, and should be built as an opportunistic enhanced mode alongside the camera+audio fallback. Finally, an MIT-licensed AVAudioEngine/AudioKit-style sample-accurate metronome and onset-to-beat-grid scoring engine can be built once and reused across all five instrument modules as shared rhythm-timing infrastructure.

## RECOMMENDATIONS
- Adopt Spotify Basic Pitch (Apache-2.0) as the core polyphonic engine for guitar/piano/ukulele chord-match verification; convert to TFLite/CoreML for on-device inference and build a template-matching post-processor rather than relying on full note transcription.
- Do NOT integrate aubio, Essentia (AGPL core + NC-licensed models), or TarsosDSP's GPL-dependent components into the closed-source app; reimplement onset detection (spectral flux/HFC peak-picking) in-house from published DSP literature — this is standard, low-risk engineering.
- Build MIDI input (USB + BLE) as a first-class opportunistic enhancement for the piano module using flutter_midi_command / libremidi_flutter / universal_ble (all BSD-licensed); market it explicitly as 'connect your keyboard for perfect note detection' rather than a requirement.
- Scope the percussion module's v1 to single-pad/snare rudiment timing (proven viable by Rudimentalist/StickPulse); defer or heavily caveat full-kit multi-drum onset classification from a single phone mic.
- Add vibrato rate/extent scoring to the voice module using the existing pitch-contour time series (no new dependency) — flagged as a real differentiator since Yousician's own reviewers note its singing module doesn't meaningfully address vibrato.
- Explicitly exclude embouchure-shape/lip-position feedback from the wind-instrument module's marketing and in-app promises — camera cannot see inside the mouthpiece; scope wind coaching to pitch, articulation-onset clarity, tone sustain, and rhythm only.
- Build one shared MIT-licensed 'RhythmEngine' (AVAudioEngine/AAudio buffer-scheduled beat grid + onset-to-grid deviation scorer) reused across all five apps' rhythm-scoring needs, regardless of whether the onset source is audio, MIDI note-on, or pose-based rep detection.

## RISKS
- Basic Pitch's polyphonic accuracy degrades on fast strumming, heavy distortion, and dense >4-note voicings — chord-match UX must be designed around sustained/isolated chord strikes, not continuous playing, or false negatives will frustrate students.
- Licensing evidence for chord-recognition-specific commercial-safe models beyond Basic Pitch is thin; most literature found is academic (arXiv) or GPL/CC-BY-NC — treat Basic Pitch as the primary/only verified commercial-safe polyphonic option until further diligence.
- Wind-instrument module commercial demand evidence is thin — only Wind2Notes (a transcription tool, not a coaching app) was found as a comparable; this is a tech-feasibility finding, not a validated market-demand finding, and should get its own market check before heavy investment.
- Camera-based 'breath posture' scoring risks overpromising to users if marketed as measuring breath support/diaphragmatic technique rather than gross shoulder/chest posture — keep in-app language conservative to avoid a false-claims/expectation-mismatch risk.
- TarsosDSP research surfaced conflicting license signals (top-level code vs. GPL dependencies); if any existing prototype code already vendors TarsosDSP or aubio, an explicit license audit is needed before any commercial release.

## ITEMS
### Spotify Basic Pitch (audio-to-MIDI, Apache-2.0)
- pop: Widely cited MIR benchmark tool since Spotify open-sourced it 2022; 3.3k+ GitHub stars as of check.
- feas: ⚠️ feasible-with-constraints: works well for static chord/note-set verification (compare detected pitch set to expected chord) at ~100-300ms decision windows; NOT reliable for fast strumming/fingerpicking passage transcription, heavy distortion, or dense >4-note voicings — accuracy documented as deg
- curr: Not a curriculum tool itself — used as the recognition engine underneath the app's own chord/exercise curriculum (open/barre chords → power chords → arpeggios).
- needs: Convert the TF SavedModel to TFLite (or CoreML via coremltools) for on-device inference in Flutter (via platform channel/native inference, e.g. tflite_flutter); need a 'chord-match' post-processor that buckets detected note-set against expected chord
- caveat: ?
- url: https://github.com/spotify/basic-pitch
### Basic Pitch LICENSE file
- pop: N/A — legal fact, not a demand metric.
- feas: ✅ feasible — license is not a blocker for a closed-source commercial mobile app.
- curr: N/A — licensing artifact.
- needs: Retain Apache-2.0 NOTICE in app's open-source attributions screen.
- caveat: ?
- url: https://github.com/spotify/basic-pitch/blob/main/README.md?plain=1
### Onset-detection-based rudiment trainers (Rudimentalist, StickPulse, Drummer ITP)
- pop: Multiple independent apps built around this exact feature since ~2023-2025, indicating validated demand among drummers for pad-based timing feedback.
- feas: ✅ feasible for practice-pad or acoustic kit with directional mic placement (single onset stream, timing-only, no pitch/timbre classification needed). ⚠️ feasible-with-constraints for distinguishing WHICH drum/cymbal was hit in a full kit (multi-source onset separation from one phone mic is unreliabl
- curr: PAS (Percussive Arts Society) 40 International Drum Rudiments — standard graded syllabus already used by these apps.
- needs: Custom lightweight onset-detector (spectral flux / high-frequency-content peak-picking) implemented natively in Swift/Kotlin — avoid GPL libraries (aubio, TarsosDSP's GPL deps) for licensing cleanliness; write a small permissively-licensed onset dete
- caveat: ?
- url: https://rudimentalist.com/
### GPL/AGPL-encumbered audio-DSP libraries — AVOID for closed-source app
- pop: N/A — cautionary licensing note, not a feature.
- feas: ❌ not usable as-is in a closed-source app without either (a) purchasing Essentia's commercial license, (b) reimplementing the needed algorithm from a paper under your own permissive code, or (c) fully open-sourcing under GPL/AGPL (not viable for App Store business model).
- curr: N/A — infrastructure choice.
- needs: Reimplement onset detection (spectral-flux/HFC peak picking) and pitch tracking (autocorrelation/YIN — already used per context) from published algorithms in-house; this is standard, well-documented DSP (not novel research) so reimplementation risk i
- caveat: ?
- url: https://aubio.org/
### Vanido / Yousician-voice singing-coach feature set
- pop: Yousician reports large singing-module user base within its broader multi-instrument platform; reviewed as of 2026 in independent vocal-coaching blogs.
- feas: ✅ feasible for pitch accuracy, timing, and vibrato rate/extent (all derivable from the same mono pitch-tracker time series, no new sensor). ⚠️ feasible-with-constraints for 'breath posture via camera' — camera can observe shoulder/chest rise and gross posture (upright vs slumped, visible over-breath
- curr: Apps reviewed (Yousician, Vanido, Sing Sharp) use graded pitch-accuracy/timing scoring per exercise with note-range calibration; Yousician's own reviewers note it explicitly does NOT meaningfully address vibrato, which is a stated gap Ostinato could 
- needs: Vibrato detection = FFT or zero-crossing analysis of the pitch-contour signal itself (no new library); posture cue = MediaPipe pose landmarks already in the stack (shoulder/chest keypoint motion), explicitly framed in-app as 'posture' not 'breath vol
- caveat: ?
- url: https://www.bloomvocal.site/en/blog/yousician-review-2026
### Wind instrument (trumpet, saxophone, clarinet, flute) module tech feasibility
- pop: Thin direct evidence located for consumer wind-practice apps at scale; Wind2Notes (klang.io) exists as an audio-to-notation tool for brass/woodwind, indicating commercial interest in wind-instrument audio analysis, thoug
- feas: ✅ feasible: pitch accuracy + note-onset/articulation timing (did the student tongue the note cleanly and on the beat) from a single phone mic, same architecture as voice/percussion modules. ❌ not feasible: embouchure (lip position, mouthpiece pressure, air-column shaping) — physically invisible to a
- curr: Standard method-book progressions (e.g., Arban's for trumpet, long-tone/lip-slur drills) already structure wind pedagogy around pitch/tone/articulation, which maps cleanly onto the feasible metric set.
- needs: None beyond existing pitch/onset stack; explicitly scope the module's coaching feedback to pitch accuracy, rhythm, articulation clarity (attack sharpness from onset envelope), and tone sustain/breath endurance (note length) — NOT embouchure shape/lip
- caveat: Popularity evidence for a dedicated wind-instrument mobile coaching app market is thin — Wind2Notes is transcription, not coaching; recommend treating wind module demand as a found
- url: https://klang.io/wind2notes/
### Flutter MIDI input packages (flutter_midi_command, flutter_midi_command_ble, libremidi_flutter, universal_ble)
- pop: MIDI keyboard/controller ownership among piano learners is high and well-documented in the digital-piano/MIDI-controller consumer market (dominant learning setups pair phone/tablet apps with USB or Bluetooth MIDI keyboar
- feas: ✅ feasible and should be a first-class input mode: MIDI gives ground-truth note/timing/velocity data, eliminating polyphonic-pitch-detection error entirely for connected-keyboard users. This does NOT replace the camera+audio path for students without a MIDI keyboard (acoustic piano, unconnected keyb
- curr: No new curriculum needed — same piano syllabus, but exercise scoring becomes exact (right/wrong note, timing to the millisecond, velocity/dynamics) when MIDI is present, enabling advanced dynamics/pedaling feedback the audio-only path cannot reliably
- needs: Implement MIDI as an optional enhanced mode: detect connected MIDI device (USB via platform MIDI APIs, BLE via universal_ble/flutter_midi_command_ble), fall back to camera+audio pose/pitch pipeline when no MIDI device present; UI should surface 'conn
- caveat: ?
- url: https://pub.dev/packages/flutter_midi_command
### AVAudioEngine-based sample-accurate metronome + AudioKit PitchTap (MIT license)
- pop: AudioKit is a long-standing, widely used (10k+ GitHub stars historically) open-source audio framework in the iOS indie-music-app ecosystem; SwiftMetronome (MIT) is a smaller but concrete open reference implementation of 
- feas: ✅ feasible: AVAudioEngine buffer-scheduled metronomes are a mature, well-documented iOS pattern; Android equivalent uses AAudio/Oboe for the same low-latency buffer-scheduling approach. Cross-instrument reuse of one 'beat-grid + onset-to-grid deviation scorer' module is architecturally sound since r
- curr: N/A — infrastructure, not curriculum; timing-accuracy scoring is layered onto each module's existing exercise curriculum.
- needs: Build a shared 'RhythmEngine' abstraction: input = timestamped onset events (from whichever per-instrument detector fired them: audio onset, MIDI note-on, or pose-based rep detection for movement apps), output = deviation-from-grid in ms + accuracy s
- caveat: ?
- url: https://github.com/AudioKit/AudioKit/blob/v5.1.0/Sources/AudioKit/Taps/PitchTap.swift


# ==== choreia-scope ====

## SUMMARY
Full-scope Choreia catalog: 20 dance disciplines spanning street/urban (hip-hop, K-pop, breaking, shuffle, Afrobeats, dancehall, house), Latin/social solo-styling (salsa shines, bachata, kizomba/zouk, tango solo), studio/technical (ballet-barre, jazz, contemporary), cultural (belly dance, Bollywood), niche-commercial (heels, twerk), and fitness/mass-market (Zumba-style, line dance) plus a TikTok-trend format. Most items are ✅ fully feasible on a single fixed phone camera with on-device pose analysis; the clearest constraint is Breaking, where toprock/footwork is teachable but power moves/floor inversions are ❌ not feasible for live coaching and must ship as demo-only reference content. Ballet/barre and heels both require dedicated prop/footwear-safety onboarding since the app can guide but not supply or verify a barre or purpose-built dance shoes. The dominant cross-cutting risk is copyright: named commercial/viral choreography (K-pop agency routines, specific TikTok trends, Bollywood film numbers, published line-dance step sheets, the 'Zumba' brand itself) must be taught via originally-choreographed, style-representative combos rather than reproduced verbatim.

## RECOMMENDATIONS
- Wave 1 (launch): Hip-Hop foundations, Zumba-style fitness dance, Line Dance, Salsa Shines, TikTok-trend-format choreo — highest popularity evidence + cleanest ✅ feasibility + lowest legal risk when built as original combos.
- Wave 2: K-Pop point-choreo, Bachata solo styling, Afrobeats/Dancehall crazes, Shuffle, Belly Dance, Bollywood — strong demand, still largely ✅ with minor camera/attribution caveats.
- Wave 3: Jazz, Ballet/Barre (with no-barre furniture-substitute mode), Contemporary/Lyrical (standing-only subset), Kizomba/Zouk solo styling, Tango solo technique, Twerk (3/4 camera-angle mode) — need extra design work (prop substitution, camera-angle guidance, or occlusion handling) before shipping.
- Wave 4 (constrained/partial): Heels Dance (needs a footwear-safety onboarding module before release), Breaking (toprock/uprock module only — power moves shipped as demo-only reference content, never scored, with explicit safety disclaimer).
- Build a shared 'legal-caution tier' flag in content pipeline: green (folk/social steps, freely teachable), yellow (style-representative but must be originally choreographed, not copy a specific viral routine), red (avoid — specific named commercial/branded choreography or trademarked program names like 'Zumba').
- For Ballet/Barre and Heels, ship dedicated in-app prop/footwear guidance screens at onboarding since the app cannot supply or verify a barre or purpose-built dance shoes — this directly answers the founder's two explicit questions (yes to both).

## RISKS
- Breaking power moves and headspins/flares carry genuine injury risk that camera-based coaching cannot supervise — must be demo-only, never scored or encouraged as a practice target.
- Heels dance and cambré/backbend elements (Kizomba/Zouk) carry real balance/spinal-strain risk that on-device pose coaching cannot substitute for in-person spotting — needs conservative safety framing, not aggressive scoring pressure.
- Named viral TikTok choreography, K-pop agency choreography, Bollywood film routines, and published line-dance step sheets are all realistic copyright/attribution exposure points — every reference set must be originally choreographed in-house in the relevant style, not scraped or reproduced from real videos.
- Quantitative global popularity data is genuinely thin for several items (House, Dancehall, Kizomba/Zouk, Twerk, Heels) — evidence is mostly qualitative (studio offerings, festival circuits, tutorial ecosystems) rather than hard participation numbers; flagged as moderate-confidence in caveats.
- Single fixed-camera occlusion is a structural limitation for any floor-work-heavy style (Breaking power moves, Contemporary floor phrases, deep Twerk squats from a straight-front angle) — needs either camera-angle guidance, demo-only mode, or explicit lower-confidence scoring for those segments.

## ITEMS
### Hip-Hop (foundational/social + choreo)
- pop: Hip-hop online-class segment valued ~$300M in 2024, projected ~$900M by 2035; ~46% of North American class activity is contemporary/hip-hop combined per market report.
- feas: ✅ feasible — single fixed camera captures full-body grooves and combos; no partner or floor contact required for standard hip-hop choreo.
- curr: Named foundational grooves (the bounce, the rock, the brooklyn, the twist), 8-count phrase teaching, isolations, then choreography combos; standard in commercial studios (e.g., Millennium, STEEZY) and YouTube tutorial channels.
- needs: None beyond core pose pipeline; groove timing/bounce detection benefits from vertical-displacement + beat-grid alignment.
- caveat: Named commercial choreography (e.g., a specific music video routine) carries copyright/attribution caution — teach via generic combos, not verbatim viral routines, unless licensed.
- url: https://www.globalgrowthinsights.com/market-reports/online-dance-classes-market
### K-Pop Choreo (idol-style, cover-dance)
- pop: K-pop cover-dance ecosystem has 'thousands of channels with hundreds of millions of subscribers'; APAC online dance training projected 13.7% CAGR 2026-2034 driven partly by K-pop demand.
- feas: ✅ feasible solo for point-choreo and full routines when learner mirrors single-dancer camera framing; ⚠️ group formation spacing cannot be taught/verified with one camera.
- curr: 'Point choreography' (signature repeatable gesture per song), mirrored 8-count breakdowns, cover-dance tutorial format (slow/mirror/full-speed) pioneered by cover teams and channels like Ellen & Brian.
- needs: Mirror-mode toggle (left/right flip) for tutorial-style teaching, common in the genre.
- caveat: Full song choreography is often copyrighted/licensed by the idol's agency; app should teach in the 'style of' via original reference sets or heavily attribute, not reproduce verbat
- url: https://www.steezy.co/posts/inside-the-world-of-k-pop-dance-covers-with-ellen-brian
### Salsa Shines (solo footwork/styling)
- pop: Salsa remains one of the most widely taught global social dances in studios worldwide (evidenced by dedicated shines curricula from major online academies like RF Dance and Library of Dance).
- feas: ✅ feasible — shines are solo-by-definition footwork/body isolation, ideal for fixed single-camera on-device pose analysis.
- curr: 8-count basic (step 1-2-3, pause 4, step 5-6-7, pause 8); named beginner shines in order — Suzy Q, grapevine, step-touch, cumbia; intermediate turns and cross-body footwork.
- needs: None beyond standard lower-body landmark tracking for footwork accuracy; music at salsa tempo (~180-250 BPM clave-based, felt as ~90-125 dance BPM).
- caveat: Partner turn patterns (cross-body lead, copa) are explicitly out of scope — app must stay in shines-only lane per founder directive.
- url: https://www.yourdancestudio.com/what-are-salsa-shines/
### Bachata (solo styling/basics)
- pop: Multiple commercial academies (Bachata Dance Academy Online, Bachata Library) run dedicated solo/pre-partnerwork tracks specifically because many learners 'don't have a partner.'
- feas: ✅ feasible — the entire solo-styling curriculum is designed to be danced alone, matching single-camera constraint exactly.
- curr: Basic 4-step/8-count bachata pattern, posture and arm styling, body isolations, hip movement, weight transfer, spins/turns performed solo.
- needs: Hip-isolation tracking benefit from finer pelvis-landmark smoothing given bachata's small, layered hip movements.
- caveat: Sensual bachata partner figures (body rolls with a partner, leg-work between partners) excluded — solo styling only.
- url: https://www.bachatadanceacademyonline.com/solobachata
### House Dance
- pop: Sustained global competitive scene (Juste Debout house category, international house dance festivals) since 1980s Chicago/NYC origins; thin quantitative stats but strong qualitative/competition evidence.
- feas: ⚠️ feasible-with-constraints — fast low footwork can motion-blur on phone camera at low light/frame rate; wide framing needed to keep full body + feet in shot simultaneously.
- curr: Named foundational steps (jacking, lofting/footwork, skating), improvisation-based teaching typical of house dance pedagogy rather than fixed combos.
- needs: Higher frame-rate capture recommendation (≥60fps) for footwork clarity; lower-body landmark confidence thresholding.
- caveat: Improvisational nature makes rigid rule-engine scoring harder than fixed-combo styles — expect looser scoring rubric.
- url: https://en.wikipedia.org/wiki/House_dance
### Afrobeats/Afro Dance
- pop: Global Afrobeats music streaming surge (Spotify/Billboard Afrobeats chart growth 2020-2026) directly correlates with viral dance-craze tutorial volume; individual named crazes (Zanku, Gwara Gwara) each generated tens of 
- feas: ✅ feasible — full-body, standing, single-person moves fit fixed camera well.
- curr: Named individual dance crazes taught as discrete moves rather than one continuous syllabus; typically sequenced beginner-friendly crazes first, then combination routines.
- needs: None beyond standard full-body tracking.
- caveat: Individual dance-craze names/origins should be credited (many originated from specific African creators/regions) to avoid appropriation framing; avoid reproducing a specific viral 
- url: https://www.bbc.com/culture/article/20230504-the-dance-crazes-taking-over-the-world
### Dancehall
- pop: International dancehall workshop circuit (teachers touring Europe/Asia) and consistent YouTube tutorial catalogs (e.g., Dancehall International) evidence sustained global demand; quantitative market stats thin.
- feas: ✅ feasible for most standing moves; ⚠️ a few moves (e.g., historic 'Dutty Wine' neck-rotation) carry documented injury risk and should be flagged/excluded or taught with an explicit safety caution, not scored for depth.
- curr: Named individual moves taught discretely (similar pedagogy to Afrobeats), building to social 'dancehall session' combinations.
- needs: Safety-flag system for moves with known injury history (neck/spine stress).
- caveat: Some named moves are tied to specific dancehall artists/choreographers — attribute origin; avoid teaching the injury-risk 'Dutty Wine' full neck-spin variant.
- url: https://www.residentadvisor.net/features/3623
### Ballet Basics / Barre
- pop: ~3.8 million people took barre classes in 2022 in the US alone; franchises (Pure Barre, Barre3) operate hundreds of locations internationally across Europe, Middle East, Asia, Australia.
- feas: ⚠️ feasible-with-constraints — turnout and foot positions (1st-5th) are checkable via lower-body landmarks from a front-facing camera, but a real barre for balance support cannot be verified/required by the app; user must have their own support (chair/counter) off-camera or app must design 'no-barre
- curr: Classical named positions (1st-5th position), pliés, tendus, relevés; barre-fitness adds small isometric pulses and core sequences layered on ballet vocabulary.
- needs: Explicit user guidance to use a household support (chair/counter) since the app cannot supply or verify a barre prop; turnout-angle estimation from ankle/hip/knee landmark triangle.
- caveat: Turnout measurement from a single 2D camera view is approximate (depth ambiguity) — report as guidance, not medical/precision assessment. Answer to founder's explicit question: yes
- url: https://www.therussianballet.com/blog/barre-from-ballet-origins-to-a-modern-fitness-phenomenon
### Contemporary/Lyrical
- pop: Cited alongside hip-hop as dominating 'usage metrics' in the online dance-class market due to dynamic, expressive format popular with younger audiences; large studio-competition ecosystem (JUMP, NYCDA) globally.
- feas: ⚠️ feasible-with-constraints — floor work (rolls, drops to the ground) causes camera-frame occlusion and depth loss on a single fixed phone camera; standing/traveling phrases are fully trackable.
- curr: Technique built from ballet/modern vocabulary (contraction/release, floor work, across-the-floor leaps and turns) plus improvisation and emotional-intent coaching.
- needs: Wide-angle framing guidance and a 'floor-work confidence flag' that lowers scoring precision when the dancer goes below a landmark-visibility threshold.
- caveat: Full floor sequences may need to be marked as demonstration-only (avatar-taught) rather than scored, given occlusion.
- url: https://www.globalgrowthinsights.com/market-reports/online-dance-classes-market
### Jazz (commercial/theatrical)
- pop: Standard component of global dance-studio syllabi (e.g., ISTD, Dance Masters of America jazz syllabi) alongside ballet/tap; consistently among top requested genres in market reports.
- feas: ✅ feasible — mostly standing, full-body, front-facing choreography suits fixed single camera well; occasional floor moments are minor vs. contemporary.
- curr: Graded syllabus systems exist (e.g., ISTD Jazz Grades, DMA Jazz Certification) with named steps (jazz square, chassé, pirouette, kick ball change) and level progression.
- needs: Turn-counting (pirouette rotation tracking) benefits from torso-rotation angular velocity from shoulder/hip landmarks.
- caveat: Graded syllabus content (ISTD etc.) is copyrighted curriculum — build original but pedagogically equivalent step progressions rather than reproducing licensed syllabus material ver
- url: https://www.numberanalytics.com/blog/ballet-fundamentals-for-beginners
### Breaking/Breakdance
- pop: Olympic debut at Paris 2024 (16 B-Boys/16 B-Girls); global scene traced through International B-Boy Championships, Battle of the Year (est. 1990), UK B-Boy Championships — decades of international competitive infrastruct
- feas: ⚠️ feasible-with-constraints for toprock/uprock/basic footwork (standing/low, front-facing, trackable); ❌ not feasible for power moves and floor footwork requiring ground-level inverted positions — a single fixed phone camera cannot maintain pose-landmark visibility when the dancer is inverted, spin
- curr: Named foundational vocabulary: toprock, footwork/downrock (6-step, CC, etc.), freezes, power moves; taught in progressive foundation→power-move syllabus by most breaking schools globally.
- needs: Toprock module only for full pose-tracking; power-move/floor content should be presented as reference/inspiration video only, never scored, with an explicit in-app safety disclaimer.
- caveat: This is the clearest ❌/⚠️ split in the whole catalog — be explicit with users that only toprock/uprock is coached live; power moves are demo-only.
- url: https://www.olympics.com/en/sports/breaking/
### Shuffle (Melbourne Shuffle/Cutting Shapes)
- pop: Extensive dedicated TikTok tutorial hashtag ecosystem across multiple sub-styles (Melbourne, Ausstyle, hardstyle shuffle) evidencing sustained high tutorial-search volume.
- feas: ✅ feasible — standing, front-on, repetitive footwork is well suited to fixed-camera pose tracking, though very fast footwork needs high frame rate.
- curr: Named core steps (running man, T-step, heel-toe) taught sequentially, then combined into freestyle-friendly loops matched to track BPM.
- needs: ≥60fps capture recommended; foot-strike beat-alignment scoring given the style's rhythm-precision emphasis.
- caveat: None significant; low legal-caution style since steps are generic/folk-origin, not commercially owned choreography.
- url: https://www.tiktok.com/discover/melbourne-shuffle-tutorial
### Belly Dance (Raqs Sharqi)
- pop: Practiced and taught in dedicated schools worldwide (Bella Diva, ODC Global Dance Passport, World Bellydance network); widely offered as both cultural-technique and fitness class internationally.
- feas: ✅ feasible — mostly standing, front-facing, subtle-but-trackable torso/hip isolations suit fixed camera well.
- curr: Progressive drills: isolations (hip, ribcage, shoulder), shimmy drills, undulations/waves, travel steps, then combos; advanced adds veil/zill (finger cymbal) work and layering.
- needs: Fine-grained torso/pelvis landmark precision for subtle isolations (shimmies are small, high-frequency movements) — may need higher-sensitivity smoothing tuned differently than large-movement styles.
- caveat: Props (veil, zills, sword) cannot be verified by the app — teach prop-free variations, demonstrate prop work via avatar only.
- url: https://belladivadance.com/classes/belly-dance/
### Bollywood Dance
- pop: DanceUS (major US dance-studio directory) expanded specifically in 2026 to add Bollywood and K-pop as 'exploding global sensations,' confirming rising instructor/studio supply-side demand.
- feas: ✅ feasible — full-body, front-facing, standing choreography suits fixed camera; hand-gesture precision (mudras) trackable via hand landmark models if the pipeline includes hand pose alongside body pose.
- curr: Named hand-gesture vocabulary borrowed from classical forms, film-choreography combo teaching (mirrored step-by-step, common on YouTube channels), Bollywood-fitness fusion classes.
- needs: Hand/finger landmark tracking in addition to 33-point body pose if precise mudra scoring is desired; otherwise gesture teaching can be avatar-demo-only.
- caveat: Specific film choreography is copyrighted by production studios — teach original Bollywood-style combos, not verbatim movie routines.
- url: https://markets.financialcontent.com/postgazette/article/abnewswire-2026-3-5-danceus-expands-directory-to-include-exploding-global-sensations-k-pop-and-bollywood-dance
### Twerk
- pop: Consistently offered as a dedicated class category at commercial urban-dance studios internationally (often bundled with heels/twerk fitness programming); thin independent quantitative stats.
- feas: ⚠️ feasible-with-constraints — standing/squat twerk technique is trackable via hip/pelvis landmarks from a front or 3/4 camera angle; low-squat and floor-based variants risk lower-body occlusion by the torso from a straight-front angle, so app should recommend a slight side or 3/4 camera placement f
- curr: Isolated glute/hip bounce drills, squat-stance variations, transitions from standing to floor-adjacent positions, building to combos.
- needs: Camera-angle guidance differing from the default front-on setup (3/4 angle recommended) to keep hip landmarks visible during deep squat positions.
- caveat: Content/community-guideline sensitivity — ensure in-app framing stays technique/fitness-focused and platform store policies (App Store/Play) around this content category are review
- url: https://dancemagazine.com/heels-dance-popularity/
### Heels Dance
- pop: Dance Magazine and multiple dedicated studio blogs (Madhouse, Werkflow, Sheydance) confirm heels classes are now a standard offering at commercial dance studios worldwide, driven by TikTok/Instagram visibility of heels c
- feas: ⚠️ feasible-with-constraints — full choreography is trackable via standard body pose, but the app cannot verify footwear or floor safety; balance/ankle-stability risk is real and elevated versus barefoot/sneaker styles.
- curr: Builds from jazz/lyrical/hip-hop vocabulary; teaches heel-specific posture, weight placement, and controlled turns before adding full choreography.
- needs: Mandatory in-app safety module: purpose-built dance heels recommended (not fashion heels), non-slip flooring check, warm-up requirement before class start — answering founder's explicit question, yes, heels demands dedicated footwear safety notes.
- caveat: Should include an injury-risk disclaimer given documented ankle/balance risk in heels dance literature; app cannot detect improper footwear, only prompt/remind.
- url: https://madewildr.com/articles/best-shoes-for-heels-dance-class
### Tango (solo technique/styling)
- pop: Tango solo-technique classes are a standard, long-established offering at tango schools worldwide (a recognized pedagogical category, not a niche invention) — evidenced by decades of tango-community technique-class discu
- feas: ✅ feasible for solo technique drills (walking, ochos, giros in place) — standing, front/side-facing, trackable via hip/leg landmarks; ⚠️ full social tango obviously requires a partner and is out of scope.
- curr: Named elements: caminata (walking technique), ochos (figure-eight pivots), giros (circular turns), disociación (torso-hip dissociation) all practiced solo before partner application.
- needs: Torso-hip dissociation scoring benefits from separate shoulder-line vs. hip-line angle tracking (a signature tango technical marker).
- caveat: Scope must stay strictly to solo technique/styling per founder's framing — do not attempt to simulate partner connection/embrace mechanics.
- url: https://mailman.mit.edu/pipermail/tango-l/2008-June/008513.html
### Kizomba/Zouk (solo styling)
- pop: Both kizomba and Brazilian zouk have expanding international festival/congress circuits across Europe, Americas, and Asia (comparable pattern to bachata's global growth); solo-styling classes are a known, established off
- feas: ✅ feasible for isolations/footwork styling; ⚠️ cambré/backbend elements need flexibility caution flagging (not a camera limitation but a safety one) since deep backbends carry spinal strain risk for untrained users.
- curr: Body isolations, chest/ribcage rolls, cambré (backbend/lean) technique, footwork styling — taught solo as prerequisite/complement to partner dancing, following the same pedagogical pattern as bachata solo styling.
- needs: Flexibility/safety gating — cambré depth should be user-paced with an in-app caution rather than pushed via scoring pressure.
- caveat: Evidence for this item is thinner/more qualitative than salsa/bachata — flag as moderate-confidence popularity claim pending firmer market data.
- url: https://www.residentadvisor.net/features/3623
### Line Dance / Country
- pop: Long-established global social-dance category with dedicated organizations (e.g., World Line Dance, UCWDC) running competitions and step-sheet libraries internationally; strong in North America, UK, and increasingly popu
- feas: ✅ feasible — explicitly designed to be danced solo/individually, standing, front-facing, ideal single-camera fit; arguably the easiest style in the catalog to encode as deterministic rules given standardized step-sheet notation.
- curr: Standardized 'step sheets' (named sequences of counts and directions — grapevine, vine, kick-ball-change, jazz box) that are the actual industry teaching format — maps directly onto an 8-count rule-engine app.
- needs: None beyond standard full-body tracking; step-sheet notation format is a gift for a rule-engine architecture.
- caveat: Named published step sheets are often choreographer-copyrighted — build original step sequences using the same named-step vocabulary rather than reproducing a specific published st
- url: https://en.wikipedia.org/wiki/Line_dance
### Zumba-style Fitness Dance
- pop: 15 million weekly participants across 200,000 locations in 189 countries; 465M+ live classes taught historically — among the strongest quantitative popularity evidence in this entire catalog.
- feas: ✅ feasible — full-body, standing, front-facing cardio choreography is the best-suited format in the catalog for on-device pose tracking and real-time voice coaching (fitness-cue delivery is a Zumba-class staple already).
- curr: Not a formal step-syllabus but a certified-instructor choreography format (Zumba Basic/Gold licensing) blending base rhythms (salsa, reggaeton, cumbia, merengue) into repeatable song-length routines.
- needs: None beyond standard pipeline; strong candidate for early wave given feasibility + evidence strength.
- caveat: 'Zumba' itself is a trademarked brand/certification — app must build 'Zumba-style' generic Latin-fusion fitness choreography, not use the Zumba name or licensed choreography.
- url: https://www.prnewswire.com/news-releases/zumba-turns-25-and-the-party-spanned-the-glaobe-302759109.html
### TikTok-Trend Choreo (generic, non-attributed)
- pop: TikTok dance trends routinely generate hundreds of millions of views/uses per trending sound (well-documented pattern across Afrobeats crazes, shuffle tutorials, and viral challenge formats cited above); the format itsel
- feas: ✅ feasible — short, standing, front-facing, single-person format is maximally camera-friendly and was essentially designed for phone-camera self-recording.
- curr: No fixed syllabus — trend format is short repeatable phrase + freestyle tag; app should teach the format/skill (learning any short viral-style combo quickly) using original in-house-choreographed combos rather than copying specific trending routines.
- needs: None; this is the format most naturally aligned with existing phone-camera dance culture.
- caveat: HIGH legal-caution item: specific named viral choreographies (e.g., a specific creator's exact TikTok routine set to a specific song) are frequently disputed IP and several creator
- url: https://www.tiktok.com/discover/melbourne-shuffle-tutorial


# ==== gravita-scope ====

## SUMMARY
Gravita full-scope catalog: 13 items spanning mass-market form coaching (push-up/pull-up/dip/squat/lunge/plank/burpee) through the full calisthenics skill tree (handstand family, planche, front/back lever, muscle-up, L-sit/V-sit/Manna, pistol squat, human flag, bridge/backbend, crow transition, rings). Handstand and planche have the strongest checkable evidence (named GMB/FitnessFAQs progression trees). Bar-based dynamic skills (muscle-up, ring muscle-up) carry a real, named technical constraint: explosive-transition motion blur on phone cameras plus doorway-bar framing/occlusion, requiring phase-based (not continuous) tracking and a dedicated bar/edge-detection layer beyond plain MediaPipe pose estimation. Human flag requires a vertical pole most home users won't own — equipment-access is the limiter, not camera feasibility. One-arm handstand and Manna are kept in-scope as physically achievable (not banned) but must be framed as aspirational/guided content, not gamified milestones, given elite-only attainability and fall/injury risk. Flips, aerials, and any move requiring partner contact or force measurement are excluded per the hard safety filter (none were in the domain scope anyway). Popularity evidence is moderate-to-good for named skills (multiple independent coaching brands each publish full progression trees) but thin on hard participation numbers — no single authoritative global calisthenics-participant count was found; search-interest and media-coverage proxies were used instead and are flagged as such.

## RECOMMENDATIONS
- Wave 1 (mass market, cheap to build, zero equipment): push-up/pull-up/dip/squat/lunge/plank/burpee form coaching — highest demand, lowest technical risk, no bar-detection dependency.
- Wave 2 (flagship skills, floor/wall only): handstand progression (wall→freestanding→HSPU) and planche progression (tuck→straddle→full) — best-documented curricula, high demand, no bar-detection dependency, inverted-pose tracking already solved (D1).
- Wave 3 (bar-equipment skills, requires new bar/edge-detection R&D): front/back lever, muscle-up, pistol squat (no bar needed but pairs well here for 'skills' branding) — prototype bar/edge detection and phase-based transition tracking before committing to a ship date.
- Wave 4 (equipment-optional / niche): rings fundamentals, bridge/backbend, crow pose, L-sit/V-sit.
- Wave 5 (aspirational/guided-only, explicit non-milestone framing): one-arm handstand, Manna, human flag (flag additionally gated on vertical-pole equipment access, which most home users lack).
- Do not gamify or issue pass/fail badges for one-arm handstand, Manna, or the muscle-up explosive-transition phase — camera cannot reliably verify these at the precision implied by a 'mastered' claim; frame as progress-tracked guided practice instead.
- Prototype the bar/edge visual-anchor detector early and validate doorway-bar framing in real home settings (low ceiling, close wall) before finalizing Wave 3 scope — this is the single biggest unproven technical dependency in the whole roadmap.

## RISKS
- No single authoritative 'global calisthenics participants' statistic was found; popularity claims rely on proxies (search-interest trend reports, number of independent coaching brands publishing the same progression tree, mainstream media coverage) rather than a hard participation count — flag this to the founder as thin-evidence.
- One search result (2025 US Health & Fitness Consumer Report per Accio.com summary) indicates calisthenics participation may have *declined* even as search/content interest rose — this is a mixed signal worth surfacing rather than presenting demand as uniformly growing.
- Bar/edge detection for doorway pull-up bars is an unvalidated engineering assumption, not a benchmarked capability — could become a schedule risk for the entire Wave 3 (muscle-up, lever) if detection accuracy under home lighting/framing proves unreliable.
- Explosive-phase motion blur (muscle-up transition, ring muscle-up) means the app can only checkpoint before/after states, not truly score the transition itself — must be communicated honestly to users to avoid overselling 'form correction' during the fastest, most injury-relevant phase.
- One-arm handstand and Manna carry genuine fall/hyperextension injury risk during unsupervised solo practice with no spotter — even though not in the hard-excluded category (flips/aerials/partner-contact), the app should carry explicit safety disclaimers and avoid encouraging attempts without matting.
- Human flag's vertical-pole equipment requirement will exclude the large majority of home users who only own a horizontal doorway pull-up bar — scope/marketing should not imply flag training is broadly accessible.

## ITEMS
### Push-up / Pull-up / Dip / Squat / Lunge / Plank / Burpee — mass-market form coaching + rep counting
- pop: Highest possible demand tier — push-up/pull-up/squat are the top three searched bodyweight exercises worldwide and the default content of nearly every fitness app; see pull-up strength-standard demand pages.
- feas: ✅ feasible — single camera, single person, deterministic joint-angle/ROM rules (elbow angle, hip-line angle, knee valgus) map cleanly to MediaPipe's 33 landmarks; burpee is a multi-phase state machine but still fits one static frame.
- curr: No single 'named' curriculum — standards are aggregated from lifting/strength databases (e.g. StrengthLevel push-up/pull-up percentile tables) and NASM/ACE personal-trainer form checklists; rep-standard tables exist per movement (see Liftoff/AthleteP
- needs: Rep-counter state machine (down→up→down) per movement; angle thresholds calibrated per movement; camera-angle guidance UI (user must self-position) since single fixed phone camera has no auto-framing.
- caveat: Burpee jump phase can motion-blur at high rep speed on cheap phone cameras in low light; plank is a hold not a rep-count so needs a timer/posture-drift rule instead.
- url: https://www.strengthlevel.com/strength-standards/push-up
### Wall Handstand → Freestanding Handstand → Handstand Push-up (HSPU) progression
- pop: Handstand is consistently the top-searched calisthenics skill across multiple guide sites (FitnessFAQs, GMB, fit.gg, Fitloop) — evidenced by at least 5 independent major coaching brands each publishing a dedicated full p
- feas: ✅ feasible for wall/freestanding balance and static HSPU with camera positioned to capture full inverted body — MediaPipe pose estimation on inverted bodies is a solved D1 problem per your own directive; ⚠️ constrained for kicking-up framing (user must self-frame far enough back, and the moment of k
- curr: Named progression trees exist from FitnessFAQs (Handstand Pro product) and GMB Fitness's free handstand guide, and Calisthenics-101's step-by-step wall-to-freestanding tree.
- needs: Inverted-pose landmark mapping (already D1-solved per directive); balance-drift/wobble detection for real-time voice cueing (e.g., 'hips back' when spine arches); camera-framing guidance so kick-up doesn't leave frame.
- caveat: None major — best-evidenced item in the whole catalog with multiple named, checkable curricula.
- url: https://gmb.io/handstand/
### One-Arm Handstand (OAHS) — guided content only, no mastery claim
- pop: High content/aspirational demand as the apex skill in every handstand progression series, but actual achieving population is small — treat as long-tail engagement content, not a core milestone.
- feas: ⚠️ feasible-with-constraints: single camera can track the balance drills and offset-hand positioning fine, but this is an elite-tier skill with real fall/wrist-injury risk during freestanding attempts; app must present it as guided practice content with strong safety framing (crash mats, spotter-fre
- curr: BergMovement and FitnessFAQs both publish structured OAHS drill breakdowns as an extension of the freestanding handstand tree.
- needs: Same inverted pose tracking as two-arm handstand; needs explicit in-app safety disclaimers and liability framing (see risks) given fall potential even though it's not banned outright like flips.
- caveat: Founder directive requires 'no illogical/impossible' content — OAHS is physically achievable (not impossible), so it can be included, but must not be oversold as a short-timeline o
- url: https://www.bergmovement.com/calisthenics-blog/one-arm-handstand-drills-and-progressions-beginner
### Planche progression (tuck → advanced tuck → straddle → full planche)
- pop: Consistently featured as a top skill across GMB, FitnessFAQs, and mainstream calisthenics media alongside the handstand and front lever — strong evidence via GMB's dedicated free program page.
- feas: ✅ feasible for a fixed side-on camera — planche is a static/near-static straight-arm hold, ideal for joint-angle (shoulder protraction, hip/hollow-body line, lean angle) rule-based scoring; no occlusion issue since the body stays largely in one plane facing the camera.
- curr: GMB Fitness publishes a free, named tuck-to-straddle planche program with a structured pathway (plank lean → tuck → straddle → full); this is a well-documented, checkable curriculum.
- needs: Lean-angle measurement relative to hand position; parallette use is optional so app should support both floor and parallette variants (parallette adds visible equipment context, doesn't change pose logic).
- caveat: None major beyond standard progression pacing (GMB itself warns tendons adapt slower than muscle — app should include built-in progression-gating/cool-down messaging, not push user
- url: https://gmb.io/planche/
### Front Lever & Back Lever progression (bar/rings)
- pop: Core skill in nearly every calisthenics roadmap and street-workout competition judging criteria (WSWCF-style events reference lever holds as scored elements).
- feas: ✅ feasible on a doorway/fixed pull-up bar with camera positioned side-on far enough back to capture full body length and the bar overhead — body stays in a single vertical plane under the bar, no occlusion from limbs crossing; ⚠️ minor constraint: user must frame camera to include both the bar and f
- curr: Part of the same named GMB Praxis curriculum and FitnessFAQs bar-skill progression trees used for planche/handstand.
- needs: Bar-position detection (see 'bar/edge detection' tech item below) so the app can anchor a reference line for body-to-bar angle scoring.
- caveat: Framing constraint is real for users with low ceilings/short rooms and a doorway bar — app should give explicit camera-distance setup instructions per body height.
- url: https://gmb.io/curriculum/
### Muscle-up (bar and ring) — explosive transition coaching
- pop: Headline bar skill referenced in mainstream press coverage of the street-calisthenics scene (Rolling Stone feature on street-calisthenics battles) and central to USA Streetlifting's expansion.
- feas: ⚠️ feasible-with-constraints: static grip/pull phases track fine, but the explosive transition phase (the moment the body rotates over the bar) is fast and can motion-blur on phone cameras, especially indoors under typical home lighting — app should rely on before/after phase landmarks (bottom hang,
- curr: Streetlifting-style progressions and rep-standard tables exist (Liftoff/AthletePath pull-up and weighted pull-up standards feed the strength prerequisite for muscle-up), plus named muscle-up-specific tutorials across FitnessFAQs/GMB libraries.
- needs: Same bar-position/edge-detection tech as lever; motion-blur-tolerant phase-based state machine (hang→pull→transition→support→dip) instead of continuous angle tracking through the blur-prone transition.
- caveat: Explosive-phase blur is a real, named technical limitation — be honest that the app coaches setup/strength prerequisites and phase checkpoints, not frame-by-frame transition form.
- url: https://www.rollingstone.com/culture/culture-features/toughest-workout-calisthenics-street-lifting-battles-1235577518/
### L-sit / V-sit / Manna progression
- pop: L-sit is a widely-taught staple (parallette/floor variants featured across nearly all bodyweight strength programs); Manna is niche/aspirational.
- feas: ✅ feasible for L-sit/V-sit — seated/supported static hold, fully visible to a front-facing fixed camera, clean joint-angle scoring (hip flexion, leg-parallel-to-floor angle); ⚠️ Manna is feasible-with-constraints only as guided/aspirational content given its extreme mobility requirement (near-elite 
- curr: Covered within the same named GMB Praxis / FitnessFAQs compression-strength progression trees as planche.
- needs: None beyond standard static-hold angle scoring; Manna should be flagged aspirational-tier like OAHS.
- caveat: Manna's back-flexibility requirement is a genuine outlier — do not gamify as an attainable milestone for general users; present as elite showcase content only.
- url: https://gmb.io/curriculum/
### Pistol squat (single-leg squat) progression
- pop: Consistently one of the most-searched 'skill squat' variations in bodyweight fitness content, positioned as the leg-day equivalent of the muscle-up.
- feas: ✅ feasible — single person, single fixed front/side camera, full body visible throughout the movement, clean knee-valgus and depth-angle tracking with MediaPipe.
- curr: Standard progression tables and standards exist on general strength-standard sites (StrengthLevel) and are taught within every mainstream calisthenics leg-strength curriculum.
- needs: None beyond standard rep/depth state machine.
- caveat: Balance wobble at the bottom can be confused with 'form break' by naive angle thresholds — needs a smoothing window, not a hard instant-fail rule.
- url: https://www.strengthlevel.com/strength-standards/pistol-squat
### Human flag (pole and vertical bar variants)
- pop: One of the most visually iconic and widely referenced 'advanced' street-workout skills in competitive and media coverage (street-workout park culture).
- feas: ⚠️ feasible-with-constraints: requires a genuinely vertical pole/post (not a standard doorway pull-up bar, which is horizontal) — most home users will lack a suitable vertical anchor; app can coach the skill for users with access to a street-workout park pole or vertical pull-up-station post, with c
- curr: Covered in the same named GMB Praxis / FitnessFAQs bar-skill trees as lever and planche; also a judged element in street-workout competitions.
- needs: Vertical-pole/edge detection (different geometry than horizontal-bar detection used for muscle-up/lever) — likely needs its own detection model rather than reusing horizontal-bar logic.
- caveat: Equipment-access is the real limiter, not camera feasibility — be explicit in-app that this requires an outdoor street-workout pole, most users won't have a suitable home anchor.
- url: https://gmb.io/curriculum/
### Bridge / Backbend flexibility & strength skills
- pop: Moderate-high — near-universal inclusion in gymnastics-based bodyweight programs as a complementary mobility skill, though less individually 'named-demand' than handstand/planche.
- feas: ✅ feasible for static bridge holds and wall-walk drills (single camera, full body visible, spine-curvature angle trackable via MediaPipe); ⚠️ constrained for the dynamic standing-to-bridge 'drop back' transition, which briefly inverts fast and risks landing-form errors the app can flag but not physi
- curr: Bridge/backbend drills are a standard module within gymnastic-strength curricula (GMB Elements/Integral Strength) alongside handstand training.
- needs: Spine-curvature angle estimation from a side-camera view; no new detection tech beyond standard pose landmarks.
- caveat: App should include a hard safety disclaimer for the drop-back transition (real fall-backward risk) — coach the hold and wall-assisted variants as the default path, treat free drop-
- url: https://gmb.io/curriculum/
### Crow pose → handstand transition (floor-to-inversion bridge skill)
- pop: Moderate — mainly relevant as a feeder skill rather than an independent high-demand target, but valuable for early-wave engagement/retention since it's achievable quickly.
- feas: ✅ feasible — low, compact static hold, fully visible to a fixed front camera, no occlusion.
- curr: Taught as a standard entry drill within combined yoga/calisthenics handstand progression guides (e.g., Omstars' handstand progression guide covers crow as a foundational step).
- needs: None beyond standard static-hold tracking.
- caveat: Overlaps with yoga-app content category — should be framed as a calisthenics stepping-stone, not core Gravita content, to avoid scope creep into yoga.
- url: https://omstars.com/blog/practice/mastering-handstand-a-step-by-step-progression-guide/
### Ring-based fundamentals (support hold, ring dip, ring row, ring muscle-up variant)
- pop: Moderate-high — rings are one of the most commonly purchased home calisthenics accessories precisely because they're portable and doorway-mountable, giving a built-in existing user base.
- feas: ⚠️ feasible-with-constraints: rings swing and rotate under load, adding instability the pose model must tolerate (more landmark jitter than a fixed bar); camera framing needs both rings and full hanging body height, same wide-shot requirement as bar skills; ring muscle-up transition has the same exp
- curr: Rings fundamentals are part of the same GMB Elements/Integral Strength named curricula and widely taught by ring-specific coaches (e.g., GymnasticBodies-style ring progressions referenced in GMB's own review of Gymnastic Bodies).
- needs: Instability-tolerant pose smoothing (rings swing); same wide-framing and bar-motion-blur handling as bar muscle-up.
- caveat: Should be scoped as an equipment-optional advanced module, not core wave-1 content, given the added instability complexity relative to fixed-bar skills.
- url: https://gmb.io/curriculum/
### Bar/edge visual anchor detection for pull-up-bar skills (special tech requirement)
- pop: N/A — infrastructure item.
- feas: ⚠️ feasible-with-constraints: requires an additional lightweight object/edge-detection step (not pure pose-landmark tracking) to anchor the bar position in-frame, since MediaPipe's 33-point body model has no bar-awareness on its own; doorway bars are frequently mounted close to a wall/ceiling corner
- curr: N/A — this is an engineering requirement, not a taught skill.
- needs: Dedicated bar/edge object-detection model (e.g., simple line/rectangle detector) running alongside the MediaPipe pose pipeline, plus an in-app camera-setup calibration step where the user marks or the app auto-detects the bar before starting a sessio
- caveat: This is an engineering estimate, not a benchmarked claim — no public source directly validates bar-detection accuracy for this exact use case; treat as an R&D risk item to prototyp
- url: https://gmb.io/curriculum/


# ==== lissom-scope ====

## SUMMARY
Full-scope research for Lissom (Yula Motion mobility/flexibility/yoga app) covering: (1) an expanded, camera-feasible assessment battery beyond V1's 8-10 tests, built around FMS-style tests where single-camera-measurable; (2) yoga style coverage ranked by real demand (Vinyasa/Hatha as top drivers, Yin/Restorative fast-growing, chair yoga surging, prenatal medically gated) with a tiered definition of 'complete' pose library (84 classical → 900+ exhaustive); (3) flexibility goal programs (splits, backbend, openers) modeled on the proven 30-day-challenge and Pliability 'paths' patterns, with camera-based angle-trend tracking as a genuine differentiator; (4) population packs for desk workers, runners, lifters, and seniors (fall-risk-aware, camera-validated single-leg-stance testing has real academic backing) — with kids explicitly flagged as NOT recommended due to liability/model-validation concerns, not a technical filter; (5) cross-family warmup/recovery packs feeding JabLab, Choreia, and Gravita as an in-family cross-sell strategy mirroring Pliability's own sport-content broadening; (6) breathwork/meditation recommended as audio-only guided content bundled alongside physical practice, explicitly without any camera-based biometric measurement claims, since chest-rise pose tracking cannot reliably measure respiration.

## RECOMMENDATIONS
- Wave 1: Core assessment battery expansion (single-leg stance, ASLR, overhead squat, plank/rotary stability) + Hatha/Vinyasa/Yin style trio + splits/hip/hamstring flexibility-goal programs — these have the strongest camera feasibility and clearest demand evidence.
- Wave 2: Chair/Office yoga + desk-worker, runner, lifter population packs + backbend/shoulder-opening goal programs — moderate build complexity, strong demand signal (chair yoga search growth, 80% desk-worker pain stat).
- Wave 3: Ashtanga primary-series basics + cross-family warmup packs (JabLab/Choreia/Gravita deep links) + audio-only breathwork/meditation bookends — lower technical risk, portfolio-strategy value.
- Wave 4 / cautious-last: Senior mobility pack (ship only with explicit non-diagnostic, consult-your-doctor gating language) and Prenatal yoga (ship only with hard medical-clearance gate and a curated 'safe pose only' subset, avoiding backbends/deep twists/supine-after-20-weeks per ACOG-aligned guidance).
- Do NOT build a Kids pack under current single-founder compliance/liability capacity — pose models are adult-validated and minor-safety obligations are out of scope; revisit only with dedicated legal/compliance review.
- Do NOT attempt camera-based breath-rate or meditation-depth measurement — ship breathwork/meditation as passive audio-guided content only, reusing the existing voice-coaching pipeline.
- Frame the assessment battery explicitly as a wellness screen, never as a clinical FMS-equivalent or diagnostic fall-risk tool, given no published validation of MediaPipe-based scoring against certified human graders.

## RISKS
- MediaPipe pose accuracy degrades meaningfully on floor/supine work and during fast motion (Vinyasa flow, quick transitions) — angle error is lowest for standing static holds and highest for ground/lying positions, so any 'per-pose correction' promise must be scoped down or disclaimed for floor and flow content.
- No independent academic validation exists for phone-camera-based FMS-style scoring or fall-risk single-leg-stance apps matching clinical-grade agreement — marketing language must avoid clinical/diagnostic claims (FMS is a certified-practitioner tool; camera version is a proxy).
- Senior and prenatal packs carry real safety/liability exposure if pose cueing or automated coaching is wrong (fall injury, pregnancy complication) — both need conservative, disclaimer-gated, non-diagnostic product framing, and prenatal specifically needs a curated safe-pose subset (no deep backbends/twists/supine after 20 weeks per ACOG-aligned sources).
- Evidence quality is uneven: yoga-style popularity and splits-app-demand claims are drawn largely from SEO/blog aggregator sites and app-store listings rather than primary market-research firms — treat participation numbers (e.g. '300M+ practitioners') as industry-consensus estimates, not audited data.
- Kids as a population pack fails the feasibility filter on liability/model-validation grounds, not physical camera limitation — including it in 'full scope' without flagging this would violate the founder's own honesty requirement.

## ITEMS
### Assessment Battery — Full Version (beyond V1's 8-10 tests)
- pop: FMS is the dominant real-world reference battery used by strength coaches/PTs worldwide; 7-test, 21-point structure is well documented and widely taught.
- feas: ⚠️ feasible-with-constraints — Deep Squat, Lunge, ASLR, single-leg stance, plank/rotary stability are single-camera measurable from a fixed side/front angle (frontal-plane sag, joint angles via MediaPipe landmarks). ❌ true FMS scoring (0-3 compensation grading incl. pain/quality judgments, hurdle-st
- curr: Graded battery: Upper (shoulder flexion/IR-ER proxy via behind-back reach visible extent, wall angel), Lower (hip hinge, ankle dorsiflexion lunge, ASLR), Spine (seated rotation, cat-cow ROM, standing lateral flexion), Balance (single-leg eyes-open ti
- needs: Side-view + front-view dual capture (user repositions phone or app prompts two takes); temporal landmark smoothing for hold-based tests (plank sag, single-leg stance sway); simple sway/COM proxy from hip landmark jitter for balance scoring.
- caveat: No published validation of MediaPipe-based scoring matching certified FMS grader agreement — treat as a wellness proxy screen, not a clinical/return-to-play FMS substitute; avoid u
- url: https://www.bodyspec.com/blog/post/functional_movement_screen_fms_tests_scores_guide
### Yoga Style Coverage (global demand ranked)
- pop: 300M+ global regular practitioners (2025); Vinyasa/Hatha named top industry drivers, Yin/Restorative fast-growing, chair yoga ~60,500 monthly searches with 3.51% MoM growth; competitor Down Dog ships 10+ styles as its ba
- feas: ✅ feasible for standing/seated/kneeling asanas in all styles (frontal or 3/4 camera angle, static or slow-flow holds). ⚠️ feasible-with-constraints for floor/supine/prone asanas (occlusion of limbs against mat, depth ambiguity) and for fast Vinyasa flow transitions (motion blur, landmark lag during 
- curr: Beginner→Level1→Level2→Level3 progression per style (mirrors Down Dog's structure); 'Boost' targeted practices by body area (hips, shoulders, backbends, core — 15-19 areas per Down Dog precedent); style-specific pacing (Yin = 3-5 min holds ideal for 
- needs: Slow-hold detection (dwell-time state machine) works best; need a 'flow mode' that relaxes pose-accuracy scoring to rep/breath-cue coaching only during fast Vinyasa sequences rather than claiming per-pose correction.
- caveat: Bikram/hot yoga named as 'renewed interest' but is heat-dependent and outside app scope entirely (physical environment, not posture) — exclude or note as non-applicable.
- url: https://www.fitsri.com/articles/yoga-statistics
### Pose Library Scale — 'Complete' Definition
- pop: Classical canon = 84 asanas (Hatha Yoga Pradipika lineage); modern comprehensive charts run 900+ (Dharma Mittra 1984, 908 poses) establishing the outer bound of 'complete'.
- feas: ✅ feasible for the ~150-250 standing/seated/kneeling/prone-visible poses. ❌ not feasible for poses requiring headstand/handstand balance judgment via a single fixed low-angle phone camera (safety-critical inverted balance needs spotter/wall, camera can log attempt duration but not safely coach entry
- curr: Adopt Ashtanga's precedent structure (standing sequence → seated sequence → finishing sequence, ~49-75 postures with 35 vinyasas) as the backbone for Tier-1 sequencing; layer Tier-2 variations as unlockable content per Down Dog's leveling model.
- needs: None beyond Tier 1/2 camera pipeline; Tier 3 advanced/inversion poses should be marked 'skeleton-avatar demo only, not app-verified' rather than fully coached.
- caveat: No single authoritative 'complete' count exists industry-wide — framing as tiers is an editorial choice, flagged as such.
- url: https://yogajala.com/84-asanas/
### Flexibility Goals — Splits/Backbend/Opener Programs
- pop: Multiple dedicated splits-challenge apps sustain presence on both app stores (evidence of durable niche demand); Pliability explicitly ships 'achieving the splits' as a named path; the broader flexibility-app category (B
- feas: ✅ feasible — splits, hamstring/hip stretches, shoulder openers are floor/standing static holds in the camera's frontal or side plane, well suited to angle-based progress measurement. ⚠️ feasible-with-constraints for backbend (Wheel pose): full inverted spinal extension is visible but the camera cann
- curr: Mirrors Pliability's 'paths' model: named multi-day objective-based series (e.g. 'Path to Splits') with a body-area daily focus, 5-30 min sessions; progress dashboard showing measured joint-angle trend over the program.
- needs: Angle-trend charting over weeks (store historical joint-angle snapshots per session) as the core value-add differentiator; safety gating that halts progression cues if pain/form-break flagged.
- caveat: Splits app reviews are consumer blog-level evidence (Medium piece), not rigorous market-size data — genuine demand is inferred from multiplicity of competing apps, not hard numbers
- url: https://medium.com/@margotcox/i-tried-the-best-splits-training-apps-here-are-my-key-takeaways-764e173e2ca3
### Population Packs — Desk workers, Runners, Lifters, Seniors, Kids
- pop: Desk-worker: ~80% of desk workers report chronic pain, 9.5 avg sitting hrs/day (chair yoga demand evidence above). Senior fall-risk: single-leg stance validated in a systematic review meta-analysis as the strongest non-i
- feas: ✅ feasible for desk-worker, runner, lifter packs (standard standing/seated ROM and dynamic stretches, well within single-camera pose tracking). ⚠️ feasible-with-constraints for seniors: single-leg stance and balance-trend tracking are camera-measurable and have real fall-risk-test precedent (single-
- curr: Pack = short (5-10 min) targeted routines addressing the population's dominant complaint pattern, cross-linked to the relevant assessment-battery test (e.g. senior pack opens with single-leg stance timed test, trend-tracked over weeks).
- needs: Senior pack needs explicit non-diagnostic disclaimer copy + a 'consult your doctor' gate before balance-challenge content; no special tech beyond standard pose pipeline.
- caveat: Kids pack explicitly NOT recommended for build — flagged as a directive-scope item that fails the safety/liability feasibility filter, not a technical camera limitation.
- url: https://wellwork.yoga/why-interest-in-chair-yoga-is-surging/
### Cross-Family Recovery/Warmup Packs (in-family cross-sell)
- pop: Pliability itself models this exact strategy — 'sport-specific content' expansion beyond its CrossFit-only origin is cited as its core broadening-appeal feature, validating the cross-sell content pattern.
- feas: ✅ feasible — all are standard standing/floor mobility drills already covered by the flexibility-goals and population-pack pipelines above; no new camera capability required, purely a content/curriculum packaging exercise addressed to each sibling app's audience.
- curr: Short (5-8 min) pre/post-session routines timed to precede or follow a session in the sibling app; deep-linkable from JabLab/Choreia/Gravita as a 'warm up with Lissom' cross-app entry point.
- needs: Deep-link/handoff UX between sibling apps (App-to-App URL scheme) rather than a new capability; no additional ML.
- caveat: None beyond standard inter-app engineering; this is a business/packaging recommendation more than a research-evidence item.
- url: https://pliability.com/
### Breathwork / Meditation Adjacency
- pop: Pliability bundles breathwork into its core stated value prop ('guided stretching, mobility, breathwork, and recovery'); Bend and Down Dog do not foreground breathwork/meditation as a pillar, focusing on movement — indic
- feas: ✅ feasible as passive audio-guided content (no camera measurement needed, zero technical risk) — this is the only feasible framing. ❌ not feasible/not advisable to build camera-based breath-rate or meditation-depth detection: chest/abdomen rise-fall via pose landmarks is unreliable for respiratory r
- curr: Position as optional 2-5 min bookend content (pre-practice breath-settling, post-practice cooldown meditation) rather than a primary pillar; audio-only, narrator-led, no pose tracking, no biometric claims — same non-measurement pattern the app alread
- needs: None — pure audio content, reuses existing voice-coaching narration pipeline.
- caveat: Evidence for competitor breathwork inclusion is from marketing copy/app-store descriptions, not independent verification of feature depth.
- url: https://pliability.com/


# ==== complete-product-features ====

## SUMMARY
Compiled a URL-checkable, feasibility-filtered COMPLETE-PRODUCT CHECKLIST for the 5 Yula Motion apps: 14 shared table-stakes/ecosystem items (onboarding, courses/daily plan, streaks/challenges, progress stats, reminders, offline, settings, paywall, referral, HealthKit/Health Connect via the Flutter `health` package, watch/widgets/Live Activities as HR-and-timer-only companions, leaderboards/community explicitly deferred per family rule but confirmed as a real 2026 STEEZY feature being traded off, content cadence reality check, and review-prompt/ASO naming) plus 5 per-app deltas (Ostinato teacher-share, Choreia music picker, JabLab round timer/shadowboxing, Lissom re-test cycle, Gravita skill tree). Every item carries a checkable URL. One item fails the hard feasibility filter outright: a free/open music picker for Choreia is ❌ not feasible without licensing (STEEZY itself avoids this by pairing fixed licensed tracks to routines) — flagged as the audit's single hardest constraint. Several items are ⚠️ with named physical constraints: watch = HR/timer companion only (no on-device camera), boxing "power" scoring is velocity-proxy not force, mobility ROM tests are less reliable for axial/rotational planes (camera depth ambiguity) than camera-facing planes, and calisthenics static-hold skills (planche/handstand) need skill-specific camera angles due to self-occlusion.

## RECOMMENDATIONS
- Treat the checklist items 1-14 as a single shared platform layer to build once and reuse across all 5 apps (onboarding, streaks, HealthKit/Health Connect, review prompts, referral) rather than rebuilding per app — this is the actual leverage point for a solo founder shipping 5 products.
- Defer leaderboards/community (item 12) per the existing family rule, but track STEEZY's Challenges+leaderboard feature as a monitored competitive gap, not an ignored one — revisit only after V1 traction data exists.
- Resolve Choreia's music-picker legal gap before any wave touches it: either budget for a licensed royalty-free music library with BPM-sync, or restrict to the user's own on-device library for private practice only with no export-with-audio.
- For Lissom and Gravita, design camera-angle-specific onboarding prompts per test/skill rather than assuming one fixed camera angle works for all movements — this directly follows from the single-camera 2D-projection constraint.
- Build a semi-automated reference-consensus tool (align >=3 public instructor videos into a landmark consensus) as the single highest-leverage infrastructure investment, since manual content cadence at STEEZY's pace (~3 classes/week) is not sustainable solo across 5 apps.
- Scope JabLab's 'power' scoring language carefully in-app and in ASO copy — competitors market it as power/speed but it is a velocity-based proxy, not a validated force measurement; avoid overclaiming to prevent both user distrust and potential store-review/health-claim scrutiny.

## RISKS
- Choreia music-picker as originally scoped ('music picker' implying free song search) is legally infeasible without sync/master licensing — building it as-briefed risks takedown/legal exposure; STEEZY's own product design (fixed licensed tracks per class) is evidence the market leader already worked around this the hard way.
- Single-camera 2D pose estimation has real, physics-based accuracy limits for depth/rotational movement (mobility ROM axial rotation, calisthenics planche/handstand side-view occlusion) — shipping unqualified accuracy claims for Lissom/Gravita risks user trust erosion when scores don't match how the user 'feels' their range of motion.
- Boxing punch-power/speed scoring (JabLab) mirrors marketing claims from competitors (COMBO AI) that are not independently validated against force-plate/glove-sensor ground truth — regulatory/health-claim risk if positioned as training-load guidance rather than a directional proxy.
- Apple's native review-prompt API is rate-limited (~3 prompts/year per app per longstanding platform policy); a naive 'ask after every good session' design across 5 apps will burn the budget fast and needs a shared prioritization rule.
- Content-cadence expectations set by full-scope competitors (STEEZY ~3 new classes/week) are not achievable solo across 5 apps without the reference-consensus automation tooling flagged in recommendations — under-resourcing this creates a credibility gap against the 'full-scope, complete product' founder directive.

## ITEMS
### 1. Onboarding + Goal Setting
- pop: Universal pattern across Yousician, STEEZY, GOWOD, Freeletics, NTC — see cited app reviews below.
- feas: ✅ feasible — pure UI/state, no camera/pose dependency.
- curr: n/a (product-flow feature, not a taught skill)
- needs: For Yula Motion: goal-picker must also capture camera placement/space check (tripod distance, lighting) since pose accuracy depends on framing — this is specific to camera-based coaching and not present in non-camera competitors.
- caveat: No direct 2026 stat on conversion lift; inferred from UX pattern consistency across all cited apps, not from a single quantified source.
- url: https://support.yousician.com/hc/en-us/articles/201558312-How-to-navigate-in-Yousician
### 2. Structured Courses + Daily Plan/Path
- pop: Yousician + GuitarTuna combined 20M MAU (Yousician company page); STEEZY 1.4M+ downloads, ~1,800 classes / 3 new per week.
- feas: ✅ feasible on-device — path logic is a deterministic state machine over completed sessions, exactly the stack YULA already uses.
- curr: Yousician: instrument tracks with numbered levels + stars/minutes goal per session. STEEZY: named 'programs' with weekly structure. GOWOD: daily routine generated from mobility-test results.
- needs: None beyond existing rule-engine architecture.
- caveat: Yousician's 20M figure is combined across two products (Yousician + GuitarTuna), not Yousician alone — treat as upper bound.
- url: https://yousician.com/company
### 3. Streaks / Achievements / Challenges
- pop: Confirmed shipped in 2026 across STEEZY, Yousician, NTC per cited sources.
- feas: ✅ feasible — local state machine, no network/social dependency required for streaks/badges (leaderboard component is the one that needs backend + is optional, see item 12).
- curr: STEEZY: streak counter + new Challenges feature (badges + Top-10 leaderboard). Yousician: Streaks tab (weekly play count) + weekly challenges. NTC: streak badges + 'trying new workout' badges.
- needs: None for streak/achievement layer; leaderboard variant needs backend (see item 12 — family rule defers this).
- caveat: n/a
- url: https://www.steezy.co/
### 4. Progress Stats & History Charts
- pop: Cited as a standout retention driver in third-party GOWOD reviews.
- feas: ✅ feasible — all inputs (rep counts, ROM angle estimates from pose landmarks, punch counts, note-accuracy scores) are already computed on-device by the rule engines.
- curr: GOWOD assessment scores 5 areas (shoulders, overhead, hips, posterior chain, ankles), flags L/R imbalance, monthly retest cadence.
- needs: For Lissom specifically: needs a repeatable, camera-measurable ROM test protocol per joint — feasible since MediaPipe landmark angles are consistent frame to frame, but accuracy is single-camera/2D-projection limited (see item 18).
- caveat: 'Reset test' capability referenced but retest cadence (monthly) is anecdotal from one review site, not GOWOD's own docs.
- url: https://www.gowod.app/faq
### 5. Reminders / Notifications
- pop: Universal; not separately sourced beyond general ASO guidance below.
- feas: ✅ feasible — Flutter local_notifications / OS scheduling APIs, fully on-device, no server required for basic reminders.
- curr: n/a
- needs: None.
- caveat: n/a
- url: https://www.apptweak.com/en/aso-blog/app-store-reviews
### 6. Offline Mode
- pop: Common competitor feature (Yousician, STEEZY both support downloaded lesson content offline per general app-store listings).
- feas: ✅ feasible — on-device pose analysis already has zero network dependency; only remote assets (instructor videos, reference clips) need pre-download/caching.
- curr: n/a
- needs: Local storage budget for cached instructor/reference videos per app; needs cache-eviction policy.
- caveat: Not independently verified per-app in 2026 app-store copy during this pass — inferred from category norm.
- url: https://pub.dev/packages/health
### 7. Settings / Profile / Account Management
- pop: n/a — App Store/Play policy requirement, not a differentiator.
- feas: ✅ feasible — standard CRUD screens.
- curr: n/a
- needs: Must expose an in-app account-deletion path (Apple/Google mandate) and, since raw video never leaves device, a clear 'what data is stored' disclosure to preempt privacy-review friction.
- caveat: n/a
- url: https://developer.apple.com/app-store/review/guidelines/
### 8. Paywall / Subscription Management
- pop: Freeletics: ~£6.99/mo (~£84/yr annual) with nutrition sold separately. NTC: fully free, no paywall.
- feas: ✅ feasible — standard IAP/StoreKit + Play Billing integration.
- curr: n/a
- needs: None beyond standard IAP; per user's own hard rule this is a 'riskly class' (IAP/para) requiring Fable + Opus review before shipping, per workspace policy — not a technical constraint.
- caveat: Pricing figures from a third-party review site, not Freeletics' own pricing page — treat as approximate/point-in-time.
- url: https://fitnesstoolsreviewed.com/app-reviews/freeletics-review-is-the-ai-training-app-worth-it/
### 9. Referral / Share Cards
- pop: Strava & MyFitnessPal referral mechanics documented; ClassPass/CycleBar use similar link-based invite flows.
- feas: ✅ feasible — share-card rendering + deep link, no persistent social graph required (unlike a leaderboard/community feature).
- curr: n/a
- needs: None — this satisfies growth-loop need without building the social graph the family rule excludes.
- caveat: Fitness examples cited are mostly non-app-native community platforms (gyms/ClassPass); direct 1:1 in-app fitness-app referral case studies are thinner than gym-referral ones.
- url: https://growsurf.com/examples/fitness-app-referral-programs/
### 10. Apple Health / Google Fit (HealthKit / Health Connect) Write-back
- pop: Standard in NTC, Fitbod, Apple Fitness+-adjacent apps per cited comparison roundups.
- feas: ✅ feasible — the `health` Flutter package (pub.dev) wraps HealthKit (iOS) and Health Connect (Android) and supports `writeWorkout`/`writeHealthData`; MIT-licensed, actively maintained (v13.3.0). Google Fit API itself is deprecated (no new signups since May 2024) and the package dropped Google Fit su
- curr: n/a
- needs: iOS: HealthKit entitlement + Info.plist usage strings + App Store review of health-data purpose. Android: Health Connect permission flow (Android 14+ system-level,13 via companion app) — no server component needed, all on-device writes.
- caveat: Package API surface (writeWorkoutData vs. writeWorkout naming) has shifted across major versions — pin version and re-check changelog before integrating.
- url: https://pub.dev/packages/health
### 11. Watch Companion / Widgets / Live Activities
- pop: Apple Fitness+, Fitloop (rest timers via Live Activity/Dynamic Island) cited as shipping this in 2026.
- feas: ⚠️ feasible-with-constraints — Live Activities/widgets are ✅ full-scope feasible (iOS ActivityKit, no camera needed, just timer/rep-count state pushed from phone). A watchOS app is ✅ feasible ONLY as a remote display (round timer, HR from watch sensor, start/stop control) — it CANNOT do pose analysi
- curr: Apple's cycling Live Activity pattern (workout metrics on a mounted iPhone) is the direct precedent for JabLab's round-timer-as-Live-Activity.
- needs: watchOS companion: HR streaming + haptic round-timer alerts only; do not attempt on-watch pose/vision. Effort is moderate (separate watchOS target + WatchConnectivity) vs. value that is real but secondary — recommend waving 2+ per app, not V1.
- caveat: No hard usage-share stat found for how many target users of niche coaching apps (boxing/dance/calisthenics/mobility/music) actually wear an Apple Watch during solo home sessions — 
- url: https://www.apple.com/newsroom/2026/01/stay-active-in-the-new-year-with-apple-watch/
### 12. Social: Leaderboards / Community
- pop: Confirmed live in STEEZY as of 2026; Yousician also runs weekly challenges (non-social ranking, personal-only).
- feas: ⚠️ feasible-with-constraints if built — technically straightforward (backend + ranking query) but explicitly OUT of scope per family rule; verdict here is about market reality, not buildability: deferring it is a real trade-off against a shipped 2026 competitor feature (STEEZY), not a strawman.
- curr: STEEZY Challenges: badges + Top-10 leaderboard, shipped 2026.
- needs: If ever revisited: needs backend user directory, anti-cheat on self-reported reps (camera-verified reps make YULA's leaderboard harder to game than competitors', which is an unclaimed differentiator worth flagging even while deferring).
- caveat: Recommendation to defer stays sound — no evidence in the sources that leaderboards are the primary driver of STEEZY's growth vs. its content library; it reads as a retention add-on
- url: https://www.steezy.co/
### 13. Content Cadence (new courses/challenges)
- pop: n/a (ops cadence, not user demand)
- feas: ⚠️ feasible-with-constraints — reference-extraction pipeline (pick 3+ public videos, build consensus skeleton) is repeatable but manual-labor-bound; realistic cadence for a solo founder is far below STEEZY's weekly pace — recommend wave-based content drops (e.g. monthly per app) rather than matching
- curr: STEEZY: 800–1,800 classes, ~3 new/week. Yousician: continuous song/lesson additions plus 2025-26 additions (AI Vocal Coach, Yousician Kids track) as bigger periodic feature waves rather than weekly content.
- needs: A semi-automated reference-consensus tool (align ≥3 instructor videos, extract landmark consensus) would be the single highest-leverage build to keep content cadence honest across 5 apps.
- caveat: STEEZY's 3-classes/week figure is a rounded estimate from third-party sources, not STEEZY's own release notes.
- url: https://www.steezy.co/
### 14. Review/Rating Prompts + ASO Feature Naming
- pop: General 2026 ASO guidance; Yousician's 'AI Vocal Coach' rename/feature-push cited as a concrete 2025-26 example of feature-as-keyword.
- feas: ✅ feasible — native OS review APIs, no camera dependency; naming is a copy decision.
- curr: n/a
- needs: Trigger logic should key off the deterministic rule-engine's 'positive session' signal (e.g., form-score above threshold, streak day N) rather than arbitrary session count.
- caveat: iOS's native prompt is rate-limited by Apple (max ~3/year) — plan trigger priority accordingly; not explicitly re-confirmed for 2026 in sources but is a longstanding platform limit
- url: https://www.apptweak.com/en/aso-blog/app-store-reviews
### 15. Ostinato delta: Teacher-Share / Side-by-Side Comparison
- pop: CoachNow and Onform are established categories (coach-athlete remote review tools), evidencing real demand for this exact workflow outside Yula Motion.
- feas: ⚠️ feasible-with-constraints — side-by-side skeleton-overlay comparison of user vs. reference is ✅ feasible on-device (both are pose-landmark streams already computed locally). Sharing a raw video clip to an external teacher would breach the 'raw video never leaves device' rule; the constraint is ar
- curr: CoachNow: AI-enabled skeleton tracking + side-by-side 'Versus Mode'. Onform: AI skeleton tracking + slow-motion + side-by-side, used for golf/tennis coaching.
- needs: Needs an on-device video re-synthesis step (render skeleton/avatar over a neutral background) before export, to keep raw camera frames device-only per the architecture's hard privacy constraint.
- caveat: No public numbers on Ostinato's actual target instrument/domain were provided beyond the name — assumed music-instrument coaching per naming convention ('ostinato' = repeated music
- url: https://coachnow.com/video
### 16. Choreia delta: Music Picker for Choreography
- pop: STEEZY: 800–1,800 classes, each married to specific music — evidences that licensing constraints shape even the market leader's product design.
- feas: ❌ not feasible as a free 'pick any song' feature — using arbitrary copyrighted commercial music synced to a coaching product requires synchronization + master-use licensing (per-track deals or a licensed music library like Epidemic Sound/Musicbed), which STEEZY itself avoids by using its own commiss
- curr: STEEZY pairs each class with a specific licensed track chosen by the choreographer, not a searchable picker.
- needs: Requires either (a) licensing budget/negotiation for a music library, or (b) BPM-detection engine that syncs choreography timing to whatever track is already in the user's own device library (no redistribution) — the safer, cheaper path for a solo fo
- caveat: This is the one item in the whole audit that fails the hard feasibility filter as originally scoped ('music picker' implying open song search) — flagging explicitly per instruction
- url: https://www.billboard.com/pro/steezy-dance-app-choreographers-credit-revenue-viral-trends/
### 17. JabLab delta: Round Timer + Shadowboxing Pose Feedback
- pop: Multiple 2026 competitors in this exact niche (mAI Boxing Coach, COMBO AI, CornerMan AI, The Shadow Boxing App) — confirms real, validated category demand, not speculative.
- feas: ✅ feasible for shadowboxing/round-timer/form-scoring (stance, guard, footwork, punch mechanics) — COMBO AI explicitly advertises on-device pose tracking with no upload, no wearables, matching Yula Motion's architecture. ⚠️ feasible-with-constraints for punch-power/speed estimation — phone camera can
- curr: COMBO AI scores across power, speed, rhythm, footwork, accuracy, combos, endurance via on-device pose tracking. mAI Boxing Coach: instant feedback on stance/guard/footwork/punch mechanics.
- needs: Round-timer needs background-audio/haptic bell cues that survive screen-lock (Live Activity candidate, see item 11); punch-mechanics rule engine needs wrist/elbow angular-velocity thresholds tuned per weight class of punch (jab vs hook vs uppercut).
- caveat: 'Power' scoring claims by competitors (COMBO AI) are marketing copy, not independently validated against force-plate/glove-sensor ground truth — treat as directionally useful, not 
- url: https://getcombo.app/
### 18. Lissom delta: Re-test Cycle for Flexibility/Mobility
- pop: GOWOD explicitly reviewed as a top mobility app with this exact mechanic; competitor Pliability/Bend also use a scored, trackable metric ('Bendometer').
- feas: ⚠️ feasible-with-constraints — single-camera 2D pose landmarks can estimate joint angles reasonably well for sagittal-plane movements facing the camera (e.g. forward fold, overhead reach) but are less reliable for rotational/frontal-plane ROM (e.g. hip internal rotation, shoulder external rotation) 
- curr: GOWOD: 5-area test (shoulders, overhead position, hips, posterior chain, ankles), flags L/R asymmetry, generates a program from weakest links, retest to update.
- needs: Needs a camera-angle guide (on-screen silhouette) during the test to force users into the plane of motion the single camera can actually measure accurately.
- caveat: No public accuracy benchmark found comparing single-phone-camera MediaPipe ROM estimates against goniometer ground truth for this specific 5-area protocol — this is an assumption-f
- url: https://www.gowod.app/faq
### 19. Gravita delta: Skill Tree Progression (Calisthenics)
- pop: At least 4 distinct 2026 competitor apps built around this exact skill-tree mechanic (Calistack, Calistree, Caliprogressions, Calitree) — confirms genuine, non-niche demand.
- feas: ✅ feasible for rep-counting, hold-duration timing, and basic form-gating (e.g., full ROM pull-up, plank alignment) via on-device pose landmarks — this is squarely within MediaPipe's strength (limb angle + joint position over time, single person, controlled framing). ⚠️ feasible-with-constraints for 
- curr: Calistack: 4-category tree (Push/Pull/Core/Legs), unlocks next move only when ready. Caliprogressions: 6 movement categories toward one-arm pull-up/iron cross. Reported result: beginner tester went negatives→2 clean pull-ups in 4 weeks under a gate r
- needs: Per-skill camera-angle prompts (front vs. side) baked into the onboarding for that specific skill; rep-gating logic needs a 'clean rep' rule engine (full ROM + no kipping/momentum) distinct from a simple rep counter.
- caveat: The 4-weeks/negatives-to-2-pull-ups result is a single anecdotal tester report from a review article, not a controlled study — cite as illustrative, not proof of efficacy.
- url: https://play.google.com/store/apps/details?id=com.cali.stack&hl=en
