import 'dart:ffi';

import 'package:flutter/foundation.dart';

typedef _NativeVertexRepack = Int32 Function(
  Uint32,
  Pointer<Void>,
  UintPtr,
  Uint32,
  Pointer<Void>,
  UintPtr,
);

/// Synchronously expands a packed layout into caller-owned destination bytes.
///
/// Returns one on success, zero for an unsupported layout, or minus one for
/// invalid spans. Neither pointer is retained. Source and destination must not
/// overlap, and both spans must remain valid throughout the call.
typedef NativeVertexRepack = int Function(
  int layout,
  Pointer<Void> source,
  int sourceBytes,
  int vertexCount,
  Pointer<Void> destination,
  int destinationCapacity,
);

/// Whether this platform enables the optional native conversion path.
bool get nativeVertexRepackingEnabled =>
    defaultTargetPlatform == TargetPlatform.android &&
    const bool.fromEnvironment('MAPLIBRE_NATIVE_REPACKING', defaultValue: true);

/// Resolves the session-independent converter when the library provides it.
NativeVertexRepack? lookupNativeVertexRepack(DynamicLibrary library) {
  if (!nativeVertexRepackingEnabled) return null;
  try {
    return library.lookupFunction<_NativeVertexRepack, NativeVertexRepack>(
      'maplibre_repack_vertices_v1',
    );
  } on ArgumentError {
    return null;
  }
}
