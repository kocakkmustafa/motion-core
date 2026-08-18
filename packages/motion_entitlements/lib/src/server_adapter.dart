import 'entitlement_status.dart';

/// Reserved for the future Motion Pass server-side verification gate
/// (00-AILE-MIMARISI.md §8.3) — not wired to any transport until that gate
/// opens. The interface exists now so callers can code against a stable
/// shape ahead of time, without a circular dependency later. Returns `null`
/// (fail-closed) when the server holds no opinion, rather than fabricating
/// a status.
abstract class ServerAdapter {
  Future<EntitlementStatus?> verify(String productId);
}
