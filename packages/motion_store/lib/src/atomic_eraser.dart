class ComponentEraseResult {
  const ComponentEraseResult({
    required this.component,
    required this.succeeded,
    this.error,
  });

  final String component;
  final bool succeeded;
  final Object? error;
}

class EraseAllReport {
  const EraseAllReport(this.results);

  final List<ComponentEraseResult> results;

  bool get allSucceeded => results.every((r) => r.succeeded);
}

/// Coordinates whole-account erasure (journal, projection, diagnostic
/// bundle, …) across storage components that cannot share one real
/// transaction. Fail-closed in the way that matters for delete-my-data:
/// every component is still attempted even if an earlier one fails — so
/// one broken component can never block the others from being erased —
/// and the report never claims success unless every component actually
/// succeeded.
class AtomicEraser {
  const AtomicEraser(this._components);

  final Map<String, Future<void> Function()> _components;

  Future<EraseAllReport> eraseAll() async {
    final results = <ComponentEraseResult>[];
    for (final entry in _components.entries) {
      try {
        await entry.value();
        results.add(ComponentEraseResult(component: entry.key, succeeded: true));
      } catch (e) {
        results.add(ComponentEraseResult(component: entry.key, succeeded: false, error: e));
      }
    }
    return EraseAllReport(results);
  }
}
