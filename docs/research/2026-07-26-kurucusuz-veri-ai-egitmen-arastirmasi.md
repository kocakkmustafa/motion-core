

# ==== nvidia-locateanything ====

## SUMMARY
NVIDIA LocateAnything is real: it is `nvidia/LocateAnything-3B`, a 3-billion-parameter vision-language grounding model released on Hugging Face in 2026 (research.nvidia.com/labs/lpr/locate-anything/, arXiv 2605.27365) that takes an image + natural-language prompt and outputs bounding boxes or points via a novel 'Parallel Box Decoding' technique, covering open-vocabulary/long-tail detection, referring-expression grounding, GUI-element grounding, and OCR/text localization. It is genuinely capable and directly on-topic for Ostinato's cello+bow localization problem — but it ships under a bespoke non-commercial-only 'NVIDIA License' (not the permissive NVIDIA Open Model License), restricting use to research/evaluation purposes with NVIDIA itself exempted. This almost certainly blocks its use anywhere in the Yula Motion commercial pipeline, including the 'offline auto-labeling on our own machine' scenario, since the resulting labels would feed a commercial product's training data. It is also far too large (3B params) for on-device mobile inference without unpublished NVIDIA distillation work — NVIDIA's own model card says embedded/on-device deployment is only 'possible with additional model optimization,' not ready today. Net recommendation: do not use LocateAnything in the actual product pipeline; stick with the family's current plan (MediaPipe Object Detector + Model Maker on-device, with Apache-2.0-licensed D-FINE or PaddleDetection-flavored RT-DETR — not the AGPL Ultralytics wrapper — as an offline teacher/auto-labeling model to bootstrap the Ostinato dataset).

## RECOMMENDATIONS
- Confirm: 'LocateAnything' is real — nvidia/LocateAnything-3B on Hugging Face, released ~2026, a 3B VLM for visual grounding (boxes/points from natural-language prompts), not a rumor or misremembered name.
- Do NOT use LocateAnything-3B anywhere in the Ostinato pipeline — including 'offline-only, runs on our machine' auto-labeling — until the founder gets explicit clarification (from NVIDIA or counsel) that using it to generate training labels for a commercial shipped app does not violate its 'non-commercial use only' clause. As written, the license restricts use of the Work (which plausibly includes its inference outputs when used to build a commercial asset) to research/evaluation purposes, with a real risk that auto-labeling for Ostinato's commercial training set counts as disqualified commercial use.
- For Ostinato's cello+bow on-device detection, stay on the current plan: MediaPipe Object Detector (Apache-2.0, mobile-ready today) fine-tuned via Model Maker, using D-FINE or PaddleDetection-license RT-DETR (Apache-2.0 checkpoints, NOT the Ultralytics AGPL wrapper) as an offline teacher/auto-labeling model to bootstrap the training set — this achieves the same 'better-than-YOLO-class auto-labeling' benefit the founder was hoping LocateAnything would provide, without the license risk.
- If curious, the founder can freely experiment with LocateAnything-3B's public HF Space demo purely for personal/research exploration (e.g., to gauge how well a large open-vocab grounder would localize a cello/bow, as a sanity check on label quality) — but any output must not enter the actual training/production pipeline given the license terms above.
- Re-check licensing on Qwen2.5-3B-Instruct (Qwen Research License) too if any Qwen-based components are ever considered elsewhere in the stack — it stacks a second non-commercial restriction on top of NVIDIA's own for LocateAnything specifically.

