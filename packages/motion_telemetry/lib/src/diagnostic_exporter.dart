class DiagnosticExportRequest {
  const DiagnosticExportRequest({required this.userPreviewed, required this.userConfirmed});

  final bool userPreviewed;
  final bool userConfirmed;
}

/// Diagnostic bundles never leave the device automatically. Fail-closed:
/// [export] returns the payload only when the caller attests the user has
/// both previewed the bundle and explicitly confirmed sending it —
/// otherwise it returns `null`.
class DiagnosticExporter {
  const DiagnosticExporter();

  String? export(DiagnosticExportRequest request, String payload) {
    if (!request.userPreviewed || !request.userConfirmed) return null;
    return payload;
  }
}
