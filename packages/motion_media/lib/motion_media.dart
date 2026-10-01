/// Local byte integrity, playback lifetime, and structural source identity.
///
/// [SourceProjectionDecoder] checks app-pinned source bytes only. Its result
/// never grants release, rights, media playback, or learner progress authority.
/// A release catalog, reviewer approval, transport, caption validation and
/// native device acceptance must be supplied by separate layers.
library;

export 'src/release_production_gate.dart';
export 'src/source_projection.dart'
    show
        SourceProjectionDecoder,
        SourceProjectionPin,
        SourceProjectionData,
        SourceProjectionError;