## RISKS
- License misinterpretation risk: 'non-commercial' VLM outputs used to train a commercial app's shipped model is a genuinely ambiguous legal question that has not been publicly addressed by NVIDIA for LocateAnything specifically — treat as prohibited until cleared, not as a gray area to route around.
- Model-name collision risk: 'RT-DETR' resolves to differently-licensed codebases (Apache-2.0 PaddleDetection original vs. AGPL/commercial-dual Ultralytics wrapper) — picking the wrong repo could silently introduce an AGPL dependency into offline tooling, which the family has flagged as banned even for internal machines per policy (though offline tooling has more license freedom per family memory, the family's own rule text says 'note license anyway' — so AGPL in offline tooling should at minimum be logged and consciously chosen, not accidental).
- Weight/size risk: LocateAnything-3B (3B params) is not on-device viable for phone-class Ostinato inference without NVIDIA-unpublished distillation/quantization work — do not plan around it becoming a shippable mobile model without significant unproven R&D investment.
- Evidence-thinness flag: claims that LocateAnything supports 'video' target pointing appear only in a secondary aggregator (HyperAI) headline, not corroborated by the primary Hugging Face model card, which describes image-only grounding — do not rely on video capability without further direct verification.

## ITEMS
### NVIDIA LocateAnything-3B
- what: A 3B-parameter vision-language model (VLM) for visual grounding: given an image (or GUI screenshot/document) and a natural-language prompt, it outputs structured coordinate tokens — bounding boxes `<box>x1,y1,x2,y2</box>` or points `<box>x,y</box>`. Architecture: MoonViT vision encoder (MIT-licensed) + Qwen2.5-3B-Instruct LM (Qwen Research License)
- why: This is exactly the model the founder heard about — it is real, current (released ~May-June 2026), and directly targets the open-vocabulary object localization problem Ostinato needs for cello+bow det
- license: "NVIDIA License" (a bespoke NVIDIA research license, NOT the permissive 'NVIDIA Open Model License' used by some other NVIDIA releases like Nemotron-4). Exact clause: "The Work and any derivative works thereof only may be used or intended for use non
- cost: Free to download (Hugging Face weights + GGUF community port), but the license forbids commercial use entirely — so 'free' does not translate into usa
- maturity: New (2026) research release from NVIDIA Research (Learning and Perception Research group), accompanied by an arXiv paper and a live Hugging Face Space
- integration: HF weights load like a standard VLM (transformers/vLLM style); a GGUF port exists for CPU/llama.cpp-style inference (community, unofficial: yuuko-eth/LocateAnything-3B-GGUF, and mudler/locate-anything
- caveats: CRITICAL LICENSE BLOCKER: the non-commercial clause almost certainly rules this out even for the 'offline auto-labeling on our own machine' use case the founder floated, because the labeled data would flow directly into training a shipped commercial app — that is a commercial use of the Work's output under most reasonable readings of 'use...non-com
- url: https://huggingface.co/nvidia/LocateAnything-3B
### MediaPipe Object Detector + Model Maker (current plan baseline)
- what: Google's on-device object detection solution: ships EfficientDet-Lite variants (Lite0/Lite2) pretrained on COCO (80 classes), with a Model Maker workflow to fine-tune on custom classes (e.g., cello, bow) using a labeled image dataset. Runs fully on-device (mobile CPU/GPU/NPU delegate) with low latency, matching the family's on-device/offline archit
- why: This remains the correct shipped-product choice for Ostinato's on-device cello+bow detection: it is Apache-2.0 licensed (fully commercial-safe, unlike LocateAnything), genuinely mobile-ready today (no
- license: Apache 2.0 (MediaPipe framework and Model Maker tooling) — fully compatible with a closed-source commercial app, no AGPL/GPL conflict.
- cost: ?
- maturity: Mature, widely deployed on-device solution with years of production use across Google and third-party apps.
- integration: Native Flutter/Android/iOS delegate support; already the family's baseline per current plan.
- caveats: EfficientDet-Lite backbone is meaningfully weaker on long-tail/open-vocabulary categories than modern DETR-class or VLM-grounding models — this is exactly the gap RT-DETR/D-FINE and (license permitting) NVIDIA-class labeling tools are meant to fill upstream in the DATASET, not at inference time.
- url: https://ai.google.dev/edge/mediapipe/solutions/vision/object_detector
### RT-DETR / D-FINE (offline auto-labeling / teacher-model candidates)
- what: Real-time DETR-family object detectors. D-FINE reformulates DETR's box regression as fine-grained distribution refinement with self-distillation (GO-LSD); reported figures: D-FINE-L ~54.0 AP (31M params, 91 GFLOPs, 8.07ms latency), D-FINE-X ~55.8 AP (62M params, 202 GFLOPs, 12.89ms). RT-DETR is the predecessor real-time DETR line ('DETRs Beat YOLOs
- why: These remain the strongest currently-usable candidates (already in the family's plan) for either (a) an offline teacher/labeling model to auto-annotate cello+bow frames before distilling into the on-d
- license: D-FINE (Peking University / official repo) — Apache 2.0. RT-DETR (Baidu/PaddlePaddle, and the widely used Ultralytics/HF ports) — check the specific repo: original PaddleDetection RT-DETR is Apache 2.0; Ultralytics' RT-DETR integration is licensed un
- cost: ?
- maturity: Established, peer-reviewed (CVPR/arXiv), widely benchmarked as of 2025-2026, e.g. RT-DETRv4 and RF-DETR follow-ons.
- integration: Runs offline on the founder's own machine (GPU recommended) purely as a labeling/teacher tool — never shipped in the app — consistent with the family's 'offline tooling has more license freedom' note,
- caveats: Verify exact license of whichever specific checkpoint/repo is pulled — 'RT-DETR' is used by multiple differently-licensed codebases (PaddleDetection Apache-2.0 vs. Ultralytics AGPL/commercial); do not assume the name alone guarantees Apache-2.0.
- url: https://arxiv.org/pdf/2410.13842


# ==== avatar-gen ====

## SUMMARY
Pose-driven open models (MimicMotion, AnimateAnyone/v2, Champ, MusePose, UniAnimate, EchoMimicV2/V3) exist and are actively developed through 2026, but every one has either an unresolved commercial-license question (MimicMotion likely inherits Stable Video Diffusion's non-commercial base license), unconfirmed/unreleased official weights (AnimateAnyone v1/v2), or a training-distribution mismatch with athletic full-body motion (dance/gesture/talking-head data, not handstands or boxing footwork). None have a published benchmark for teaching-grade anatomical accuracy on jabs, handstands, or yoga alignment — this is real, unaddressed white space, not just missing evidence. Consistent-character generation via FLUX.1/2-dev LoRA is the best visual-fidelity option but FLUX-dev's default license is NON-commercial (must route through BFL's paid API or buy an enterprise license); SDXL (CreativeML Open RAIL++-M) is the license-clean, lower-fidelity fallback. Paid closed tools (Kling Motion Control ~$0.07-0.11/s, Runway Gen-4 ~$0.12-0.25/s with best-reported 85-87% character consistency, Veo 3.1 API $0.05-0.40/s with no pose-conditioning found, HeyGen Avatar V ~$0.05/s optimized for talking/gesture not athletic form) all cost real money per clip and none has a demonstrated accuracy guarantee for teaching correct exercise form. EU AI Act Article 50 (binding from 2 Aug 2026) requires machine-readable marking of synthetic video AND a clear human-facing AI-disclosure label — guidance found suggests this applies even to a wholly fictional AI-instructor character, not just deepfakes of real people, which is an important and possibly under-appreciated compliance point for the family.

## RECOMMENDATIONS
- Do NOT adopt pose-driven open-model animation as the primary teaching-visual pipeline for V1 — run a small, cheap pilot first (pick 1 jab and 1 handstand reference skeleton, animate with MimicMotion or Champ on a rented A6000/4090, and have someone form-check the output against the real-instructor reference) before committing engineering time; anatomical fidelity on athletic extremes is the single biggest unverified risk in this whole landscape.
- If the pilot fails (likely, given no athletic-motion benchmarks exist for these models), the cheapest 'good enough' path is probably: (a) license/commission a small library of real stock/demonstrator footage per movement (one-time cost, ToS-clean, guaranteed anatomically correct) for the launch set of movements, and (b) reserve AI generation for lower-stakes teaching visuals (intro/outro character shots, encouragement clips, non-form-critical B-roll) where a Kling/Runway paid clip at $0.10-0.25/s is affordable and errors are cosmetic, not instructional.
- For the consistent-character 'look' of the instructor (face/body/studio), use SDXL + LoRA (clean commercial license, near-zero cost) rather than FLUX-dev self-hosted (non-commercial by default) unless you route through Black Forest Labs' paid API.
- Before writing a single line of the disclosure UI, get a real legal/compliance read on EU AI Act Art. 50 applicability to a synthetic (non-real-person) AI instructor character — the 'even if no real individual is depicted' language found in this research suggests disclosure is required regardless, which changes onboarding/UI copy requirements.
- Re-verify every 'unverified' license flagged above (MusePose, UniAnimate, MimicMotion's SVD-base dependency) directly against each repo's LICENSE file before any commercial commitment — this research pass could only confirm licenses for AnimateAnyone (Apache-2.0), Champ (Apache-2.0), EchoMimicV3 (Apache-2.0), FLUX-dev (non-commercial), and SDXL (Open RAIL++-M).

## RISKS
- No independent benchmark exists (found in this research) for pose-driven animation OR paid video-gen tools reproducing biomechanically correct athletic form (jab mechanics, handstand alignment, yoga pose depth) — shipping AI-generated demonstration visuals without a rigorous internal QA pass risks teaching visibly wrong form, which is a core product-integrity failure for a coaching app.
- MimicMotion's likely dependency on Stable Video Diffusion's non-commercial base license is a real legal trap: the Tencent repo code may be permissively licensed while the underlying pretrained weights it fine-tunes are not commercially licensed absent a separate Stability AI deal — do not ship without resolving this.
- FLUX.1/2-dev self-hosted commercial use is a common mistake in this space (the weights are free to download but explicitly non-commercial) — using them to generate the shipped 'AI instructor' character without an API/enterprise license would be a license violation.
- EU AI Act Article 50 enforcement begins 2 August 2026 (i.e., now/imminently relative to the current date) — shipping AI-generated instructor visuals into EU markets without machine-readable marking and clear disclosure is a compliance risk, not a future concern.
- All closed paid-API pricing found (Kling, Runway, Veo, HeyGen) is per-second and can compound quickly across a library of dozens of movements × multiple angle/variant takes needed to cover 5 apps' worth of content — 'as close to free as possible' budget constraint is hard to satisfy with any of the paid options at library scale; self-hosted open models remain the only path to near-zero marginal cost, but carry the unresolved license/quality risks above.
- Several claims in this report (UniAnimate license/VRAM, MusePose license, athletic-motion quality of any model) were not independently verified against primary sources within this research pass and are flagged accordingly — treat as leads requiring direct repo/ToS confirmation, not settled facts.

## ITEMS
### Tencent MimicMotion
- what: Diffusion-based pose-guided human video generation (image + DWPose skeleton sequence -> video). Confidence-aware pose guidance reduces distortion on high-motion limbs.
- why: Directly matches the 'we already have extracted skeleton sequences, animate a consistent character' use case for Gravita/JabLab/Choreia demo videos.
- license: Repo ships a LICENSE file (check exact terms before shipping; base SVD checkpoint it fine-tunes from carries Stability AI's non-commercial Community License unless a commercial SVD license is purchased) — TREAT AS NOT CLEANLY COMMERCIAL until verifie
- cost: Self-host only, no hosted API found. Free to run once GPU is owned/rented.
- maturity: Research release (ICML 2025 paper), actively referenced by newer 2025-2026 papers as a baseline — not a maintained product.
- integration: ComfyUI workflow exists (runcomfy.com); moderate integration effort, Python/diffusers stack.
- caveats: License ambiguity is the single biggest risk: MimicMotion is built on Stable Video Diffusion, whose base weights are non-commercial (Stability AI Community License) unless you buy a commercial SVD license — this could make MimicMotion outputs non-commercial in practice even though the Tencent repo code itself may be permissively licensed. Verify LI
- url: https://github.com/Tencent/MimicMotion
### HumanAIGC AnimateAnyone / AnimateAnyone 2
- what: Alibaba's consistent-character human image animation from a reference image + pose sequence; v2 adds environment affordance (character interacts with background/props).
- why: Same pose-driven animate-a-consistent-character workflow; v2's environment affordance is useful for 'studio environment' consistency across movement clips.
- license: Apache License 2.0 on the GitHub repo — genuinely permissive, commercial use allowed with attribution/notice retention.
- cost: Free to self-host; no official weights release historically (HumanAIGC has been slow/inconsistent about releasing checkpoints for v1; v2 weights avail
- maturity: v2 paper Feb 2025 (arXiv 2502.06145), CVPR-track work; community reimplementations exist but official weights for v2 not confirmed released.
- integration: Moderate-high effort; official code/weights availability is the practical blocker, not the license.
- caveats: License looks clean (Apache-2.0) but actual usability is gated by whether official pretrained weights are ever released — historically AnimateAnyone v1's official weights were never public, only community reproductions (e.g., MooreThreads/Moore-AnimateAnyone) with their own separate licenses. Verify weight availability before counting on this.
- url: https://github.com/HumanAIGC/AnimateAnyone
### Fudan Champ (3D Parametric Guidance)
- what: Human image animation guided by SMPL 3D parametric body model (depth/normal/semantic maps) instead of 2D pose alone, for better anatomical consistency during animation.
- why: 3D-guided approach may better preserve anatomically correct joint angles for athletic movements (handstands, kicks) than pure 2D-pose models — directly relevant to 'anatomical fidelity limits' questio
- license: Apache 2.0 (permissive, commercial use allowed).
- cost: Free to self-host; consumer GPU feasible per community reports (~16-24GB VRAM class) but slower than 2D-pose-only methods due to SMPL fitting step.
- maturity: CVPR/arXiv 2403.14781, research-grade, moderate community adoption (Windows fork exists: sdbds/champ-for-windows), not a maintained commercial product
- integration: Requires SMPL parametric fitting pipeline on top of pose extraction — added complexity vs. MimicMotion/AnimateAnyone.
- caveats: Full-body athletic motion (inversions, high-velocity strikes) is outside the training distribution of most human-animation datasets (typically dance/gesture/runway-walk clips) — expect degraded fidelity on handstand/jab-specific extremes; no benchmark found specifically for gymnastics/combat-sports motion.
- url: https://github.com/fudan-generative-vision/champ
### TMElyralab MusePose
- what: Pose-driven image-to-video framework for virtual human generation, Tencent Music Entertainment Lyra Lab.
- why: Another pose-conditioned option in the same family, sometimes cited as more stable on stylized/controlled full-body motion than AnimateAnyone reimplementations.
- license: Uncertain from search — not directly verified in this pass (Apache-style repos are common in this family but must be checked individually; do NOT assume).
- cost: Free to self-host, consumer-GPU class per community reports.
- maturity: 2024 research release, still cited/compared in 2025-2026 papers as one of several UniAnimate/Champ/StableAnimator-class baselines.
- integration: ComfyUI community workflows exist.
- caveats: License was not independently confirmed in this research pass — flag as UNVERIFIED, check repo LICENSE file directly before use.
- url: https://github.com/TMElyralab/MusePose
### Alibaba UniAnimate
- what: Unified pose-driven animation using a Temporal Mamba backbone for efficient long-sequence generation; stacks reference latent with noisy latents.
- why: Frequently cited as SOTA baseline alongside Champ/StableAnimator/EchoMimicV2 for full-body pose-driven animation quality comparisons in 2025-2026 papers (e.g., EMOSH arXiv 2606.28026).
- license: Not verified in this pass — check official UniAnimate GitHub repo directly.
- cost: Free to self-host if weights released; VRAM requirements not confirmed here.
- maturity: Cited as an established comparison baseline through 2026, suggesting reasonably mature/reproducible code.
- integration: Unconfirmed — treat as research-grade.
- caveats: This entry is the weakest-evidenced of the pose-driven group; only found via citation in a comparison paper, not via its own repo/license page. Needs direct follow-up before any commitment.
- url: https://arxiv.org/html/2606.28026
### Ant Group EchoMimicV2 / EchoMimicV3
- what: EchoMimicV2 (CVPR 2025): semi-body human animation from reference image + audio + hand-pose sequence. EchoMimicV3 (AAAI 2026): unified 1.3B-parameter multi-modal, multi-task human animation (pose/audio-driven), Apache 2.0.
- why: V3's Apache-2.0 licensing and 2026 recency make it the cleanest-licensed, most current pose+audio-driven option found; useful for voice-coach lip/gesture sync layered on top of movement demos.
- license: Apache License 2.0 (confirmed for V3) — genuinely commercial-friendly.
- cost: Free to self-host; 1.3B params suggests consumer-GPU feasibility (needs direct VRAM confirmation before committing).
- maturity: Actively maintained by Ant Group through 2026 (AAAI 2026 paper), most recent/active repo of the whole open pose-animation family.
- integration: Purpose-built more for talking/gesturing portraits+semi-body than full standing full-body athletic motion — may need adaptation for standing exercise demonstrations.
- caveats: EchoMimic family's core strength is face/upper-body + audio-driven animation, not full standing-body athletic form (handstands, kicks, footwork) — likely weaker fit than MimicMotion/Champ for whole-body sport-specific reference-skeleton animation. Verify with a pilot test before adopting.
- url: https://github.com/antgroup/echomimic_v3
### Black Forest Labs FLUX.1 [dev] / FLUX.2 [dev]
- what: State-of-the-art open-weight text/image-to-image diffusion model, commonly LoRA-fine-tuned to lock a consistent character identity for use as a reference image feeding pose-driven animators.
- why: Step (2) of the pipeline: generate/lock a single consistent 'AI instructor' character portrait via LoRA, then drive it with pose-driven video models above.
- license: FLUX.1 [dev] weights are NON-COMMERCIAL by default (FLUX Dev Non-Commercial License) — commercial use requires either (a) generating exclusively via BFL's own paid API (whose outputs are commercially licensed) or (b) purchasing a separate commercial 
- cost: Non-commercial self-hosting is free (just GPU cost); commercial path costs API fees (BFL API, pay-per-image) or a negotiated enterprise license (not p
- maturity: FLUX.1 released 2024, FLUX.2 [dev] 2025-2026 with native multi-LoRA stacking (up to 4 adapters) for character+brand consistency — actively developed, 
- integration: Straightforward LoRA training pipelines (Kohya, ai-toolkit, fal.ai training endpoints) widely documented.
- caveats: This is the trap most teams miss: self-hosting FLUX.1/2-dev weights locally and shipping the outputs commercially without an API/enterprise license is a license violation even though the model is 'free to download.' Budget-as-close-to-free plan must route through the paid API tier or Stability/SDXL instead.
- url: https://huggingface.co/black-forest-labs/FLUX.1-dev/blob/main/LICENSE.md
### Stability AI SDXL 1.0 (base)
- what: Open-weight text-to-image diffusion model, widely LoRA-fine-tuned for character consistency; older/lower-fidelity than FLUX but with cleaner commercial terms.
- why: Lower-cost, license-clean alternative to FLUX for the consistent-character reference-image step if FLUX's commercial gating is unworkable on a near-zero budget.
- license: CreativeML Open RAIL++-M — permissive, commercial use of the model AND its generated outputs allowed with no revenue cap, subject to RAIL's use-based restrictions (no illegal/harmful use).
- cost: Free to self-host; consumer GPU (8-12GB) sufficient for SDXL inference/LoRA training with modern optimizers.
- maturity: Mature, extremely well-documented (2023 release), huge LoRA/ComfyUI ecosystem, effectively the safe default for commercial character-consistency work 
- integration: Very well supported (ComfyUI, Automatic1111, diffusers, Civitai LoRA ecosystem).
- caveats: Visual fidelity/likeness consistency is noticeably behind FLUX and behind closed models (Midjourney, Kling's image mode) — expect more LoRA-training iteration to nail a consistent instructor face/body across angles.
- url: https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/LICENSE.md
### Kling AI (Kuaishou) — video generation API
- what: Closed commercial text/image-to-video model family (Kling 3.0/O1) with a Motion Control mode that can take pose/motion reference input.
- why: Paid alternative for generating instructor demonstration clips directly, with an actual motion-control input mode relevant to pose-driven demos.
- license: Paid membership/API tiers remove watermark and 'expressly permit commercial use, subject to Kling's wider rights and content rules'; free tier explicitly bars commercial use and is watermarked/720p/5s-capped.
- cost: API pay-as-you-go roughly $0.07-$0.14 per second of video (e.g., ~$0.075/s Kling 3.0, ~$0.111/s Kling O1, ~$0.113/s Motion Control mode); a 5s 1080p c
- maturity: Actively developed 2025-2026, Motion Control is a newer feature (exact motion-accuracy-on-athletic-movement benchmarks not found in this pass).
- integration: REST API via Kling developer platform or resellers (kie.ai, others); resellers may offer lower effective per-second rates but add a middleman ToS layer to check.
- caveats: No independently verified benchmark found for accuracy of Kling Motion Control on precise athletic form (jab mechanics, yoga alignment) — this needs a hands-on pilot test before relying on it for teaching-accurate content; per-clip cost adds up fast for a library of dozens of movements × multiple takes.
- url: https://crazyrouter.com/en/blog/kling-ai-pricing-complete-guide-2026
### Runway Gen-4 / Gen-4.5 — video generation API
- what: Closed commercial text/image-to-video model, Gen-4 (May 2026) with markedly improved character-consistency across shots.
- why: Paid alternative with the best publicly reported character-consistency numbers of the closed tools, relevant to 'consistent instructor across many clips.'
- license: Standard commercial ToS on paid tiers; exact generated-content ownership/commercial-use language needs direct ToS check at runwayml.com/legal before shipping training/marketing content.
- cost: API ≈ $0.12/second on standard Gen-4 (5 credits/s at $0.01/credit on Turbo tier); Gen-4.5 video runs up to 25 credits/s ($0.25/s) at higher quality; f
- maturity: Gen-4 launched May 2026 with reported ~85-87% character-consistency across generations in independent testing — best-in-class among closed tools for t
- integration: REST API documented at Runway's developer portal; straightforward integration.
- caveats: Character consistency numbers (85-87%) are still not 100% — some fraction of generated clips will show a visibly 'different' instructor and need manual filtering/regeneration, which adds hidden cost on top of the quoted per-second price. No specific benchmark found for exercise-form / athletic-motion accuracy.
- url: https://fairstack.ai/blog/runway-pricing
### Google Veo 3 / 3.1 (Gemini API / Vertex AI)
- what: Closed commercial text/image-to-video model with native audio generation.
- why: Paid alternative; useful if voice-coaching narration needs to be baked directly into the generated clip (native audio).
- license: Standard Google Cloud / Gemini API commercial terms; per Google, billing only occurs on successful generation.
- cost: Gemini API: $0.05/s (Veo 3.1 Lite, 720p) to $0.40/s (Standard, 720p/1080p); Vertex AI official pricing is steeper at $0.75/s (~$6 for an 8s clip) — a 
- maturity: Veo 3.1 is the current generation as of 2026; legacy Veo 3.0 endpoints were shut down June 30, 2026.
- integration: Gemini API (cheaper) vs Vertex AI (enterprise, pricier) — pick Gemini API tier for a bootstrapped budget.
- caveats: No pose-conditioning / motion-control input mode confirmed for Veo (text/image-to-video only as far as found) — weakest fit of the paid tools for 'animate this specific extracted skeleton,' better suited to generic b-roll-style instructor shots than form-accurate movement reproduction.
- url: https://www.aifreeapi.com/en/posts/veo-3-1-pricing
### HeyGen Avatar IV/V
- what: Closed commercial photorealistic digital-human avatar platform; Avatar V learns a movement profile from a ~15-second reference recording of a real person.
- why: Paid alternative most oriented toward a single consistent 'instructor character' talking/demonstrating, closest analog to a virtual coach persona (though optimized for talking-head/gesture, not full-b
- license: Standard commercial SaaS ToS; paid plans grant commercial usage rights to generated video (verify exact clause at heygen.com/legal before shipping).
- cost: API: $0.05/second (~$3/minute) for Avatar V; platform plans from $29/mo (Creator, 200 credits) to $149/mo+seat (Business, 4K + custom avatars).
- maturity: Mature commercial product, Avatar V is HeyGen's current premium engine in 2026.
- integration: REST API + web studio; well documented.
- caveats: HeyGen's motion realism is trained/optimized for talking, presenting, and light gesture — NOT validated for precise full-body athletic form (a jab's shoulder rotation, a handstand's hip alignment); using it to demonstrate technique accurately enough to teach form is unproven and likely to reproduce generic/soft movement rather than the biomechanica
- url: https://www.eesel.ai/blog/heygen-pricing
### EU AI Act Article 50 — transparency/labeling obligations
- what: Binding EU law requiring providers of generative AI systems to mark synthetic audio/image/video output in a machine-readable, detectable way, and requiring deployers to clearly disclose deepfake-like content (AI-generated content resembling real persons/events) to end users.
- why: Directly governs disclosure obligations for the planned AI-instructor teaching visuals if any EU users are served — a hard compliance requirement, not optional guidance.
- license: N/A (regulation)
- cost: N/A
- maturity: Applies from 2 August 2026; European Commission adopted final Guidelines and a Code of Practice on Transparency of AI-generated content in mid-2026 as
- integration: Practical requirement: (1) embed machine-readable provenance/watermark metadata in generated video (e.g., C2PA-style), AND (2) since the AI instructor is a synthetic character that could plausibly be 
- caveats: Deepfake labeling applies 'even without intent to deceive... even if no real individual is depicted' per guidance found — meaning a fully synthetic, non-real 'AI instructor' character likely still needs a clear AI-generated disclosure label, not just real-person deepfakes. Content generated before 2 Aug 2026 does not need retroactive labeling, but 
- url: https://artificialintelligenceact.eu/transparency-rules-article-50/


# ==== harvest-pipeline ====

## SUMMARY
Recommended founder-free harvesting toolchain: yt-dlp (Unlicense) as the acquisition backbone — layered with YouTube Data API's videoLicense=creativeCommon filter and non-YouTube CC sources (Vimeo CC, Wikimedia Commons, Internet Archive, Pexels/Pixabay) as license-safer supplements — feeding PySceneDetect (BSD-3) for scene/clip segmentation, MediaPipe Pose (Apache 2.0, same model family already shipping in-app) as the primary batch pose extractor with mmpose/RTMPose (Apache 2.0, audit checkpoints individually) as a higher-fidelity supplement, imagededup + videohash for dedup, an in-house OpenCV Laplacian-variance blur filter plus native landmark-visibility scores for quality/occlusion filtering, and faster-whisper (MIT) run locally for zero-cost coaching-cue mining from tutorial audio. The one serious licensing landmine surfaced is the SMPL/SMPL-X body model underlying nearly all 3D human-mesh-recovery repos (4D-Humans, WHAM) — its research-only license is separate from and stricter than the permissive code licenses of the repos that depend on it, and should be avoided for anything touching the shipped product without a paid Meshcapade commercial license. No turnkey 'exercise dataset builder' project exists at GitHub scale; this is a custom-assembled pipeline from general-purpose, individually license-clean tools.

## RECOMMENDATIONS
- Backbone: yt-dlp for acquisition, biased first toward YouTube Data API videoLicense=creativeCommon results, official/federation instructor channels, and non-YouTube CC sources (Vimeo CC, Wikimedia Commons, Internet Archive, Pexels/Pixabay for b-roll) — with YouTube-at-large used per the founder's already-accepted ToS risk decision as the volume fallback.
- Segmentation: PySceneDetect (BSD-3) to cut long tutorial videos into per-movement/per-rep clips before any pose extraction runs.
- Pose extraction, two-tier: use MediaPipe Pose (Apache 2.0) as the default extractor — it's the same model family already shipping in the app, guaranteeing landmark-format parity between references and the runtime scorer. Reserve mmpose/RTMPose (Apache 2.0, but audit each pretrained checkpoint's dataset license) for movements needing higher accuracy or more keypoints.
- Do NOT build the core pipeline around 4D-Humans/WHAM or any SMPL-based 3D mesh recovery unless the founder is willing to either purchase a commercial SMPL license from Meshcapade or strictly firewall that output from ever touching shipped/commercial artifacts — the SMPL model's non-commercial research-only clause is the single largest hidden license risk in this space and is easy to miss because the *code* repos (Apache/MIT) look clean while the *model* they depend on is not.
- Quality/dedup stage: imagededup (Apache 2.0) for frame-level near-duplicate filtering, videohash for whole-video near-duplicate detection, and a simple in-house OpenCV Laplacian-variance blur filter (no need to depend on a third-party repo for a 5-line technique) plus MediaPipe/mmpose's native per-landmark visibility scores for occlusion filtering.
- Coaching-cue mining: faster-whisper (MIT, SYSTRAN) run locally on the founder's own machine for zero-cost batch transcription of instructor audio, feeding a searchable coaching-language corpus.
- Provenance: log per-item {source_url, uploader/channel, license_type_if_known, retrieval_date, tool_version} for every harvested clip at download time (yt-dlp --write-info-json gives most of this for free) — this is the cheapest possible insurance against future takedown requests or license disputes and should be non-negotiable regardless of which acquisition source is used.
- Accept that there is no single 'exercise dataset builder' repo worth adopting wholesale — plan for ~2-4 weeks of custom glue-code work to compose the above general-purpose tools into the actual harvesting rig.

## RISKS
- YouTube ToS/derivative-content risk on yt-dlp downloads is real and already accepted as a business decision by the founder — not re-argued here, but worth re-confirming this decision periodically as YouTube's enforcement posture and legal precedent (e.g. ongoing yt-dlp-adjacent litigation trends) can shift.
- SMPL/SMPL-X body-model license (non-commercial only) is a serious, easy-to-miss trap in the entire 3D-human-recovery research ecosystem (4D-Humans, WHAM, VIBE, and most mesh-recovery repos depend on it) — using these for anything that touches the shipped commercial product without a Meshcapade commercial license would violate the model's own terms even though the surrounding code repos are permissively licensed.
- mmpose's Apache 2.0 repo license does not automatically clear every pretrained checkpoint in its model zoo — some are trained on datasets with academic-only redistribution terms; audit weights individually, not just the codebase.
- The `internetarchive` Python library is AGPL-3.0 — per the family's own stated policy this class of license is banned for anything shipped, and must be strictly confined to the founder's offline harvesting-rig tooling, never linked into or distributed with any app binary or backend service.
- Coverage of true CC-licensed, non-YouTube sources (Vimeo CC, Wikimedia Commons, Pexels/Pixabay, Internet Archive) for niche movement-specific technique content (correct-form handstands, shadow-boxing combinations, specific dance steps) is likely thin — expect these to supply single-digit-percent of total volume, with YouTube-at-large (already risk-accepted) remaining the dominant practical source for reaching the '>=3 instructors per movement' consensus target at scale.
- Several smaller utility repos flagged here (videohash, individual blur-detection scripts) have thinner maintenance signals (single maintainer, forks suggesting stalls) — treat as lower-confidence picks, verify current license file and recent commit activity before depending on them in production, and prefer reimplementing trivial techniques (blur detection) in-house over adding a fragile dependency.
- No existing GitHub project does true end-to-end 'public video -> licensed, deduplicated, quality-filtered movement reference dataset' at the scale and specificity Yula Motion needs — this whole toolchain must be assembled and maintained in-house, which is an ongoing engineering cost, not a one-time integration.

## ITEMS
### yt-dlp
- what: CLI/Python library for downloading video+audio from YouTube and 1800+ other sites (also supports metadata-only scraping, subtitle extraction, and filtering by uploader/playlist).
- why: Core acquisition engine for the harvesting rig. Founder has accepted YouTube ToS risk; yt-dlp is still the only practical tool at this scale. Combine with YouTube Data API `videoLicense=creativeCommon
- license: Unlicense (public domain) for the git/PyPI code; some bundled release binaries include MIT/ISC third-party code (THIRD_PARTY_LICENSES.txt) — license itself is not the risk, YouTube's Terms of Service is the risk (a policy question, already decided by
- cost: Free
- maturity: Very mature, most-starred yt-dlp fork family, daily releases, huge contributor base.
- integration: CLI or Python (`yt_dlp` module); pair with `--write-info-json` for provenance metadata and `--download-archive` for incremental/resumable harvesting runs.
- caveats: ToS/derivative-work risk on YouTube downloads is real and already accepted per binding decision — not re-litigated here. Mitigation ladder: (1) prefer YouTube Data API creativeCommon filter, (2) prefer non-YouTube CC sources below, (3) prefer official federation/instructor channels with clear educational-use framing, (4) keep per-video provenance (
- url: https://github.com/yt-dlp/yt-dlp
### YouTube Data API v3 Search — videoLicense=creativeCommon
- what: Official Google API parameter that filters YouTube search results to only videos the uploader marked Creative Commons (CC BY reuse license).
- why: Lets the pipeline pre-filter candidate videos by license before ever downloading, directly implementing the 'prefer CC-licensed videos' mitigation the founder wants layered on top of yt-dlp usage.
- license: Google API — free tier (quota-limited, 10,000 units/day default), Google API Terms of Service apply to API usage itself.
- cost: Free within quota
- maturity: Official, stable, actively maintained by Google.
- integration: REST call with `type=video&videoLicense=creativeCommon`; feed resulting video IDs into yt-dlp for download.
- caveats: Only a small minority of YouTube uploads are marked CC; coverage for niche movement categories (handstand, shadow boxing specifics) may be thin — expect to fall back to standard-license videos per the accepted risk decision.
- url: https://developers.google.com/youtube/v3/docs/search/list
### Vimeo — Creative Commons filter / API
- what: Vimeo lets uploaders tag videos with CC licenses and supports filtering by license in search/API.
- why: Non-YouTube source diversification; Vimeo skews toward higher-production dance/movement/fitness content from independent instructors, often explicitly CC-licensed for reuse.
- license: Vimeo API terms; individual videos carry their own CC license (BY, BY-SA, etc.) set by uploader — must be read per-video.
- cost: Free tier available (rate-limited); higher tiers paid.
- maturity: Stable, official platform API.
- integration: REST API with `filter=CC` type query params, or yt-dlp also supports vimeo.com URLs directly.
- caveats: Volume is much lower than YouTube for niche movement content — treat as a supplementary, not primary, source.
- url: https://developer.vimeo.com/api/reference/videos#search_videos
### Pexels API (video)
- what: Free stock photo/video API; all content licensed under the permissive Pexels License (free for commercial use, no attribution required).
- why: Genuinely zero-risk source for general sport/fitness/movement B-roll and some instructional clips — directly satisfies the 'budget as close to free as possible' and license-safety goals, though covera
- license: Pexels License — free for commercial and personal use, no attribution required.
- cost: Free (200 req/hour, 20,000/month on default key).
- maturity: Mature, official, actively maintained.
- integration: REST API, JSON responses with direct video file URLs.
- caveats: Library is stock-footage oriented, not instructor/coaching content — good for supplementary b-roll/scene variety, not a substitute for real technique references from instructors.
- url: https://www.pexels.com/api/
### Pixabay API (video)
- what: Free media API (photos/video/music) under the Pixabay Content License, similar royalty-free terms to Pexels.
- why: Second free/permissive stock source for scale and diversity; unlimited requests on the free API tier.
- license: Pixabay Content License — royalty-free, broad commercial reuse allowed.
- cost: Free, unlimited requests.
- maturity: Mature, official.
- integration: REST API.
- caveats: Video catalog is smaller/thinner than photos on Pixabay; same coaching-content-scarcity caveat as Pexels.
- url: https://pixabay.com/api/docs/
### Wikimedia Commons (API + pyWikiCommons)
- what: Wikimedia's media repository with millions of files under CC/public-domain licenses, including instructional and sports videos (e.g. WikiSport, dance, gymnastics footage); pyWikiCommons is a Python wrapper for bulk retrieval.
- why: High-provenance, license-explicit source — every file's exact CC variant (BY, BY-SA, public domain) is machine-readable via the API, making automated compliant filtering easy.
- license: Per-file CC licenses (mostly CC BY-SA or public domain), documented via API metadata; pyWikiCommons wrapper itself is open source.
- cost: Free
- maturity: Wikimedia API is official/stable; pyWikiCommons is a small community package (moderate maturity, last significant activity a few years back — check be
- integration: MediaWiki Action API / REST API; pyWikiCommons (`pip install pyWikiCommons`) for simple bulk-download scripts.
- caveats: Volume of relevant movement-technique video (vs. images) is limited compared to YouTube — useful for provenance-clean supplementary set, not primary volume. Verify pyWikiCommons is still functional (unofficial community tool) before depending on it.
- url: https://api.wikimedia.org/wiki/Documentation/Code_samples/Images_and_media
### Internet Archive + internetarchive Python library / internetarchive-downloader
- what: Archive.org hosts large public-domain and CC-licensed video collections (historical sports footage, educational films, some modern creator uploads); the official `internetarchive` Python library and the `internetarchive-downloader` script support bulk, multithreaded retrieval by collection/item.
- why: Another zero-cost, license-transparent, non-YouTube source, especially strong for public-domain historical instructional/sports film that carries essentially no ToS risk.
- license: internetarchive Python lib: AGPL-3.0 (NOTE: AGPL — per family policy this is BANNED for shipped closed-source apps, but the family's own stated exception applies: 'offline tooling on our own machines has more freedom' — this tool never ships in the a
- cost: Free
- maturity: internetarchive lib is official/IA-maintained and mature; internetarchive-downloader is a smaller community script.
- integration: CLI/Python.
- caveats: AGPL license on the official `internetarchive` pip package is a hard flag — confirm it never gets bundled into any shipped product; treat strictly as a build-machine-only offline tool per the family's own carve-out. Per-item license on archive.org varies widely and must be read from item metadata before use.
- url: https://github.com/john-corcoran/internetarchive-downloader
### PySceneDetect
- what: Python/OpenCV library and CLI for detecting scene cuts/transitions in video and automatically splitting clips (ContentDetector, AdaptiveDetector, ThresholdDetector).
- why: First-stage pipeline step: chops long tutorial videos into individual movement/rep segments before pose extraction, and helps discard talking-head/intro/outro segments that aren't usable reference foo
- license: BSD 3-Clause — fully permissive, safe for closed-source shipped tooling.
- cost: Free
- maturity: Very mature (10+ years), actively maintained, large user base, also has hosted docs at scenedetect.com.
- integration: Python API (`from scenedetect import detect, ContentDetector`) or CLI; straightforward to slot into a batch pipeline.
- caveats: Tuned for editorial scene cuts (camera angle changes), not semantic rep boundaries — will still need a downstream heuristic (e.g. pose-velocity zero-crossings) to segment individual reps/movements within a single continuous shot.
- url: https://github.com/Breakthrough/PySceneDetect
### MediaPipe Pose / Tasks (Pose Landmarker)
- what: Google's on-device pose estimation solution (BlazePose-based), 33 landmark 2D/3D pose extraction, real-time capable on CPU.
- why: This is already the family's chosen on-device scoring engine — using the exact same MediaPipe Pose model for the offline reference-harvesting pipeline guarantees landmark-format compatibility between 
- license: Apache 2.0 — fully permissive, safe for both offline tooling and shipped closed-source apps (already the case, since it ships in-app).
- cost: Free
- maturity: Very mature, Google-maintained, industry-standard for lightweight pose estimation.
- integration: Python (`mediapipe` pip package) for batch offline processing on the harvesting rig; same model family as the in-app Flutter/native integration.
- caveats: 2D/2.5D landmarks only (BlazePose gives rough 3D z but is not metric-accurate 3D) — for movements needing more reliable 3D depth (e.g. handstand alignment, precise joint angles) mmpose or a 3D recovery model below is a stronger reference-extraction option, at the cost of losing pipeline/model parity with the in-app scorer.
- url: https://github.com/google-ai-edge/mediapipe
### MMPose (OpenMMLab)
- what: Comprehensive PyTorch pose-estimation toolbox: 2D/3D body, hand, face, whole-body (133 keypoint) pose, plus batch video inference tooling and pretrained model zoo (HRNet, RTMPose, etc.).
- why: Higher-accuracy/more-keypoint alternative or supplement to MediaPipe for building the master reference library offline (accuracy matters more than real-time speed at harvest time); RTMPose models with
- license: Apache 2.0 for the MMPose codebase itself (per LICENSE file). CAVEAT: some pretrained checkpoints/model configs in the model zoo are trained on datasets with non-commercial restrictions, and any 3D mesh recovery via SMPL/SMPL-X integration is separat
- cost: Free (compute cost only — GPU recommended for batch throughput at scale).
- maturity: Very mature, large OpenMMLab ecosystem, active development and community.
- integration: Python; has dedicated video-inference demo scripts for batch dataset construction (image/video → keypoint JSON).
- caveats: Steeper setup/dependency footprint than MediaPipe (PyTorch, MMEngine, MMCV compiled ops); some model configs depend on COCO-WholeBody or similar datasets with academic/research-only redistribution terms for the weights — audit per-model before use, and never redistribute/ship the model checkpoints themselves in the app.
- url: https://github.com/open-mmlab/mmpose
### 4D-Humans (HMR 2.0)
- what: Transformer-based 3D human mesh recovery and tracking from monocular video ('Humans in 4D: Reconstructing and Tracking Humans with Transformers').
- why: Candidate for extracting metrically-meaningful 3D body pose/mesh sequences from 2D reference videos — useful for movements where depth/rotation matters (handstand alignment, boxing rotation, dance tur
- license: Code license: check repo LICENSE (research-oriented, verify exact terms before use — historically HMR-family code repos are MIT/BSD for code but always depend on the SMPL body model). HARD CAVEAT: 4D-Humans, like nearly all 3D human mesh recovery rep
- cost: Free code, but SMPL model itself may require a paid commercial license (Meshcapade) if used in any commercial pipeline.
- maturity: Actively used research codebase (CVPR-lineage), well-cited, moderate ongoing maintenance.
- integration: Python/PyTorch, GPU strongly recommended for batch inference.
- caveats: This is the single biggest license trap in this whole toolchain. Do NOT use 4D-Humans/WHAM/any SMPL-based 3D recovery pipeline in a way that touches the shipped commercial product or any commercially-used derived reference data without either (a) obtaining a commercial SMPL license from Meshcapade, or (b) using it purely as an internal, non-distrib
- url: https://github.com/shubham-goel/4D-Humans
### WHAM (World-grounded Humans with Accurate Motion)
- what: ECCV 2024 method for world-grounded 3D human motion recovery from video, combining video features with camera motion estimation.
- why: Same use case as 4D-Humans — higher-fidelity 3D motion extraction from monocular reference video, useful if the team wants world-frame-accurate trajectories (e.g. for Choreia's traveling dance steps).
- license: Code license: verify repo LICENSE file directly (not fully confirmed in this research pass — flag as uncertain). Same SMPL body-model non-commercial dependency as 4D-Humans applies here.
- cost: Free code, GPU compute cost; SMPL model may require commercial license as above.
- maturity: Recent (ECCV 2024), research-grade, less battle-tested for production batch pipelines than mmpose/MediaPipe.
- integration: Python/PyTorch.
- caveats: Same SMPL non-commercial trap as 4D-Humans. Also newer/less mature — expect more engineering friction for large-scale batch harvesting than mmpose. Treat as an optional high-fidelity supplement, not the pipeline backbone, given the licensing overhead.
- url: https://github.com/yohanshin/WHAM
### imagededup
- what: Python library for finding exact and near-duplicate images using perceptual hashing (PHash/DHash/WHash/AHash) and CNN-based similarity, with a built-in evaluation framework.
- why: Deduplication stage after PySceneDetect segmentation — many public tutorial videos re-upload/mirror the same footage; dedup on extracted key frames prevents the reference library from being dominated 
- license: Apache 2.0 — fully permissive.
- cost: Free
- maturity: Mature, maintained by Idealo (large e-commerce co.), well-documented with hosted docs site.
- integration: Python; run on extracted key frames per scene/segment.
- caveats: Designed for still images, not full video streams — must first extract representative frames (e.g. via PySceneDetect or periodic sampling) before applying.
- url: https://github.com/idealo/imagededup
### videohash
- what: Python package for near-duplicate full-video detection via a 64-bit perceptual video hash, robust to resize/transcode/watermark/frame-rate changes.
- why: Video-level (not just frame-level) deduplication — catches re-encoded/re-uploaded copies of the same source tutorial across channels before they're even segmented, saving compute and preventing skewed
- license: Verify exact license in repo (commonly MIT for this author's projects — confirm before use; not independently verified in this pass).
- cost: Free
- maturity: Moderate — actively maintained by a single primary maintainer (akamhy), has a fork (videohash2) suggesting some maintenance gaps; check recent commit 
- integration: Python, requires ffmpeg (also a yt-dlp dependency, so no new system dependency).
- caveats: Cannot detect partial/fingerprint-style overlap (e.g. a video that only contains a clip of another) — only whole-video near-duplicates; combine with imagededup at the frame/segment level for finer-grained dedup.
- url: https://github.com/akamhy/videohash
### OpenCV Laplacian-variance blur detection (WillBrennan/BlurDetection2 pattern)
- what: Simple, well-established technique: convolve frame with the Laplacian operator and threshold on variance to flag blurry/motion-blurred frames; several reference implementations exist on GitHub.
- why: Quality-filtering stage — rejects motion-blurred or out-of-focus frames from low-quality tutorial uploads before they enter the reference library, protecting the accuracy of the multi-instructor conse
- license: Repo-dependent — WillBrennan/BlurDetection2 and similar are typically MIT/permissive small utility scripts; this is really a ~5-line OpenCV technique (`cv2.Laplacian(...).var()`) rather than a dependency worth pinning to one repo. Verify the specific
- cost: Free (uses OpenCV, already a dependency via PySceneDetect/mediapipe pipeline).
- maturity: Technique is a standard, decades-old, well-documented computer vision method (see PyImageSearch tutorial); reference repos are small hobby-maintained 
- integration: Trivial to reimplement directly in-house with `opencv-python` rather than pulling in a third-party repo as a dependency.
- caveats: Given how simple the technique is, recommend implementing it directly rather than depending on any specific small GitHub repo (reduces supply-chain/maintenance risk); occlusion detection (person partially out of frame / limbs hidden) is NOT covered by blur detection and needs a separate check — e.g. MediaPipe/mmpose per-landmark visibility/confiden
- url: https://github.com/WillBrennan/BlurDetection2
### OpenAI Whisper
- what: Open-source automatic speech recognition (ASR) model trained on 680,000 hours of multilingual audio; transcribes and can translate speech, runs fully offline/on-device.
- why: Directly enables 'speech→cue mining from tutorials': transcribe instructor audio from harvested videos to build a coaching-language/cue library (e.g. common verbal cues real instructors use for a hand
- license: MIT — fully permissive, safe for both offline tooling and shipped closed-source apps.
- cost: Free (local compute only, no API cost).
- maturity: Very mature, industry-standard ASR baseline, huge ecosystem.
- integration: Python (`pip install openai-whisper`), or via faster-whisper (below) for better throughput at batch scale.
- caveats: Base OpenAI Whisper is noticeably slower than faster-whisper for large-batch offline transcription; recommend using faster-whisper as the actual runtime with the same underlying model weights.
- url: https://github.com/openai/whisper
### faster-whisper (SYSTRAN)
- what: Reimplementation of Whisper using CTranslate2 inference engine — up to 4x faster than the original OpenAI implementation at equivalent accuracy, with 8-bit quantization support for CPU/GPU efficiency.
- why: The practical production choice for batch-transcribing a large corpus of harvested tutorial videos to mine coaching cues at reasonable time/cost on the founder's own hardware.
- license: MIT — fully permissive.
- cost: Free (local compute only).
- maturity: Mature, actively maintained by SYSTRAN, widely adopted as the go-to fast local Whisper runtime.
- integration: Python (`pip install faster-whisper`), drop-in replacement pattern for Whisper API calls, supports CPU-only quantized inference for the founder's own machines.
- caveats: None significant beyond general Whisper transcription-accuracy caveats (accents, overlapping speech, background music in some fitness videos can degrade cue-extraction quality — plan for manual spot-checking of the mined cue library).
- url: https://github.com/SYSTRAN/faster-whisper
### Existing fitness/exercise pose-estimation reference repos (community-scale, not production-grade)
- what: A handful of smaller open GitHub projects apply pose estimation to fitness video for rep-counting/form-checking (e.g. DanielGuarnizo/Pose-Estimation-for-Fitness-Exercise-Analysis, SravB/Computer-Vision-Weightlifting-Coach, yakupzengin/fitness-trainer-pose-estimation) plus academic-scale datasets like M3GYM (CVPR 2025) for multi-view gym pose data.
- why: Worth reviewing as architecture/approach references for the video→pose-sequence pipeline design, but none of these are turnkey 'harvest at scale' tools — they are small demo/student projects, not infr
- license: Varies per repo — check each individually; several have no explicit license file (defaults to all-rights-reserved for reuse, i.e. code can be read for reference but not safely vendored without checking).
- cost: Free to read/reference
- maturity: Low — mostly student/hobby projects with limited stars, sparse maintenance, small scope (single-exercise demos).
- integration: Not directly integrable — use as design inspiration only, not as dependencies.
- caveats: HONEST FLAG: there is no mature, well-maintained, GitHub-scale 'exercise/movement video dataset builder' project that does what the family needs end-to-end. The realistic path is composing the general-purpose tools above (yt-dlp + PySceneDetect + MediaPipe/mmpose + imagededup/videohash + faster-whisper) into a custom pipeline, not adopting a single
- url: https://github.com/topics/fitness-dataset


# ==== breadth-gravita-lissom ====

## SUMMARY
Breadth-harvest of public-video sources for Gravita (handstand + calisthenics skill families) and Lissom (mobility tests + yoga asanas) surfaced a workable but not fully proven multi-instructor pool. For Gravita, GMB Fitness, FitnessFAQs, Tom Merrick, THENX, Tapp Brothers, and Antranik give strong 3+ instructor coverage for handstand, pistol squat, crow pose, and L-sit; planche/front lever coverage is thinner, anchored mainly by Simonster Strength. For Lissom, clinical/PT-credentialed channels (Physiotutors, E3 Rehab, Clinical Physio, Movement by David, NASM/Brookbush) plus flexibility specialists (Emmet Louis, Tom Merrick) give a plausible multi-instructor pool for shoulder flexion, thoracic rotation, and overhead squat assessment, but several named tests (hamstring reach, ankle dorsiflexion, single-leg balance, most FMS sub-tests) were confirmed only at channel level, not individual-video level, and need a follow-up search pass. No usable CC-licensed or public-domain instructional VIDEO source was found for either family — Wikimedia Commons/Internet Archive returned only static photos. The closest thing to a goniometer/angle ground-truth resource is the academic Yoga-82 dataset, which is image-only (not video), not goniometer-measured, and of uncertain per-image commercial licensing — usable at most as an internal benchmark, not a shipped asset.

## RECOMMENDATIONS
- Adopt a two-tier source model per movement: (1) a small set of named, credentialed single-instructor channels (GMB, FitnessFAQs, Tom Merrick, Emmet Louis, Physiotutors, Clinical Physio) as the primary >=3-instructor consensus pool for Gravita's handstand/pistol/crow/L-sit and Lissom's shoulder/thoracic/ankle tests; (2) a wider 'long-tail' YouTube search pass per specific movement (e.g. 'planche tutorial', 'ankle dorsiflexion test video') to fill in movements where the named channels are thin (planche/lever, hamstring reach test, balance tests, most individual asana beyond crow/headstand).
- Do NOT rely on Wikimedia Commons / Internet Archive for CC-licensed VIDEO tutorials — this search found only scattered static photos, not instructional clips. Treat the 'CC-licensed source' requirement as unmet for now; if a CC video source is a hard requirement, a dedicated Archive.org video-category browse (not just web search) is needed as a follow-up, or the family should proceed on standard-YouTube-license public videos with fair-use/reference-extraction framing (consistent with the binding decision that references are 'extracted from public real-instructor videos', not redistributed).
- For Lissom, prioritize the clinical/PT channel cluster (Physiotutors, E3 Rehab, Clinical Physio, Movement by David, NASM/Brookbush) over generic fitness-influencer channels for the standardized tests (overhead squat, shoulder flexion, thoracic rotation, ankle dorsiflexion) — these give protocol-consistent, camera-static clinical demonstrations that will be easier to extract consistent landmark truth from across multiple instructors.
- Run a dedicated follow-up search pass per specific Lissom test name + 'video' (hamstring reach test, single-leg balance test, ASLR test, FMS hurdle step/in-line lunge) — this pass surfaced strong channel-level candidates but did not confirm individual video URLs for every named test.
- No goniometer-ground-truth video dataset was found; Yoga-82 is the closest academic artifact but is image-only and of uncertain commercial licensing — do not treat it as a shippable asset without a separate legal/licensing check; use only as an offline sanity-check benchmark on the founder's own machines, consistent with the family's 'offline tooling has more freedom' allowance.

## RISKS
- No confirmed CC-licensed or public-domain instructional VIDEO source exists for either Gravita or Lissom movement families based on this search — everything found is standard-YouTube-license content, which is consistent with the family's binding decision (extraction from public videos, not redistribution) but means there is zero legal fallback if extraction-from-public-video practice is ever challenged.
- Planche/front-lever and other advanced static-skill progressions (Gravita) currently have thinner multi-instructor confirmation (mainly Simonster Strength + one unattributed front-lever tutorial) than handstand/pistol — risk of falling short of the >=3-6 instructor target for this sub-family without further search.
- Several named tests (hamstring reach, single-leg balance, most FMS sub-tests, ankle dorsiflexion specifically) were confirmed at the channel level but not at the individual-video level — actual per-movement instructor-count could be lower than assumed until specific videos are located.
- The Yoga-82 academic dataset's web-scraped images have unclear per-image copyright provenance; using it beyond an internal benchmark risks IP issues for a shipped closed-source app.
- Some higher-quality clinical channel content (e.g. Clinical Physio 'Premium' videos) is paywalled, working against the stated near-zero budget constraint — free-tier availability must be reconfirmed per video before counting it into the library.

## ITEMS
### GMB Fitness (YouTube + gmb.io)
- what: Coach-led, single-person, clean/plain-background tutorials covering handstand fundamentals, press handstand, one-arm handstand, crow pose, pistol squat, handstand push-up. Playlist-structured (e.g. 8-part 'Comprehensive Handstand Tutorial Series').
- why: Core Gravita reference source: full-body framing, static or simple tripod camera, deliberate slow demonstration reps, covers most calisthenics skill families named in the task (handstand, HSPU, crow, 
- license: standard YouTube license (all rights reserved) — no CC indication found
- cost: free on YouTube; paid programs (Elements, Handstand series) behind gmb.io paywall
- maturity: established, active, large back-catalog (10+ yrs)
- integration: n/a — source for reference extraction, not an SDK
- caveats: Did not verify camera framing shot-by-shot; some GMB videos are talking-head/demo-mixed rather than pure full-body static — spot-check each video before use.
- url: https://www.youtube.com/watch?v=oaB-NdQpcOc
### FitnessFAQs (Daniel Vadnal) — YouTube channel
- what: Physiotherapist-run channel with deep handstand progression content ('Handstand Pro' 60-video series), plus muscle-up, planche, and general calisthenics tutorials.
- why: Second independent instructor take on handstand family (balance, kick-up, press) — helps satisfy the >=3 instructor/movement target for Gravita's handstand line.
- license: standard YouTube license
- cost: free tutorials on YouTube; 'Handstand Pro' is a paid program
- maturity: established, active, PT-credentialed instructor
- integration: n/a
- caveats: Paid program content (60 videos) not verifiable as separately licensed/free; only free YouTube uploads should be counted toward the free-source library.
- url: https://www.youtube.com/channel/UCY8v29rasGtp6bAf_hhxFBw
### Tom Merrick / The Bodyweight Warrior — YouTube (@BodyweightWarrior)
- what: Single-person, full-body, plain-background videos on pistol squat, mobility/flexibility follow-alongs, handstands; has a dedicated 'Flexibility & Mobility' playlist.
- why: Third independent instructor for pistol squat and handstand; also directly useful for Lissom (mobility/flexibility follow-along format, full-body clean framing).
- license: standard YouTube license
- cost: free
- maturity: established, very active, large subscriber base
- integration: n/a
- caveats: Follow-along format sometimes has camera cuts/angle changes mid-video rather than one static full-body shot — verify per-video before using as pose-extraction source.
- url: https://www.youtube.com/c/BodyweightWarrior/videos
### Emmet Louis — YouTube + Modern Methods of Mobility / Bendability podcast
- what: Flexibility/mobility specialist (gymnastics + circus background); has dedicated 'Shoulder Mobility' YouTube playlist, flexibility test demo videos (e.g. '4 Simple Tests'), and paid M3 programs.
- why: Strong Lissom source for shoulder flexion/overhead mobility tests and general flexibility test demonstrations from a credentialed mobility coach — independent instructor voice distinct from PT-clinica
- license: standard YouTube license
- cost: free YouTube content; paid M3 online programs
- maturity: established, active, respected in mobility/flexibility niche
- integration: n/a
- caveats: Search did not surface a direct overhead-squat-specific Emmet Louis video — his content skews toward splits/shoulder/hip flexibility tests rather than the NASM-style overhead squat assessment; treat as supplementary, not primary, for that specific test.
- url: https://www.youtube.com/playlist?list=PLXi7slewxuML0TZpk7n_kyLZCZXmpj94W
### Simonster Strength (Simon Ata) — YouTube (@SimonsterStrength)
- what: Single-instructor calisthenics channel focused on planche and front lever progressions, tuck-to-full progressions, static-skill supersets.
- why: Primary/only strong single-creator source found specifically for planche/lever family within Gravita's 'advanced statics' bucket — fills a family FitnessFAQs/GMB cover more thinly.
- license: standard YouTube license
- cost: free tutorials; paid 'Project Planche 2.0' program
- maturity: established, moderately active
- integration: n/a
- caveats: Planche/lever family currently has fewer independent >=3-instructor confirmations than handstand/pistol — recommend supplementing with THENX and generic 'front lever tutorial' searches (several other single-creator front-lever tutorials surfaced, e.g. https://www.youtube.com/watch?v=e_YwP0O34zM, not yet attributed to a named channel).
- url: https://www.youtube.com/c/SimonsterStrength
### THENX — YouTube
- what: Calisthenics channel (bodyweight coaches) with L-sit and pistol squat instructional content ('How To Start Calisthenics — L SIT & PISTOL SQUATS').
- why: Independent instructor for L-sit and pistol squat, adding to the multi-instructor count for those movements.
- license: standard YouTube license
- cost: free
- maturity: established, very large following, active
- integration: n/a
- caveats: THENX videos often feature two presenters and gym backgrounds rather than single-person plain-background framing — verify per video.
- url: https://www.youtube.com/watch?v=flQVCWBuVgk
### Tapp Brothers — YouTube
- what: 'How to Pistol Squat - 4 Beginner Progression Steps' and related bodyweight-strength tutorials.
- why: Additional independent pistol-squat instructor take, full-body single-person framing common in their videos.
- license: standard YouTube license
- cost: free
- maturity: established
- integration: n/a
- caveats: Not deeply vetted beyond this single video; channel-wide coverage of other Gravita movements unconfirmed.
- url: https://www.youtube.com/watch?v=PZlLHZ4Venw
### Tate Englund Yoga — YouTube
- what: Yoga-lineage tutorials on crow pose, crow-to-headstand, and arm-balance transitions.
- why: Yoga-side independent take on crow pose / headstand family, broadening the instructor pool beyond calisthenics-only channels and giving Lissom-adjacent asana coverage overlap with Gravita's crow/heads
- license: standard YouTube license
- cost: free
- maturity: smaller/independent creator
- integration: n/a
- caveats: Single video found; channel breadth and consistency of framing not verified.
- url: https://www.youtube.com/watch?v=7wk7Rvne8VU
### Antranik Kizirian (antranik.org + YouTube)
- what: Long-running bodyweight/gymnastics/flexibility educator; 'The Mobility Project', comprehensive handstand tutorial, crow pose mastery article+video, extensive flexibility bundles.
- why: Broad single-creator archive spanning both Gravita (handstand, crow, gymnastics strength) and Lissom (flexibility/mobility) — useful as a fourth-or-fifth instructor voice across many movements at once
- license: No explicit Creative Commons licensing confirmed on his YouTube uploads despite his site's flexibility-education focus — standard YouTube license assumed; not verified as CC
- cost: free articles/videos; paid bundles for full programs
- maturity: established, long-running (10+ yrs), active blog+video output
- integration: n/a
- caveats: Flag: could not confirm any CC-licensed video status here or anywhere else in this search — no CC-licensed or public-domain full-body tutorial video source was found for either Gravita or Lissom movement families. Treat 'CC-licensed source' as effectively NOT FOUND for usable tutorial-style footage.
- url: https://www.youtube.com/user/AntranikDotOrg/videos
### Wikimedia Commons / Internet Archive (gymnastics & yoga media)
- what: Free-license media repository; checked for handstand/yoga/gymnastics video content.
- why: Was the explicit candidate for CC0/CC-BY source material per the task's ask.
- license: CC0/CC-BY/GFDL depending on file
- cost: free, CC-licensed/public domain
- maturity: n/a — thin, mostly static images not instructional video
- integration: n/a
- caveats: IMPORTANT — evidence is thin/negative: search only turned up static photographs (e.g. 'Joshua Tree yoga - handstand.jpg', 'Handstand.png'), not instructional video clips with full-body clean framing or multi-instructor coverage. No usable CC-licensed VIDEO tutorial source was found for either app family. This should be treated as a confirmed gap, n
- url: https://commons.wikimedia.org/wiki/Category:Handstands
### NASM / Brookbush Institute overhead squat assessment videos
- what: 'NASM Overhead Squat Assessment' YouTube videos, plus Brookbush Institute's 'Overhead Squat Assessment, Goniometry & Muscle Length Tests' YouTube playlist.
- why: Directly matches Lissom's overhead squat test — clinical/certification-grade demonstration with explicit compensation-pattern teaching, well suited as one of several independent 'instructor takes' on 
- license: standard YouTube license
- cost: free videos; paid CPT/certification courses
- maturity: established fitness-certification bodies (NASM), active content
- integration: n/a
- caveats: NASM overhead squat assessment protocol (arms overhead throughout squat) differs procedurally from generic bodyweight/goniometer overhead-squat tests — confirm test protocol matches Lissom's intended scoring definition before treating as ground truth.
- url: https://www.youtube.com/watch?v=dtBvwmMpcRg
### Physiopedia — Overhead Squat Test / Goniometry: Ankle Dorsiflexion reference pages
- what: Clinical reference wiki pages describing standardized test procedures (overhead squat test, ankle dorsiflexion goniometry) with cited methodology, some embedded/linked demonstration media.
- why: Gives Lissom a text-protocol ground truth to cross-check video demonstrations against, and links onward to demonstration videos and academic sources.
- license: CC-BY-NC-SA (Physiopedia's standard site license) — text/reference content only, not raw video footage
- cost: free
- maturity: established, community-maintained, physiotherapy-community-reviewed
- integration: n/a
- caveats: Useful for protocol definitions, not itself a video-instructor source; verify embedded media licensing separately per page.
- url: https://www.physio-pedia.com/Overhead_Squat_Test
### Clinical Physio — YouTube channel
- what: Physiotherapy education channel with a structured range-of-motion library: active/passive ROM testing for knee, lumbar spine, elbow, shoulder, and a dedicated 'Thoracic Spine Full Assessment Run Through' and 'Thoracic Rotation Test' video.
- why: Strong Lissom clinical-assessment source: covers thoracic rotation, shoulder flexion, and general ROM testing with presumably static/clean clinical-demo camera setup — directly matches several of the 
- license: standard YouTube license
- cost: free (some content marked 'Premium' — paywalled)
- maturity: established physio-education channel, active
- integration: n/a
- caveats: Some relevant videos (e.g. Shoulder/Elbow Passive ROM) are marked 'Clinical Physio Premium' and may sit behind a paywall — confirm free-tier access before counting toward the free-budget library.
- url: https://www.youtube.com/watch?v=2MUD8ioDsPk
### E3 Rehab / Movement by David / Physiotutors — YouTube channels
- what: Evidence-based PT/DPT-run channels; E3 Rehab (exercise library + rehab content), Movement by David (mobility exercises, e.g. 'Spinal mobility in 3 steps'), Physiotutors (841K+ subs, large physiotherapy education library).
- why: Three more independent clinical-credential channels to round out the >=3-6 instructor target for Lissom's flexion/rotation/mobility tests; Physiotutors in particular is large enough to likely cover mo
- license: standard YouTube license
- cost: free
- maturity: established, large and active (Physiotutors especially)
- integration: n/a
- caveats: Did not individually confirm each channel has video for every named Lissom test (overhead squat, hamstring reach, balance tests) — Physiotutors' library is large enough to be likely but needs a per-movement follow-up search pass.
- url: https://www.youtube.com/@Physiotutors
### FMS (Functional Movement Screen) reference + demonstration material
- what: Standardized 7-test battery (deep squat, hurdle step, in-line lunge, shoulder mobility, active straight-leg raise, trunk stability push-up, rotary stability) documented by Functional Movement Systems, Physiopedia, and NSCA PDF guides; demonstration videos referenced but not directly surfaced in this search pass.
- why: Gives Lissom a standardized, widely-replicated test protocol family (shoulder mobility, ASLR/hamstring-adjacent test) with strong clinical backing, likely to have many independent instructor video wal
- license: standard web/reference licensing; official demonstration videos likely standard YouTube license
- cost: free reference material; official FMS test kits/certification are paid
- maturity: established industry-standard screen (used since 1990s), very well documented
- integration: n/a
- caveats: This search pass found strong TEXT documentation of FMS tests but did not confirm specific instructor-video URLs for each of the 7 sub-tests — needs a follow-up per-test video search (e.g. 'FMS shoulder mobility test video', 'FMS hurdle step video').
- url: https://www.physio-pedia.com/Functional_Movement_Screen_(FMS)
### Yoga-82 dataset (CVPR Workshop 2020, arXiv:2004.10362)
- what: Academic image dataset of 82 fine-grained yoga pose classes (6/20/82 hierarchical labels), ~28K images scraped from web search, manually annotated keypoints via MakeSense AI.
- why: Closest thing found to a 'goniometer/angle ground truth' dataset for yoga poses — gives Lissom's asana scoring a possible external validation/benchmark set for pose classification, though not a video 
- license: academic dataset license (check paper for exact terms — typically research-use only, not for commercial redistribution)
- cost: free for research use
- maturity: peer-reviewed (CVPRW 2020), moderately cited academic dataset
- integration: downloadable dataset + keypoint annotations; would need licensing review before any commercial (closed-source app) use
- caveats: IMPORTANT: this is a STATIC-IMAGE dataset, not video, and not goniometer-measured — the paper explicitly notes 'no high-quality publicly available video-based benchmarking dataset for yoga asana exists.' It also uses web-scraped images of unclear per-image copyright status — likely NOT usable as a training/reference source for a shipped commercial 
- url: https://arxiv.org/pdf/2004.10362


# ==== breadth-jablab-choreia ====

## SUMMARY
Breadth harvest of public-video sources for JabLab (boxing/kickboxing) and Choreia (dance) confirms the family's data strategy is broadly viable but with uneven strength across sub-clusters. JabLab: three independent, high-volume coach channels (Precision Striking, Tony Jeffries, ExpertBoxing) give a genuine >=3-instructor-per-move baseline for jab/cross/hook/uppercut/footwork, and single-person static-camera shadow-boxing tutorials exist in reasonable volume. Clean, controlled slow-motion (240fps) punch footage is THIN — most 'slow motion boxing' search results are broadcast-match compilations (two fighters, dynamic camera, copyrighted footage), not single-subject instructional slow-mo, so this specific sub-need should not be assumed solved. Muay Thai/kickboxing for the future engine shows promising per-technique depth (roundhouse kick alone has several independent sources) but was only spot-checked, not exhaustively mapped. Choreia: Hip-Hop foundations (bounce/rock/roll) and Salsa solo shines — the two priority styles — both clear the >=3-instructor bar with good full-body framing; Salsa's half-speed-then-full-speed teaching format is a natural substitute for slow-motion capture. Among the other 10 styles, House (loose legs/jacking) and Afrobeats (Zanku, Shaku Shaku, etc.) are similarly well-covered with named, comparable moves across multiple teachers; K-Pop choreography is extremely high-volume with mirroring as a confirmed, explicitly-labeled industry convention (directly answers the mirror-teaching question), but much of that content sits with agencies/studios and carries more reuse caution than independent teacher channels; Bachata solo only turned up ~2 recurring channels in this pass, short of the 3-instructor target and needing a deeper follow-up search. AIST++ (Google, CC-BY-4.0 on annotations) is confirmed as a real, high-quality, properly licensed 3D motion dataset spanning 10 street-dance genres — a strong supplement/validation source, though its genre list only partially overlaps Choreia's 12-style catalog and the license covers only the annotation layer, not necessarily the underlying original AIST source videos. Count-based (8-count) teaching is confirmed as a common convention, useful for aligning the rule engine to musical timing. Overall: none of the sources found are CC-licensed VIDEO (only AIST++'s annotation layer is CC-BY-4.0); all instructional YouTube content is under standard YouTube/creator terms, consistent with the family's existing 'extract landmarks for internal analysis, never redistribute source clips' posture, which should be treated as a policy assumption to keep validating, not a settled legal conclusion.

## RECOMMENDATIONS
- Treat Precision Striking + Tony Jeffries + ExpertBoxing as the confirmed 3-instructor baseline for JabLab core punches (jab/cross/hooks/uppercuts) and begin multi-video consensus extraction there first.
- Do NOT assume clean single-subject 240fps slow-motion punch footage exists in usable volume — run a dedicated deeper harvest (including sports-science/biomechanics YouTube channels, not just boxing-coach channels) before relying on this for the scorer's perturbation-reference pipeline.
- For the future Muay Thai/kickboxing engine, do a full per-technique harvest pass (teeps, knees, elbows, clinch, footwork) beyond roundhouse kick before committing engine scope.
- Lock in Hip-Hop (bounce/rock/roll) and Salsa (solo shines) as the launch styles for Choreia per the family's stated priority — both have real multi-instructor, well-framed source pools confirmed in this pass.
- Run a dedicated deeper harvest for Bachata solo specifically (only 2 channels found) before treating it as consensus-ready; House and Afrobeats are comparatively strong and can be built out sooner.
- Use AIST++ as a 3D ground-truth validation/calibration set for the deterministic scorer rather than as a primary per-style tutorial source, and verify the license status of the underlying original AIST source videos (separate from Google's CC-BY-4.0 annotation layer) before any commercial use.
- Treat K-Pop/agency-produced tutorial content as higher legal-caution priority than independent teacher channels, even though it is by far the highest-volume and best-framed cluster found, given rights-managed/commercial production.
- Given no CC-licensed VIDEO sources were found for JabLab or Choreia (only AIST++ annotations), reconfirm with the founder that the existing policy — extract pose landmarks for internal deterministic reference only, never redistribute source clips or ship them in-app — is the operating assumption for ALL of these sources, not just a subset.

## RISKS
- Slow-motion punch footage cluster is genuinely thin; if the scorer design depends on true high-frame-rate reference data (vs. standard 30fps tutorials), this is a real gap, not just an uncertain one.
- None of the harvested video sources are CC-licensed — all reuse for landmark-truth extraction relies on the family's existing 'internal analysis only, never redistribute' posture, which is a reasonable but not risk-free interpretation of standard YouTube ToS; worth a periodic re-check as the product scales.
- Bachata solo and general Muay Thai/kickboxing technique coverage were only shallowly searched — do not treat them as consensus-ready without a follow-up harvest.
- K-Pop content is dominated by commercial/agency-produced videos (1MILLION Dance Studio ecosystem, official crews), which carries higher rights-holder risk than hobbyist tutorial channels even for landmark-only internal use.
- AIST++'s CC-BY-4.0 claim applies specifically to Google's annotation layer; the original AIST source video license was not independently re-verified in this pass and has historically been more restrictive (research/non-commercial) — treat as unconfirmed for commercial use until checked directly against Google's current dataset terms page.

## ITEMS
### Precision Striking (YouTube @PrecisionBoxing)
- what: Boxing coach channel (Jason Van Veldhuysen, 1M+ subs) with weekly technique/tactics breakdowns covering jab, cross, hooks, uppercuts, footwork, defense.
- why: High-volume, well-framed single-instructor technique tutorials for JabLab core moves; large back-catalog makes multi-video consensus feasible when combined with other coaches.
- license: Standard YouTube license (not CC) — reference/study only, not redistribution
- cost: free (YouTube)
- maturity: active, large volume
- integration: Manual review + frame extraction for pose reference; cannot redistribute clips
- caveats: Standard YouTube ToS license, not CC-BY — using as 'source of landmark truth' for internal analysis is a gray area typical of ML dataset practice, but redistributing frames/clips is not permitted without permission.
- url: https://www.youtube.com/@PrecisionBoxing
### Tony Jeffries (YouTube @Tony_Jeffries)
- what: Former Olympic boxer, 2.5M+ subs, beginner-to-intermediate tutorials on stance, guard, basic punches, footwork, and shadow boxing.
- why: Second independent instructor for the >=3-instructor-per-movement consensus requirement; includes a dedicated shadow-boxing tutorial useful for full-body single-person demo footage.
- license: Standard YouTube license, not CC
- cost: free (YouTube)
- maturity: active, large volume
- integration: Manual/automated frame extraction for reference pose sets
- caveats: Same non-CC licensing caveat as other coach channels.
- url: https://www.youtube.com/@Tony_Jeffries
### ExpertBoxing (YouTube user/expertboxing + expertboxing.com)
- what: Long-running free boxing instruction channel/site (Johnny N) covering jab, cross, hooks, footwork, and fight strategy with detailed written breakdowns.
- why: Third independent instructor voice; combined with Precision Striking and Tony Jeffries gives a real >=3-instructor baseline for jab/cross/hook/uppercut consensus extraction.
- license: Standard YouTube/website license, not CC
- cost: free
- maturity: long-running, moderate video volume, extensive companion articles
- integration: Manual annotation; site articles useful for technique-checklist cross-referencing
- caveats: Video volume is lower than Precision Striking; some tutorials are older (lower resolution/framing quality).
- url: https://www.youtube.com/user/expertboxing
### 'What a Punch REALLY Does' 240 FPS Slow Motion (YouTube)
- what: Slow-motion (240fps) breakdown video of punch mechanics and impact.
- why: Directly answers the slow-motion punch footage requirement; useful for understanding punch kinematics/impact frames though likely single clip not a full library.
- license: Standard YouTube license
- cost: free
- maturity: single video
- integration: Reference only, not annotatable dataset
- caveats: Single video, not a systematic slow-motion library; framing/subject may not match desired boxing stance angle. Volume of true 240fps punch-specific (not general combat sports) footage on YouTube appears thin — most 'slow motion boxing' results are match highlight compilations (e.g. Canelo vs GGG) rather than clean instructional slow-mo, so this clu
- url: https://www.youtube.com/watch?v=E6QdhRGUoNM
### Slow Motion Boxing compilations (YouTube playlist + montage videos)
- what: Compilation/montage videos of professional bouts slowed down (not instructional, not controlled single-subject).
- why: Supplementary visual reference for punch trajectories but framing is broadcast/match footage (multiple fighters, dynamic camera), not clean single-person static-camera shadow boxing.
- license: Standard YouTube license, largely rebroadcast of copyrighted match footage
- cost: free
- maturity: moderate volume, mixed quality
- integration: Visual reference only — NOT usable as pose-truth source (broadcast camera angles, occlusion, two fighters)
- caveats: Poor fit for controlled reference extraction; flagged as weak/thin evidence for the specific 'clean single-person slow-mo' need in the family's data strategy.
- url: https://www.youtube.com/playlist?list=PLxHGAvDjWnNaR1nVq45IdRxhaKVxArfIW
### Shadow boxing tutorials — Tony Jeffries + 'Complete Shadow Boxing Tutorial' + 'Learn how PRO BOXERS Actually Shadow Box'
- what: Single-person, largely static-camera, full-body shadow-boxing instructional videos.
- why: Matches the JabLab single-person shadow-boxing full-body demo requirement closely; multiple independent creators give some multi-instructor coverage.
- license: Standard YouTube license
- cost: free
- maturity: moderate volume, growing (2025-2026 uploads present)
- integration: Good candidate for full-body pose reference extraction (single subject, front-facing, largely static camera)
- caveats: Camera framing/distance and zoom varies by creator; not verified whether full body stays in frame throughout — needs per-video QA before use.
- url: https://www.youtube.com/watch?v=rwAGGeOk4_Q
### Muay Thai roundhouse kick tutorials (multiple channels: Evolve MMA, Muay Thai Guy, general instructional playlist)
- what: Cluster of roundhouse-kick-specific tutorials (heavy bag drills, technique breakdowns, step-by-step guides) from several independent Muay Thai sources.
- why: Future kickboxing/Muay Thai engine seed content; roundhouse kick alone already has several independent instructor sources, suggesting >=3-instructor consensus is feasible for at least this one core te
- license: Standard YouTube/website license, not CC
- cost: free
- maturity: multiple independent sources, moderate-high volume for this one technique
- integration: Frame extraction per technique; would need broader search per additional Muay Thai technique (teep, knee, clinch, elbow) before committing to full engine
- caveats: Only roundhouse kick was searched in depth; coverage of other core Muay Thai techniques (teeps, elbows, clinch) not yet verified — treat as a promising but partial signal for the future engine.
- url: https://evolve-mma.com/blog/muay-thai-101-the-roundhouse-kick/
### Kickboxing basics/fundamentals tutorials (multiple beginner-course channels, incl. a full 'Absolute Beginners Course' playlist)
- what: Beginner kickboxing technique series covering guard, basic strikes, combinations.
- why: Supplementary future-engine seed content for kickboxing distinct from Muay Thai/boxing.
- license: Standard YouTube license
- cost: free
- maturity: moderate volume
- integration: Reference only
- caveats: Not deeply vetted for per-movement multi-instructor consensus; flagged as exploratory-stage evidence only.
- url: https://www.youtube.com/playlist?list=PLWqHYO8fTO-83cCDdTLTpY0pBtmLRXrrR
### Hip-Hop foundations tutorials — bounce/rock/roll cluster (multiple independent channels)
- what: Several independent creators teaching the specific foundational moves (bounce, rock, roll, skate) with dedicated tutorial videos, some explicitly 'Part 1/Part 2' beginner series.
- why: Directly matches Choreia's Hip-Hop-first requirement; the presence of at least 4-5 independent channels teaching the exact same named foundational moves (bounce/rock/roll/skate) makes a >=3-instructor
- license: Standard YouTube license, not CC
- cost: free
- maturity: good volume, spans multiple years (2020-2024) of independent uploads
- integration: Strong candidate cluster for first-style build; frame extraction per move name (bounce, rock, roll separately)
- caveats: Framing quality (static full-body camera) not individually verified per video — needs per-source QA pass.
- url: https://www.youtube.com/watch?v=E_zrWpFU5XE
### Salsa solo shines tutorials (multiple channels incl. Amanda's 'Follow Along Solo Footwork', 'Salsa Solo for Beginners' playlist)
- what: Dedicated solo-footwork ('shines') tutorials, some demonstrating 12 basic shine patterns at half-speed then full-speed, explicitly single-dancer full-body format.
- why: Directly matches Choreia's Salsa-solo-shines-second requirement; half-speed/full-speed demonstration format is unusually well-suited to reference-pose extraction (built-in slow-motion equivalent).
- license: Standard YouTube license, not CC
- cost: free
- maturity: good volume, dedicated playlists exist
- integration: Strong candidate — half-speed segments effectively substitute for slow-motion capture
- caveats: Instructor count for true 3+ per specific shine pattern not fully verified; only 2-3 distinct channels confirmed in this pass — needs deeper harvest before committing to full consensus pipeline.
- url: https://www.youtube.com/watch?v=C4fsMsgVN0w
### House dance basics — Loose Legs / Jacking tutorials (multiple channels incl. MihranTV, Jardy Santiago, Ricky 'Glytch' Evans)
- what: Dedicated tutorials for the two core house-dance fundamentals (loose legs, jacking), from at least 3-4 independently identifiable instructors.
- why: One of the strongest clusters found for the '10 other styles' catalog — named-move specificity (loose legs, jacking) plus multiple independent teachers supports real multi-instructor consensus.
- license: Standard YouTube license, not CC
- cost: free
- maturity: good volume, spans 2018-2023
- integration: Good candidate for second-tier style build-out
- caveats: None major; this was one of the better-covered clusters in the search.
- url: https://www.youtube.com/watch?v=3HyOEYlDx0g
### Afrobeats dance tutorials (Sherrie Silver, DancEmotion, Dancegodlloyd, ALL ABOUT DANCE, others)
- what: Cluster of named-move tutorials (Zanku, Shaku Shaku, Legwork, Sangra) from several distinct Afrobeats choreographers/channels.
- why: Good breadth for the 10-style catalog; specific move names recur across channels enabling per-move multi-instructor comparison similar to Hip-Hop.
- license: Standard YouTube license, not CC
- cost: free
- maturity: good volume, active as of 2026 uploads
- integration: Candidate for mid-tier style build; per-move (Zanku vs Shaku Shaku) source counting still needed
- caveats: Not verified whether individual videos maintain full-body static framing — some Afrobeats tutorial channels use dynamic/handheld camera work, which would hurt pose-extraction quality.
- url: https://www.youtube.com/watch?v=op992EFqG24
### K-Pop choreography tutorials + mirrored-practice convention (1MILLION Dance Studio ecosystem, R.P.M Dance Crew, dedicated 'mirrored' uploads)
- what: Extremely high-volume choreography tutorial ecosystem; explicit convention of publishing a 'mirrored' (horizontally flipped) version alongside the normal version so viewers can follow without mental left-right conversion.
- why: Confirms the mirror-teaching convention question directly (yes, mirroring is a well-established, explicitly-labeled K-pop tutorial practice) and gives Choreia a very high-volume, well-framed (typicall
- license: Standard YouTube license, not CC — official 1MILLION/agency content is often monetized/rights-managed
- cost: free
- maturity: very high volume, industry-standard practice
- integration: Excellent for framing quality and consensus volume; mirrored-vs-original pairing could even help validate left/right consistency in rule engine
- caveats: Much of this content is produced by dance studios/agencies with commercial rights — reuse for training data (even as visual reference only, per family policy) carries more legal caution than amateur tutorial channels; recommend treating official K-pop/agency videos as lower-priority/higher-risk sources compared to independent teacher channels.
- url: https://www.youtube.com/watch?v=70Y7VZL8qDo
### Bachata solo/styling tutorials (Bachata Dance Academy — Demetrio & Nicole, freelydance, others)
- what: Solo bachata basic-step and styling tutorials, several explicitly 'no partner needed' and demonstrating basic turn practice solo.
- why: Covers Choreia's bachata-solo item in the 10-style catalog; Bachata Dance Academy appears as a recurring, well-produced source across multiple videos (good for consistency).
- license: Standard YouTube license, not CC
- cost: free
- maturity: moderate volume
- integration: Usable but instructor diversity thinner than Hip-Hop/House/Afrobeats clusters — mostly 2 recurring channels (Bachata Dance Academy, freelydance) found in this pass
- caveats: Only 2 distinct channels clearly identified in this search pass, short of the >=3-instructor target — needs a deeper follow-up harvest specifically for Bachata before committing.
- url: https://www.youtube.com/watch?v=xhrdh-uFkog
### AIST++ Dance Motion Dataset (Google Research)
- what: Large-scale 3D dance motion capture dataset built from the AIST dance video database: 1,408 sequences across 10 dance genres, 30 subjects, 9-view camera calibration, SMPL pose parameters + 17 COCO-format 2D/3D joints, music-synced. Annotations licensed CC BY 4.0 by Google LLC.
- why: Directly matches the requested AIST++ CC-BY-4.0 supplement — a genuinely free, properly licensed, high-quality 3D pose-truth dataset spanning multiple dance genres (though the underlying source videos
- license: Annotations CC BY 4.0 (source videos from original AIST database — check underlying AIST video license separately, historically for non-commercial research use)
- cost: free
- maturity: mature, published (Google Research, used in multiple papers e.g. AI Choreographer/Bailando)
- integration: Directly ingestible 3D SMPL/joint data — best-fit within the family's 'no shipped ML classifier, deterministic engine' policy as ground-truth calibration/validation data, not as a training corpus for 
- caveats: The CC-BY-4.0 license covers Google's ANNOTATIONS; the underlying original AIST dance videos/database have historically had separate, more restrictive terms (research/non-commercial) — must verify current AIST source video license before any commercial use, only the annotation layer is confirmed CC-BY-4.0. Also the 10 genres in AIST++ are specific 
- url: https://google.github.io/aistplusplus_dataset/
### '8-count' breakdown dance tutorials (general cluster, e.g. MihranTV Quick 8 Count series, various slowed-down tutorials)
- what: Cluster of tutorials structured explicitly around teaching in musical 8-counts, often with slowed-down demonstration passes.
- why: Confirms count-based teaching convention is common across styles (especially Hip-Hop/commercial choreography), which is useful for building a rule engine that aligns pose landmarks to musical counts.
- license: Standard YouTube license
- cost: free
- maturity: moderate-high volume, cross-style
- integration: Reference for count-alignment methodology; not a distinct content source beyond the style-specific clusters above
- caveats: This is a teaching-convention confirmation rather than a discrete content cluster — do not double-count against per-style volume estimates.
- url: https://www.youtube.com/watch?v=SxzcgrHDegE


# ==== breadth-ostinato ====

## SUMMARY
Web-research inventory for Ostinato's string-instrument reference-video breadth harvest. Cello: CelloBello and tonebase's free tier are the two strongest multi-instructor free sources for open-string bowing, long bow, bow changes, and posture/setup, both with active YouTube channels for discovery. Camera-angle reality check (qualitative, not measured): pedagogy video is shot for teaching clarity, not landmark capture, so expect a real but incomplete-majority fraction of candidate videos to actually match Ostinato's seated right-front-diagonal V1 angle — a manual triage pass is recommended before committing to extraction tooling. URMP remains accessible via a request-gated download but is better suited to audio/score alignment than pose extraction given its ensemble camera framing; its current 2026 terms were not independently reconfirmed. Several audio-visual instrument-performance datasets with pre-computed pose/keypoints exist (Solos, Gan et al.'s MUSIC/Music-Gesture line, MUSIC-AVQA, VioPose/VioDat for violin, PianoMotion10M for piano) but none were confirmed to carry a permissive commercial license — all are best treated as methodology references or independent-baseline checks, not directly importable training/reference assets, pending a license read. Early-harvest anchors for violin, guitar, and piano teacher ecosystems were identified but not yet developed to the same >=3-instructor depth as cello. The instrument/bow-detector auto-labeling-from-public-video idea is explicitly flagged as a separate legal question from reference extraction under the family's OK-8 rule and is left for the coordinator to decide, with options and risk noted rather than resolved."

## RECOMMENDATIONS
- Adopt CelloBello + tonebase-free-tier as the two primary cello source pools (both multi-instructor, both free-accessible), and require >=3 distinct named instructors per target movement (open string, long bow, bow change, posture/setup) pulled across the two before calling any movement's reference 'consensus-verified' per the family rule.
- Do the camera-angle audit as an explicit, cheap first step before investing in extraction tooling: manually triage ~30-50 candidate cello videos across CelloBello + tonebase-free + generic YouTube search and tag each as {usable full-upper-body+bow, right-front-diagonal-ish} vs {unusable framing: extreme close-up on bow hand, front-on recital wide shot, side profile, obstructed}. Expect (based on how pedagogy video is typically shot for teaching clarity, not landmark capture) that a meaningful minority — plausibly under half — will match V1's angle well enough to use directly; most will need either cropping tricks, a wider net of candidate clips, or acceptance of a looser 'front-facing-ish, bow visible' filter rather than a strict diagonal match. This is a judgment estimate, not a measured statistic — budget an actual manual tagging pass rather than trusting this number.
- Treat Solos and the Gan et al. MUSIC/keypoint line of academic datasets as methodology references and as an independent-baseline sanity check for your own MediaPipe extraction pipeline, not as directly importable training assets, given unresolved licensing on the underlying YouTube video.
- Keep URMP as an audio/score-alignment reference dataset (it is not well-suited to the pose-reference extraction use case given its ensemble/wide-shot camera framing) and re-verify its 2026 access terms via the Google-form request before relying on it for anything shipped.
- On the instrument/bow-detector auto-labeling question: this is explicitly a SEPARATE legal question from reference (landmark) extraction under the family's OK-8 rule, which restricts detector *training* data to owned/consented footage. Do not fold 'extract poses from public video for scoring references' and 'auto-label public video to train a shipped bow/instrument detector' into the same bucket when presenting this to the coordinator — flag the detector-training option (bootstrapping labels from YouTube via an off-the-shelf detector run offline) explicitly as requiring a founder/coordinator decision, not something to proceed on by default.
- For violin/guitar/piano, this pass only establishes early-harvest anchors (one to two teacher-ecosystem channels each) — a full >=3-instructor breadth harvest per movement, matching the depth done here for cello, is still needed once each engine is actually scoped.

## RISKS
- License uncertainty: none of the academic datasets found (Solos, MUSIC/Music-Gesture, MUSIC-AVQA, VioPose/VioDat, PianoMotion10M) were confirmed in this pass to carry a permissive commercial-use license — most academic audio-visual datasets built from YouTube default to research-only terms and/or distribute only video IDs/links rather than re-hosted footage. Every one of these must have its actual LICENSE file/terms page read before any use beyond citation-as-methodology.
- Camera-angle mismatch: pedagogy video (cello, guitar, piano alike) is filmed for viewer clarity, not landmark-capture — front-on lecture shots, extreme bow-hand close-ups, and side profiles are common, and the seated right-front-diagonal angle Ostinato standardizes on is not a filming convention teachers optimize for. This could mean a smaller-than-hoped usable slice of any given channel's catalog, increasing the number of channels/videos needed to hit the >=3-instructor-per-movement consensus bar.
- URMP's actual 2026 access process (Google-form request) could not be verified as still active/maintained in this pass — treat as unconfirmed until directly checked.
- The instrument/bow-detector auto-labeling idea, if pursued, sits in a legal gray zone regarding whether analyzing/labeling public YouTube video offline to train a model constitutes a use the video's ToS or copyright permits — this is flagged per the task instructions as a decision for the coordinator, not resolved here.
- tonebase's genuinely free-tier content may be thinner than search snippets suggest (much of the deep technique content sits behind a 14-day trial or subscription) — do not assume the '100+ free lessons' figure holds specifically for advanced bowing/technique content versus beginner-level material.

## ITEMS
### CelloBello
- what: Nonprofit-adjacent free video-lesson platform (Peabody Institute affiliated) with masterclasses, bow-technique series (e.g. 'Joy of Feuillard' bow-technique blog+video series), posture/setup demos from name-brand pedagogues; has an active YouTube channel plus cellobello.org site.
- why: Best single hub for multi-instructor cello bowing/posture consensus footage — directly matches the 'multi-video consensus, >=3 instructors per movement' rule for open-string bowing, long bow, bow chan
- license: Free-to-view public site; standard YouTube ToS (no explicit CC license found) — treat as reference-extraction-only (pose/landmark analysis of a public video), not redistribution.
- cost: ?
- maturity: Established, actively maintained since ~2015.
- integration: Manually curate a shortlist of >=3 CelloBello instructors per target movement (open string, string crossing, bow change, spiccato/detache basics); extract MediaPipe landmarks offline, discard video.
- caveats: Camera angle on CelloBello masterclass videos is usually a stage/lecture front-on or side shot chosen for teaching clarity, not the seated right-front-diagonal V1 angle — expect to need cropping/re-angling judgement, not a clean stand-in.
- url: https://cellobello.org
### CelloBello YouTube channel
- what: Official YouTube channel mirroring cellobello.org video lessons and masterclasses.
- why: Search/browse layer on top of CelloBello's library; easier to scan thumbnails for usable full-body+bow framing before spending time on the main site.
- license: Standard YouTube ToS; public but not CC-licensed by default.
- cost: ?
- maturity: Active.
- integration: Use as the discovery/triage layer for CelloBello content.
- caveats: None beyond the general YouTube ToS caveat.
- url: https://www.youtube.com/channel/UCCM5ZPixzZmXpSbxLE1Njng
### tonebase Cello (free tier)
- what: Subscription platform with a substantial free tier: '100+ free online cello lessons' and free lesson segments from working professional cellists (e.g. Astrid Schween on right-hand/bow mechanics), plus a YouTube channel and masterclasses with artists like Amit Peled, Jan Vogler, Mischa Maisky.
- why: Second major multi-instructor source for bowing/posture consensus; free-tier segments are usable without a paid subscription, expanding the >=3-instructor requirement beyond CelloBello alone.
- license: Free-to-view but tonebase's own ToS likely restricts commercial reuse/scraping of full paid-course video; the free-tier segments and YouTube channel are the safer subset to use for landmark extraction.
- cost: ?
- maturity: Active, well-funded (raises across piano/guitar/violin/cello/flute/trumpet/voice too).
- integration: Use only the explicitly free lesson pages + tonebase's public YouTube channel; avoid touching paywalled course video.
- caveats: Much of tonebase's actual bowing-technique depth is behind the 14-day trial / subscription — the freely accessible slice may be thinner than it looks; verify per-video before building a reference pipeline around it.
- url: https://strings.tonebase.co/cello/free-lessons
### tonebase Cello YouTube channel
- what: tonebase's public YouTube presence, separate from the paywalled course platform.
- why: Additional public-video source of bowing demonstration content for consensus extraction.
- license: Standard YouTube ToS.
- cost: ?
- maturity: Active.
- integration: Discovery/triage layer, same pattern as CelloBello's channel.
- caveats: Content overlaps with paywalled site; confirm each specific video is actually public before use.
- url: https://www.youtube.com/channel/UC_a-NweaRJlzqairIaibYqA
### URMP (University of Rochester Multi-modal Music Performance) dataset
- what: 44 classical chamber pieces (duets–quintets) with synchronized musical score, individual-instrument audio, assembled audio+video, and frame/note-level ground-truth transcriptions; includes cello, violin, and other orchestral instruments.
- why: Directly requested URMP status recap. Gives synchronized audio+video+score ground truth — potentially useful for validating a rule engine's timing/pitch logic (not pose), or as a controlled dataset fo
- license: Access via a Google-form request to the creators (Rochester AIR lab); not a blanket open/CC license — usage terms should be confirmed on request, historically research-use oriented.
- cost: ?
- maturity: Mature (introduced ~2016, arXiv 1612.08727), still actively cited in 2025 papers (e.g. MT3, zero-shot source separation), but no confirmed 2026 update
- integration: Request-gated download; best used for audio/score-alignment validation rather than pose-reference extraction given ensemble/wide camera framing.
- caveats: Could not confirm current (2026) license text or whether the request form is still actively processed — flag as UNVERIFIED for present-day access status; original docs are ~2016-2018 vintage.
- url: https://labsites.rochester.edu/air/projects/URMP/URMP_doc.pdf
### Solos: A Dataset for Audio-Visual Music Analysis
- what: 755 YouTube solo-performance clips (>65 hours) across 13 instruments (including cello, violin, guitar), with per-frame OpenPose skeleton (upper body + hands) already computed for the soloist.
- why: Closest existing dataset to what Ostinato needs: real YouTube performance video + pre-computed 2D skeletons for string players. Directly useful for validating/bootstrapping the detector or for cross-c
- license: Dataset is metadata + YouTube video IDs/links (standard 'links to YouTube, not re-hosted content' pattern common in audio-visual ML datasets) — check the GitHub repo's LICENSE file directly before use; not confirmed as CC-permissive.
- cost: ?
- maturity: Published ECCV/ICASSP-adjacent workshop 2020 (arXiv 2006.07931), stable, moderately cited.
- integration: Good candidate to bootstrap an OFFLINE pose-quality baseline (compare MediaPipe vs their OpenPose skeletons) — but note this is model-evaluation, not necessarily 'reference truth' since Solos performe
- caveats: License unverified in this pass — must be checked in-repo before any training use; also since videos are YouTube-sourced and likely not consented for ML training in the OK-8 sense, this sits squarely in the 'separate legal question' bucket flagged below.
- url: https://github.com/JuanFMontesinos/Solos
### MUSIC / "Music Gesture for Visual Sound Separation" dataset (Gan et al., CVPR 2020)
- what: Curated set ("MUSIC", ~714+ videos in follow-on work) of solo/duet instrument-performance YouTube videos used with 2D keypoint (body+hand) detection for audio-visual source separation research; the CVPR2020 paper builds a keypoint-based motion representation of musicians.
- why: Another precedent for auto-labeling pose/keypoints on public performance video for a downstream (non-generative) task — technically and legally analogous to the instrument/bow-detector bootstrapping q
- license: Research paper; dataset built from YouTube — same caveat as Solos regarding no explicit permissive redistribution license for the underlying video.
- cost: ?
- maturity: Well-cited CVPR2020 paper, foundational in the audio-visual-gesture research line (also see MUSIC-AVQA, a follow-on QA dataset).
- integration: Reference point for methodology (how academic labs justify auto-pose-labeling YouTube video for research) rather than a directly importable asset for Ostinato.
- caveats: Academic 'research use' framing does not equal a green light for a shipped commercial detector — see legal flag below.
- url: https://openaccess.thecvf.com/content_CVPR_2020/papers/Gan_Music_Gesture_for_Visual_Sound_Separation_CVPR_2020_paper.pdf
### MUSIC-AVQA
- what: Audio-visual question-answering dataset built over ~22 instrument categories (including guitar and cello) sourced from YouTube performance videos.
- why: Further evidence of an established academic norm of scraping+auto-labeling public instrument-performance video; also a possible source of category-labeled instrument clips for a lightweight instrument
- license: Academic dataset release, terms typically restrict to non-commercial research use — verify on project page before any commercial use.
- cost: ?
- maturity: Active research dataset (CVPR2022-era), still referenced in 2025 surveys.
- integration: Not directly usable for a shipped closed-source app under its likely non-commercial research license; useful only as a reference architecture.
- caveats: Non-commercial research license is a near-certain blocker for shipped-product use — confirm exact terms if pursued.
- url: https://gewu-lab.github.io/MUSIC-AVQA/
### VioPose / VioDat (violin 4D pose dataset, WACV 2025)
- what: Purpose-built violin-performance dataset: 639 videos of 12 violinists (varied gender/age/size/skill) playing exercises and freestyle pieces, with 4D (3D+time) pose ground truth combining audiovisual inference.
- why: Directly relevant early-harvest signal for a future violin engine — shows a recent (2025), well-resourced academic effort specifically targeting the occlusion/bow problem in violin pose estimation, wh
- license: Academic dataset; likely research-only release — check the project page for the actual data-release terms (not confirmed as downloadable/open in this pass).
- cost: ?
- maturity: New (WACV 2025), state-of-the-art for the specific sub-problem of violin pose under occlusion.
- integration: Read the paper for its camera-angle assumptions and occlusion-handling approach — highly relevant prior art for how Ostinato should choose/validate its own standard camera angle for string instruments
- caveats: Could not confirm within this pass whether VioDat itself is downloadable/open or paper-only; treat as a methods reference until verified.
- url: https://arxiv.org/abs/2411.13607
### PianoMotion10M
- what: Large-scale piano-performance dataset: 116 hours, 10M annotated frames, synchronized piano audio + hand-pose ground truth (via top-down/top-view camera).
- why: Best current academic dataset for a future piano engine — piano posture/hand-motion is a well-instrumented ML problem already, unlike cello/violin.
- license: Academic release; check project repo for exact terms (not confirmed permissive in this pass).
- cost: ?
- maturity: 2025 dataset (arXiv 2406.09326), described as the first dataset integrating piano audio with corresponding hand motion at this scale.
- integration: Strong early-harvest candidate for the piano engine's hand-position scoring, once/if piano becomes a priority.
- caveats: Uses top-view camera framing, which is a different setup problem than Ostinato's likely seated diagonal camera — framing translation needed.
- url: https://arxiv.org/html/2406.09326v2
### IRMAS dataset
- what: Audio-only instrument-recognition dataset (cello, guitar (acoustic+electric), piano, violin, etc.) from the Music Technology Group at UPF.
- why: Not audio-visual, but a permissively-documented, long-standing academic dataset that could support an audio-side 'which instrument is playing' sanity classifier if ever needed as a complement to the v
- license: Documented on the MTG site — historically released for research use; check current terms on the page.
- cost: ?
- maturity: Long-established (originally ~2012), still cited as a standard benchmark.
- integration: Low relevance to the vision/pose problem directly; noted for completeness of the 'other datasets' ask.
- caveats: Audio-only — does not address the camera-angle or pose questions at all.
- url: https://www.upf.edu/web/mtg/irmas
### Justin Guitar (Justin Sandercoe)
- what: Fully free, structured beginner-to-advanced guitar curriculum on YouTube and justinguitar.com, widely regarded as the most complete free guitar teaching ecosystem, including posture/hand-position fundamentals.
- why: Early-harvest anchor for a future guitar engine — analogous role to CelloBello for cello: a single trusted, prolific, free, multi-topic teacher source.
- license: Free to view; standard site/YouTube ToS, not CC-licensed for reuse.
- cost: ?
- maturity: Very mature, long-running (since ~2007), huge back catalog.
- integration: Good discovery starting point once guitar engine work begins; would still need >=3-instructor consensus per family rule, so pair with 2+ other channels (e.g. Marty Music).
- caveats: Single-instructor bias risk — per family rule needs corroboration from other teachers before treating as scoring ground truth.
- url: https://www.justinguitar.com
### Marty Music (Marty Schwartz)
- what: Large free YouTube guitar-lesson channel (3.8M+ subscribers) covering technique, posture, and song-based lessons.
- why: Second-source guitar channel to satisfy the multi-instructor consensus rule alongside Justin Guitar.
- license: Standard YouTube ToS.
- cost: ?
- maturity: Mature, active.
- integration: Pair with Justin Guitar and a third channel for a 3-instructor guitar posture/technique consensus set when that engine is scoped.
- caveats: URL for the channel is a best-guess canonical handle based on search snippets — verify handle directly before relying on it.
- url: https://www.youtube.com/martymusic
### Hoffman Academy
- what: Free, structured beginner piano curriculum on YouTube (Joseph Hoffman), including a popular 'Piano Lessons for Beginners' playlist covering sitting posture through full songs.
- why: Early-harvest anchor for a future piano engine's posture/setup layer.
- license: Free to view; standard site/YouTube ToS.
- cost: ?
- maturity: Mature, large free catalog.
- integration: Pair with 2+ other piano-teaching channels for consensus per family rule before treating as reference truth.
- caveats: Posture demos on piano teaching channels are typically filmed front-on or overhead for hand visibility, not from a seated diagonal angle — same camera-angle mismatch issue as cello.
- url: https://www.hoffmanacademy.com


# ==== founder-free-validation ====

## SUMMARY
The founder-recording gate assumption in the existing Motion family gate-validation plans must be replaced with a founder-free validation ladder built on three legs: (a) public research datasets pairing RGB video with mocap/3D ground truth (AIST++ is the standout — CC-BY on annotations, commercially usable; MM-Fit is CC-BY on Zenodo; but Human3.6M, MPI-INF-3DHP, 3DPW, AMASS, and BEDLAM are all explicitly non-commercial-research-only under Max-Planck-style EULAs and should NOT be used for a shipped commercial product's internal QA without either a paid commercial license or written confirmation that 'internal-only validation, not training' is exempt — treat that distinction as unresolved/risky, not as an established legal safe harbor); (b) self-generated synthetic ground truth via Unity Perception (free, MIT-licensed toolkit, built-in keypoint/pose randomization, output owned entirely by us) or Blender + the official SMPL-X Blender addon (refactored May 2026) — both give exact, house-owned angle ground truth with zero licensing risk, at the cost of a domain gap vs. real phone video that must be characterized separately; (c) cheap paid human data — Fiverr custom exercise-video gigs run roughly $15-75 per short custom clip from an individual freelancer up to ~$2,000 for bulk (450-clip) libraries, giving a concrete cost anchor for commissioning small sets of founder-free demonstration/error clips with explicit rights-assignment language in the gig brief (get a written work-for-hire/license grant, since Fiverr/Upwork do not supply this by default); public physiotherapy goniometry education videos on YouTube give known-angle references for specific joint ROM claims but are copyrighted, non-downloadable-for-shipping content usable only for eyeballing/manual QA, not automated ground truth, and reproduction must stay minimal per copyright policy. University kinesiology/biomechanics motion-capture labs (e.g. CSUSB xREAL Lab, SFU Mocap Database, Stanford FAIR Center, University of Liverpool rehab dataset) are a viable partnership channel but require direct outreach — no ready-made public 'partner with us' pipeline was found, so this is a leads list, not a plug-in solution. TestFlight supports in-app consent flows for beta cohorts (Apple's Beta Testing Data collection is separate/automatic, but developers can build their own consent+recording flow inside the app itself; Apple's TestFlight terms restrict what data flows to Apple but do not block developer-built consent capture). Device/thermal/FPS benchmarking remains trivial and requires no accuracy-skill dependency — it only needs the founder to run the app on physical hardware, which stays unaffected by this whole problem.

## RECOMMENDATIONS
- Accuracy gate (angle-measurement correctness): Primary = AIST++ (CC-BY, commercial-safe) for full-body/dynamic-motion validation relevant to Choreia and Gravita; supplement with MM-Fit (CC-BY, Zenodo) for gym/repetition movements relevant to Gravita/JabLab conditioning drills. Before relying on either, re-verify the CC-BY scope directly on the Zenodo record page and the Google AIST++ site (annotations vs. underlying video may differ). Do NOT use Human3.6M / MPI-INF-3DHP / 3DPW / AMASS / BEDLAM for internal validation without emailing the license contact (ps-licensing@tue.mpg.de or smpl@max-planck-innovation.de / IMAR contact) to get written confirmation that 'internal QA, not model training, not distribution' is permitted under a free tier — assume no until that email is answered.
- Read the Fit3D /legal page directly (https://fit3d.imar.ro/legal) before using it — it is the single best domain-matched dataset (real fitness movements + real mocap) but its license status is unresolved from this research pass.
- Build a small in-house synthetic validation set with Unity Perception (free, permissive Unity Companion/package license, keypoint+pose randomization built in) or Blender + the official SMPL-X Blender addon — this is the only zero-licensing-risk path to arbitrarily many known-ground-truth poses/angles, and is well suited to testing the deterministic rule engine's angle math in isolation from the CV landmark step.
- Reliability gate (test-retest / same-movement consistency across body types): commission a small paid clip set via Fiverr (custom exercise/movement video gigs, ~$15-75/clip from individual freelancers, or bulk packages ~$2,000/450 clips) — write an explicit work-for-hire clause assigning full rights/license to Yula Lab into the gig brief before hiring, since platform default terms do not guarantee usable IP rights.
- Reach out to 1-2 university kinesiology/biomechanics motion-capture labs (e.g. CSUSB xREAL Lab, Stanford FAIR Center, SFU Mocap Database contacts) as a medium-term, higher-fidelity founder-free ground-truth channel — this needs direct relationship-building, not a self-serve dataset download, so start it now if it's wanted for a later gate.
- Use TestFlight beta cohorts with an in-app consent screen (built by us, not relying on Apple's automatic Beta Testing Data) to collect real, diverse, consenting users' movement videos over time as an ongoing/expanding validation corpus, once a beta cohort exists.
- Device/thermal/FPS benchmarking gate: confirmed trivial — the founder can run the app himself on his own devices; no data, no skill, no license question applies here. Keep this gate exactly as originally planned.

## RISKS
- The single most damaging mistake would be using Human3.6M, 3DPW, AMASS, MPI-INF-3DHP, or BEDLAM for 'internal validation' at a for-profit company on the assumption that 'we're not training on it, just checking accuracy' makes it fine — the license text on all of these explicitly says 'non-commercial scientific research' and in some cases explicitly bans any commercial-product-adjacent use; this needs a direct answer from the license holders, not an internal legal interpretation, before any use.
- Fit3D's actual license terms could not be retrieved in this pass (the /legal page didn't return content) — do not proceed with Fit3D until that page is read and license text captured verbatim.
- AIST++'s CC-BY covers Google's annotation layer specifically; the underlying AIST dance video itself may carry separate, less permissive terms from the original AIST database site — conflating the two could create a false sense that the whole pipeline is commercial-safe.
- Fiverr/Upwork freelancer gigs do not automatically transfer full commercial rights or model/talent releases — without an explicit written rights-assignment clause in the gig brief, using the resulting footage inside a shipped commercial app (even just as 'reference,' not shown to end users) could create takedown/likeness-rights exposure later.
- Physiotherapy/goniometry YouTube videos are copyrighted third-party content; they are fine for a human reviewer to eyeball, but reproducing frames or angle values from them at scale (e.g. scraping to build an automated ground-truth set) is a copyright violation, not merely a licensing gray area — this must stay 'manual spot-check reference only.'
- Synthetic ground truth (Unity Perception / Blender+SMPL-X) has zero licensing risk but a real domain-gap risk: validating against your own perfectly-labeled synthetic renders does not prove real-world (phone camera, real lighting, real body shapes) accuracy — it should be treated as a necessary-but-not-sufficient gate, always paired with at least one real-video-with-real-ground-truth dataset (AIST++/MM-Fit) or real paid human clips.

## ITEMS
### AIST++ (Google)
- what: 3D dance dataset: 5.2M SMPL-derived 3D keypoint annotations (multi-view triangulated, refined via OpenPose+bundle adjustment) paired with the underlying public AIST dance videos, 10 genres, 30 subjects.
- why: Best-fit accuracy validator: RGB video + independently-triangulated 3D angle ground truth, permissive license, directly usable to sanity-check on-device angle-measurement error on real (non-founder) h
- license: CC BY 4.0 on Google's annotations (explicitly stated on the dataset site). Underlying AIST source videos are separately licensed by AIST website — check aistdancedb.ongaaccel.jp terms before using the raw video, but the annotations themselves are com
- cost: Free download.
- maturity: Established (CVPR 2021), widely used, actively cited in 2026 papers (e.g. Motion-X).
- integration: Multi-view triangulated 3D keypoints in COCO-style format + camera params; straightforward to reproject and compare to our pose-estimator joint angles.
- caveats: Dance-specific motions — good for full-body dynamic-motion accuracy (relevant to Choreia/Gravita) but not a substitute for narrow-domain joints like handstand wrist loading or violin/cello bow-arm goniometry (Ostinato). Must separately confirm the raw-video license from AIST's own site since Google only licenses its annotation layer.
- url: https://google.github.io/aistplusplus_dataset/factsfigures.html
### MM-Fit
- what: 20 workout sessions, RGB+depth video time-synchronized with wearable IMU/accelerometer/gyroscope/heart-rate data, for exercise recognition and rep-counting.
- why: Usable as a secondary accuracy/reliability check for repetitive gym movements (squats, lunges, etc.) relevant to Gravita's calisthenics domain, video+sensor pairing lets us cross-validate rep-detectio
- license: Zenodo record uses Creative Commons Attribution (CC-BY) — permits commercial use with attribution per Zenodo's stated CC-BY terms.
- cost: Free.
- maturity: Established (IMWUT 2020), actively cited.
- integration: RGB+depth video, wearable sensor CSVs; no 3D mocap ground truth (IMU/depth only), so angle accuracy is coarser than AIST++ or Fit3D/Human3.6M.
- caveats: Confirm CC-BY applies to the whole Zenodo deposit, not just metadata — verify on the record page (zenodo.org/records/7607736) before shipping any derived internal report; no true skeletal mocap, so it's a weaker angle-truth source than marker-based datasets.
- url: https://zenodo.org/records/7607736
### Fit3D
- what: 3M+ images across 13 subjects x 4 RGB cameras with full 3D motion-capture ground truth and 3D body scans, covering fitness-specific exercises.
- why: Closest domain match to Gravita/general fitness movement accuracy validation — real mocap ground truth on actual exercise repertoire, not just walking/general-activity like Human3.6M.
- license: UNRESOLVED/uncertain from this research pass — the Fit3D site has a `/legal` license page that could not be read directly; sibling IMAR datasets (Human3.6M) from the same lab are academic/research-only with a paid commercial-license path, so assume F
- cost: Free for registered research use; commercial license likely requires contacting IMAR.
- maturity: Established (used in AIFit/CVPR work), maintained by the IMAR/Sminchisescu group.
- integration: Multi-view video + mocap-derived 3D joint positions; direct angle ground truth for real exercises.
- caveats: HIGH-PRIORITY CAVEAT: must fetch https://fit3d.imar.ro/legal and read the actual license text before any internal QA use — do not assume commercial-safe. Registration/access request required per the imar_vision_datasets_tools GitHub repo.
- url: https://fit3d.imar.ro/
### Human3.6M
- what: 3.6M frames, 11 actors, 4 synchronized cameras + mocap-derived 3D joint positions, classic large-scale pose benchmark (walking, sitting, everyday actions).
- why: Gold-standard mocap ground truth for validating baseline joint-angle accuracy on ordinary body poses (not exercise-specific) — useful as a general accuracy floor test for the shared pose-estimation pi
- license: Academic/research-only EULA; explicitly non-commercial, non-transferable, no sub-licensing; commercial licensing must be separately negotiated with the dataset owners (contact info on EULA page).
- cost: Free for registered academic use only.
- maturity: Very mature/canonical (2014, CVPR/PAMI), still a standard benchmark in 2026 papers.
- integration: 3D joint positions + multi-view video + depth; well-documented loaders (e.g. github.com/anibali/h36m-fetch).
- caveats: Read literally: 'internal QA use' at a for-profit company is very likely still 'commercial purpose' under this EULA's wording. Treat as OFF-LIMITS for a commercial app's validation pipeline unless a lawyer confirms internal-only benchmarking is exempted — do not risk it without written clarification from the maintainers.
- url: https://vision.imar.ro/human3.6m/eula.php
### MPI-INF-3DHP
- what: 3D human pose dataset with markerless mocap ground truth across indoor/outdoor/green-screen scenes, standing/general poses.
- why: Secondary general-pose accuracy benchmark, useful for testing robustness across different lighting/backgrounds relevant to at-home phone-camera capture.
- license: Released for academic research only, non-commercial, free to researchers at educational/research institutions.
- cost: Free for academic use.
- maturity: Established (3DV 2017), still commonly cited.
- integration: Multi-camera markerless mocap + video.
- caveats: Same commercial-use exclusion problem as Human3.6M — treat as research-only, do not use for a for-profit internal validation pipeline without written permission.
- url: https://vcai.mpi-inf.mpg.de/3dhp-dataset/
### 3DPW (3D Poses in the Wild)
- what: In-the-wild video paired with IMU-driven mocap ground truth (no lab/marker suit needed for capture), realistic outdoor/everyday scenes.
- why: Best 'real-world, non-lab' mocap-ground-truth dataset available — closer to how our users will actually film (handheld phone, natural background) than lab datasets like Human3.6M.
- license: Max-Planck-Gesellschaft license: non-exclusive, free, but explicitly 'sole purpose of performing non-commercial scientific research' — any commercial use, including in a commercial product/service, is expressly prohibited.
- cost: Free for non-commercial research.
- maturity: Established (ECCV 2018), widely used.
- integration: Video + IMU-derived SMPL pose parameters.
- caveats: Explicitly bans commercial use of any kind per the license text quoted on the license page — do not use for a shipped commercial app's validation without a paid Max-Planck commercial license.
- url: https://virtualhumans.mpi-inf.mpg.de/3DPW/license.html
### AMASS
- what: Large unified archive of many marker-based mocap datasets converted to a common SMPL parametric-body format — one of the largest motion libraries available.
- why: Could synthesize large volumes of ground-truth 3D pose sequences (including odd/rare movements) to stress-test the rule engine's angle math against known-correct joint trajectories, independent of any
- license: Max-Planck license: usage rights for 'non-commercial scientific research, non-commercial education, or non-commercial artistic projects' only; explicitly prohibits using the dataset to train models/algorithms for any commercial use; commercial licens
- cost: Free for non-commercial; paid commercial license available.
- maturity: Very mature, heavily used across the pose research community, actively maintained.
- integration: SMPL pose parameters (not raw video) — good for testing the geometry/angle-computation layer in isolation, not the CV/landmark-detection layer.
- caveats: Explicit commercial-use and commercial-training ban; internal QA at a for-profit company is a gray area worth a direct email to ps-licensing@tue.mpg.de before use rather than assuming 'internal only' is exempt.
- url: https://amass.is.tue.mpg.de/license.html
### BEDLAM / BEDLAM 2.0
- what: Large-scale synthetic (rendered) dataset of realistic bodies in motion with exact ground-truth 3D pose, camera, and clothing — designed explicitly to support pose-estimation research with perfect synthetic ground truth.
- why: A synthetic-ground-truth path (no real humans needed, no founder-recording dependency) that could validate the CV landmark pipeline against pixel-perfect known angles, and provides a template for how 
- license: Perceiving Systems PS:License 1.0 — non-commercial research/education/artistic use only, explicitly bans commercial, pornographic, military, surveillance uses and (BEDLAM 2.0) content-integrity-violating uses; commercial license path is smpl@max-plan
- cost: Free for non-commercial research; paid commercial license required otherwise.
- maturity: Active/current (BEDLAM 2.0 paper is Nov 2025), state-of-the-art synthetic dataset.
- integration: Rendered video + exact 3D ground truth + SMPL-X params; good template even if the dataset itself can't be used commercially.
- caveats: Cannot be used directly for commercial internal QA without a paid license — but its open rendering pipeline/methodology is a useful reference for building our OWN synthetic set (see Unity Perception / Blender+SMPL-X items below) which we would own outright.
- url: https://bedlam.is.tuebingen.mpg.de/license.html
