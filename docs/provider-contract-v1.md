# Motion provider contract v1

`motion_core` 0.13.0 adds an optional pure Dart declaration and selection API.
Existing pose, camera, account and session APIs remain unchanged. All five
consumer Git pins remain unchanged until each owner explicitly adopts a
published immutable revision. There is no implicit migration or model download.

`MotionProviderManifest` binds provider/version, production or replay mode,
runtime ABI, input schema, coordinate space, model SHA-256 and a map of named
capabilities. Domain task IDs, variants, views, phases and learning progress
remain app-owned. Unknown contract versions and malformed values fail closed.

A capability is `unsupported`, `calibrationRequired` or `validated`. The last
requires model, calibration and acceptance hashes; it does not create accuracy
or expert acceptance. `MotionProviderRequirement` must receive hashes computed
from actual loaded bytes plus the independently reviewed acceptance hash owned
by the app. Copying candidate declarations into that receipt defeats the gate.
The receipt/manifest are metadata, not a signature verifier or trust boundary.
The acceptance artifact must bind the exact task, model, calibration, runtime,
input/view/variant and frozen independent evaluation. No such yoga artifact is
supplied or claimed in this change.

`inspect` returns an explicit non-ready reason for absent support, calibration,
ABI/input/space mismatch, artifact mismatch, absent acceptance or wrong mode.
Production requirements reject replay even if all hashes match. Fixture/fake
providers and manifests belong in tests/tooling; a production constructor must
not accept a mode flag from a user preference or enable replay via fallback.

`MotionProviderSelection.select` changes the active identity only after a
ready result. A rejected candidate preserves active and previous identities.
`rollback` is explicit and rechecks actual bytes and acceptance; it never
assumes an old artifact is still compatible. Selection is in-memory only.
App owners retire capture/observation resources and start a fresh session on
any model/calibration/account/lifecycle change, and decide separately whether
historical records are comparable. No inference outcome may automatically
become a practice/mastery record through this API.

Training is deferred. First-party intake/split/one-shot holdout preparation
from 8455a56b is retained and is not rerun or replaced. Synthetic tests here
prove contract logic only. Actual training, calibration, physical device,
qualified review and release acceptance remain separate gates.
