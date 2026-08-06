// Required symbols fail during lookup. Optional symbols either use a fallback
// or throw an [UnsupportedError] when first used.

/// Tracks which optional feature groups the loaded library provides.
class NativeSymbolTable {
  final _resolvedFeatures = <String>{};
  final _missingFeatures = <String>{};

  /// Feature groups that did not resolve, in the order they were attempted.
  Iterable<String> get missingFeatures => _missingFeatures;

  /// Whether [feature] was looked up and resolved completely.
  ///
  /// An unknown feature is not considered available. This makes misspelled
  /// feature names fail closed instead of silently reporting support.
  bool provides(String feature) => _resolvedFeatures.contains(feature);

  /// Looks up a group of symbols that entered the C ABI together.
  ///
  /// Lookup stops at the first failure. Assignments made by [lookUp] before
  /// that failure remain assigned. Use [provides] to check the complete group.
  ///
  /// Returns whether the group resolved.
  bool lookUpGroup(String feature, void Function() lookUp) {
    try {
      lookUp();
      _resolvedFeatures.add(feature);
      _missingFeatures.remove(feature);

      return true;
    } catch (_) {
      _resolvedFeatures.remove(feature);
      _missingFeatures.add(feature);

      return false;
    }
  }

  /// Unwraps an optional symbol at its first use.
  ///
  /// [api] names the requested operation. [feature] names its native feature
  /// group when available.
  T requireSymbol<T>(T? symbol, String api, {String? feature}) {
    if (symbol != null) return symbol;
    final message = feature == null
        ? '$api is not supported by the loaded native library'
        : '$api requires native support for $feature';
    throw UnsupportedError(message);
  }
}
