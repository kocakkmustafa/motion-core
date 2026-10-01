# motion_media

`SourceProjectionDecoder`, `SourceProjectionPin`, `SourceProjectionData` and
`SourceProjectionError` are public structural source-identity APIs. An app must
compile an immutable expected projection SHA-256, source catalog SHA-256,
source manifest SHA-256, course SHA-256, app ID and variant/HOLD counts into
its own binary before calling the decoder on bounded, canonical JSON bytes.

`VerifiedMediaCache` is an internal transport/lifetime component. Applications
must not import `src/verified_media_cache.dart` directly; its arbitrary byte
stream and native initializer are not a production release decision.

A successful decode means only that the bytes match those app-owned pins and
have the expected source-row shape. It does **not** approve rights, reviewer
decisions, media files, playback, release, or learner progress. The signed
release verifier remains internal and `ReleaseProductionGate` remains closed
until a separate reviewed production root and attestation path exist.
